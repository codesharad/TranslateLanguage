"""One-leg translation session.

A call has two legs. Each WebSocket is one speaker: their microphone is
recognized in whatever language they use, then translated and spoken in the
other person's preferred language.
"""

from __future__ import annotations

import asyncio
import time
import uuid
import zlib
from collections.abc import Awaitable, Callable
from typing import Any

import structlog
from fastapi import WebSocket

from app.hub import CallRoom
from app.audio.pcm import LatencyProbe, now_ms
from app.audio.vad import EndpointingVad
from app.config import Settings
from app.languages import is_auto, lookup, same_language, voice_for
from app.pipeline.base import SttPartial
from app.providers.factory import build_stt, build_translator, build_tts
from app.protocol import (
    ControlType,
    FrameKind,
    PcmFrame,
    SessionReady,
    SessionStart,
    dumps,
    loads,
)

log = structlog.get_logger("session")

SendFn = Callable[[bytes | str], Awaitable[None]]


class TranslationLeg:
    def __init__(
        self,
        ws: WebSocket,
        settings: Settings,
        start: SessionStart,
        send_to_peer: SendFn,
        send_local: SendFn,
        room: CallRoom,
    ) -> None:
        self._ws = ws
        self._settings = settings
        self._start = start
        self._send_to_peer = send_to_peer
        self._send_local = send_local
        self._room = room
        self._vad = EndpointingVad(settings)
        self._stt = build_stt(settings)
        self._mt = build_translator(settings)
        self._tts = build_tts(settings)
        self._closed = asyncio.Event()
        self._tts_generation = 0
        self._tts_task: asyncio.Task[None] | None = None
        self._seq_out = 0
        self._last_partial = ""
        self._probe: LatencyProbe | None = None
        # True once the current sentence is finished. The next sentence then gets a new id,
        # even while the voice for the previous one is still playing.
        self._utt_closed = False
        raw_src = (start.src_lang or "").strip()
        self._hear_lang = (start.hear_lang or "").strip()
        if not self._hear_lang and not is_auto(raw_src):
            self._hear_lang = raw_src
        self._src_lang = "auto"
        self._dst_lang = start.dst_lang
        self._spoken_lang = ""
        self._stt_pump: asyncio.Task[None] | None = None
        self._heard_speech = False
        self._last_rx = time.monotonic()
        self._speaker_tag = zlib.crc32(start.peer_id.encode()) & 0xFFFF
        self._mt_seq = 0

    async def run(self) -> None:
        self._stt.prepare_detection(self._hear_lang, self._dst_lang)
        own = lookup(self._hear_lang)
        if own and self._settings.resolved_stt() == "azure":
            # Each phone's language is known, so recognize only that. Guessing between the two
            # languages heard Hindi as English and the reverse, and echoes as the wrong language.
            self._spoken_lang = own.stt_code
            await self._stt.start(own.stt_code)
        elif self._settings.resolved_stt() == "azure":
            await self._stt.start("auto")
        else:
            await self._stt.start(self._hear_lang or self._dst_lang or "en-IN")
        await self._send_local(
            dumps(
                SessionReady(
                    call_id=self._start.call_id,
                    frame_ms=self._settings.frame_ms,
                    sample_rate_hz=self._settings.sample_rate_hz,
                    provider=self._settings.pipeline_provider,
                )
            )
        )
        log.info(
            "leg.stt",
            provider=self._settings.resolved_stt(),
            call_id=self._start.call_id,
            peer=self._start.peer_id,
            src="auto",
            hear=self._hear_lang,
            dst=self._dst_lang,
        )
        reader = asyncio.create_task(self._read_uplink(), name="uplink")
        self._stt_pump = asyncio.create_task(self._pump_stt(), name="stt-pump")
        watchdog = asyncio.create_task(self._watchdog(), name="watchdog")
        try:
            await self._closed.wait()
        finally:
            reader.cancel()
            watchdog.cancel()
            if self._stt_pump:
                self._stt_pump.cancel()
            if self._tts_task:
                self._tts_task.cancel()
            await self._stt.close()
            await self._tts.close()

    def stop(self) -> None:
        self._closed.set()

    async def _read_uplink(self) -> None:
        try:
            while not self._closed.is_set():
                message = await self._ws.receive()
                if message.get("type") == "websocket.disconnect":
                    break
                self._last_rx = time.monotonic()
                data = message.get("bytes")
                if data:
                    frame = PcmFrame.unpack(data)
                    if self._room.uplink_is_echo(self._start.peer_id):
                        log.debug("echo.drop", speaker_id=self._start.peer_id, tag=frame.speaker_tag)
                        continue
                    if self._settings.crosstalk_guard and self._room.audible_elsewhere(self._start.peer_id):
                        continue
                    await self._stt.push_pcm(frame.pcm)
                    tts_busy = self._tts_task is not None and not self._tts_task.done()
                    if self._settings.relay_original_voice and not tts_busy and frame.pcm:
                        await self._relay_pcm(frame.pcm)
                    started, ended, _ = self._vad.push(frame.pcm)
                    if started:
                        self._heard_speech = True
                    if started and self._settings.barge_in:
                        await self._cancel_tts()
                    if ended:
                        self._begin_utterance()
                        self._probe.mark("vad_end")
                    continue
                text = message.get("text")
                if text:
                    await self._on_control(text)
        except Exception as exc:  # noqa: BLE001
            log.warning("uplink.closed", error=str(exc))
        finally:
            self.stop()

    async def _relay_pcm(self, pcm: bytes) -> None:
        self._room.mark_receivers_playing(
            self._start.peer_id, len(pcm), self._settings.sample_rate_hz
        )
        self._seq_out += 1
        await self._send_to_peer(
            PcmFrame(
                seq=self._seq_out,
                kind=FrameKind.DOWNLINK_PCM,
                utterance_end=False,
                pcm=pcm,
                speaker_tag=self._speaker_tag,
            ).pack()
        )

    async def _watchdog(self) -> None:
        while not self._closed.is_set():
            await asyncio.sleep(5)
            if time.monotonic() - self._last_rx > 30:
                log.warning("leg.timeout", peer=self._start.peer_id)
                self.stop()
                try:
                    await self._ws.close(code=4000)
                except Exception:
                    return

    async def _on_control(self, raw: str) -> None:
        try:
            payload = loads(raw)
        except Exception:
            return
        if payload.get("type") == ControlType.PING:
            await self._send_local(dumps({"type": ControlType.PONG, "t": payload.get("t")}))
            return
        if payload.get("type") != ControlType.LANGUAGES_SET:
            return
        hear = payload.get("hear_lang") or ""
        if hear and not is_auto(hear):
            await self.set_hear_language(hear)
        dst = payload.get("dst_lang") or ""
        if not dst or is_auto(dst):
            return
        await self.set_target_language(dst)

    async def set_hear_language(self, hear: str) -> None:
        """This phone's user switched the language they speak: recognize that language now."""
        own = lookup(hear)
        if own is None or own.stt_code == self._hear_lang or same_language(own.stt_code, self._hear_lang):
            return
        self._hear_lang = own.stt_code
        self._spoken_lang = own.stt_code
        self._start.hear_lang = own.stt_code
        log.info("languages.hear", hear=own.stt_code, call_id=self._start.call_id, peer=self._start.peer_id)
        switch = getattr(self._stt, "switch_language", None)
        if switch is not None and self._settings.resolved_stt() == "azure":
            self._utt_closed = True
            await switch(own.stt_code)

    async def set_target_language(self, dst: str) -> None:
        """Point translation and TTS at the listener's preferred language.

        Speech recognition stays on automatic detection. Changing what the
        other person wants to hear must not restart this recognizer.
        """
        if dst == self._dst_lang:
            return
        self._dst_lang = dst
        self._start.dst_lang = dst
        self._start.voice = voice_for(dst)
        log.info("languages.target", dst=dst, call_id=self._start.call_id, peer=self._start.peer_id)
        await self._cancel_tts()

    async def _pump_stt(self) -> None:
        async for partial in self._stt.results():
            try:
                await self._on_stt(partial)
            except Exception:
                # One failed translation must not end captions for the rest of the call.
                log.exception("stt.handle_failed", peer=self._start.peer_id)
                self._utt_closed = True

    async def _on_stt(self, partial: SttPartial) -> None:
        text = (partial.text or "").strip()
        if not text:
            return
        if text.startswith("[stt-error]"):
            log.warning("subtitle.stt_error", message=text, peer=self._start.peer_id)
            await self._send_local(
                dumps({"type": ControlType.ERROR, "code": "stt", "message": text})
            )
            return
        self._heard_speech = True
        partial = SttPartial(
            text=text,
            is_final=partial.is_final,
            confidence=partial.confidence,
            language=partial.language,
        )

        self._begin_utterance()
        if self._probe.stt_first_partial is None:
            self._probe.mark("stt_first_partial")

        source = self._remember_spoken(partial.language)
        if not partial.is_final:
            self._last_partial = partial.text
            await self._emit_local(partial.text, is_final=False, language=source)
            self._schedule_partial_mt(partial.text)
            return

        self._probe.mark("stt_final")
        self._mt_seq += 1  # a late partial translation must not overwrite the final one
        self._last_partial = ""
        await self._emit_local(partial.text, is_final=True, language=source)
        translated = await self._translate(partial.text, source)
        self._probe.mark("mt_done")
        if translated:
            await self._emit_remote(translated, is_final=True)
            self._utt_closed = True
            await self._speak(translated, committed=True, probe=self._probe)
        else:
            log.info("subtitle.untranslated", text=partial.text, src=source, dst=self._dst_lang)
            self._utt_closed = True

    def _begin_utterance(self) -> None:
        if self._probe is None or self._utt_closed:
            self._probe = LatencyProbe(utterance_id=uuid.uuid4().hex[:12])
            self._utt_closed = False

    def _schedule_partial_mt(self, text: str) -> None:
        if not self._settings.partial_translate or not text.strip():
            return
        self._mt_seq += 1
        seq = self._mt_seq
        utterance = self._probe.utterance_id if self._probe else ""
        asyncio.create_task(self._partial_mt(text, seq, utterance))

    async def _partial_mt(self, text: str, seq: int, utterance: str) -> None:
        await asyncio.sleep(0.04)
        if seq != self._mt_seq:
            return
        if self._probe is None or self._probe.utterance_id != utterance:
            return
        translated = await self._translate(text, self._spoken_lang)
        if seq != self._mt_seq or not translated:
            return
        if self._probe is None or self._probe.utterance_id != utterance:
            return
        await self._emit_remote(translated, is_final=False)

    def _subtitle(self, kind: str, text: str, language: str, is_final: bool) -> dict[str, Any]:
        return {
            "type": kind,
            "text": text,
            "language": language.split("-")[0],
            "bcp47": language,
            "is_final": is_final,
            "utterance_id": self._probe.utterance_id if self._probe else "",
        }

    def _remember_spoken(self, language: str) -> str:
        detected = (language or "").strip()
        if detected and not is_auto(detected):
            self._spoken_lang = detected
        return self._spoken_lang

    async def _translate(self, text: str, source: str) -> str:
        if source and same_language(source, self._dst_lang):
            return text.strip()
        return (await self._mt.translate(text, source, self._dst_lang)).strip()

    async def _emit_local(self, text: str, *, is_final: bool, language: str = "") -> None:
        if not text:
            return
        payload = self._subtitle(
            ControlType.SUBTITLE_LOCAL,
            text,
            language or self._spoken_lang or self._hear_lang or self._dst_lang,
            is_final,
        )
        log.info(
            "subtitle.emit",
            type=payload["type"],
            language=payload["language"],
            is_final=is_final,
            peer=self._start.peer_id,
            text=text,
        )
        await self._send_local(dumps(payload))

    async def _emit_remote(self, text: str, *, is_final: bool) -> None:
        if not text:
            return
        payload = self._subtitle(ControlType.SUBTITLE_REMOTE, text, self._dst_lang, is_final)
        log.info(
            "subtitle.emit",
            type=payload["type"],
            language=payload["language"],
            is_final=is_final,
            peer=self._start.peer_id,
            text=text,
        )
        await self._send_to_peer(dumps(payload))

    async def _cancel_tts(self) -> None:
        self._tts_generation += 1
        if self._tts_task and not self._tts_task.done():
            self._tts_task.cancel()
            self._room.clear_playback(self._start.peer_id)
            await self._send_to_peer(
                dumps(
                    {
                        "type": ControlType.TTS_CANCEL,
                        "call_id": self._start.call_id,
                        "utterance_id": self._probe.utterance_id if self._probe else "",
                        "generation": self._tts_generation,
                    }
                )
            )

    async def _speak(self, text: str, committed: bool, probe: LatencyProbe | None = None) -> None:
        if not text:
            return
        self._tts_generation += 1
        generation = self._tts_generation
        if self._tts_task and not self._tts_task.done():
            self._tts_task.cancel()
            await self._send_to_peer(
                dumps(
                    {
                        "type": ControlType.TTS_CANCEL,
                        "call_id": self._start.call_id,
                        "utterance_id": self._probe.utterance_id if self._probe else "",
                        "generation": generation,
                    }
                )
            )
        self._tts_task = asyncio.create_task(
            self._tts_loop(text, generation, committed, probe),
            name="tts",
        )

    async def _tts_loop(
        self, text: str, generation: int, committed: bool, probe: LatencyProbe | None = None
    ) -> None:
        utterance_id = probe.utterance_id if probe else ""
        if self._settings.half_duplex:
            await self._send_to_peer(
                dumps({"type": ControlType.DUCK, "call_id": self._start.call_id, "duck": True})
            )
        await self._send_to_peer(
            dumps(
                {
                    "type": ControlType.TTS_START,
                    "call_id": self._start.call_id,
                    "utterance_id": utterance_id,
                    "generation": generation,
                    "committed": committed,
                }
            )
        )
        first = True
        try:
            async for pcm in self._tts.stream_pcm(text, self._dst_lang, voice_for(self._dst_lang)):
                if generation != self._tts_generation:
                    return
                if first and probe:
                    probe.mark("tts_first_byte")
                    await self._send_local(
                        dumps(
                            {
                                "type": ControlType.LATENCY,
                                "call_id": self._start.call_id,
                                "utterance_id": utterance_id,
                                "stages_ms": probe.stages_ms(),
                                "server_now_ms": now_ms(),
                            }
                        )
                    )
                    first = False
                self._seq_out += 1
                frame = PcmFrame(
                    seq=self._seq_out,
                    kind=FrameKind.DOWNLINK_PCM,
                    utterance_end=False,
                    pcm=pcm,
                    speaker_tag=self._speaker_tag,
                )
                self._room.mark_receivers_playing(
                    self._start.peer_id, len(pcm), self._settings.sample_rate_hz
                )
                await self._send_to_peer(frame.pack())
            await self._send_to_peer(
                dumps(
                    {
                        "type": ControlType.TTS_END,
                        "call_id": self._start.call_id,
                        "utterance_id": utterance_id,
                        "generation": generation,
                    }
                )
            )
        except asyncio.CancelledError:
            raise
        finally:
            if self._settings.half_duplex:
                await self._send_to_peer(
                    dumps({"type": ControlType.DUCK, "call_id": self._start.call_id, "duck": False})
                )
            # The probe is not cleared here: the next sentence may already be in progress.
