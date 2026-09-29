"""Sarvam Saaras realtime STT.

Protocol: wss://api.sarvam.ai/speech-to-text-realtime/ws
  send  {"event":"audio_input","audio":"<base64 linear16>"}
  recv  transcript.partial | transcript.final | vad.speech_start | error

Manual endpointing: we already run Silero locally, so we send speech_start /
speech_end and keep Sarvam's VAD as a backup (endpointing=vad, silence 180ms).
"""

from __future__ import annotations

import asyncio
import base64
from collections.abc import AsyncIterator
from urllib.parse import urlencode

import orjson
import structlog
from websockets.asyncio.client import connect

from app.config import Settings
from app.pipeline.base import SttPartial, StreamingStt

log = structlog.get_logger("sarvam-stt")


class SarvamStreamingStt(StreamingStt):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._queue: asyncio.Queue[bytes | None] = asyncio.Queue()
        self._results: asyncio.Queue[SttPartial | None] = asyncio.Queue()
        self._language = "hi-IN"
        self._task: asyncio.Task[None] | None = None
        self._ws = None

    async def start(self, language: str) -> None:
        self._language = language
        self._queue = asyncio.Queue()
        self._results = asyncio.Queue()
        self._task = asyncio.create_task(self._run(), name="sarvam-stt")

    async def push_pcm(self, pcm: bytes) -> None:
        await self._queue.put(pcm)

    def results(self) -> AsyncIterator[SttPartial]:
        return self._iter()

    async def _iter(self) -> AsyncIterator[SttPartial]:
        while True:
            item = await self._results.get()
            if item is None:
                return
            yield item

    async def reconfigure(self, language: str) -> None:
        self._language = language
        if self._ws is not None:
            await self._ws.send(
                orjson.dumps({"event": "config.update", "language_code": language}).decode()
            )
            return
        await super().reconfigure(language)

    async def close(self) -> None:
        await self._queue.put(None)
        if self._task:
            await asyncio.gather(self._task, return_exceptions=True)
            self._task = None
        await self._results.put(None)

    async def _run(self) -> None:
        params = urlencode(
            {
                "language_code": self._language,
                "model": self._settings.sarvam_stt_model,
                "stream_type": "fast",
                "mode": "transcribe",
                "endpointing": "vad",
                "encoding": "linear16",
                "sample_rate": str(self._settings.sample_rate_hz),
                "silence_duration_ms": str(self._settings.vad_silence_ms),
                "min_speech_duration_ms": str(self._settings.vad_min_speech_ms),
                "threshold": str(self._settings.vad_threshold),
            }
        )
        url = f"wss://api.sarvam.ai/speech-to-text-realtime/ws?{params}"
        headers = {"api-subscription-key": self._settings.sarvam_api_key}
        try:
            async with connect(url, additional_headers=headers, max_size=2**22) as ws:
                self._ws = ws
                sender = asyncio.create_task(self._send_loop(ws))
                try:
                    async for raw in ws:
                        await self._on_message(raw)
                finally:
                    sender.cancel()
                    self._ws = None
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            log.warning("sarvam.stt.closed", error=str(exc))
            await self._results.put(
                SttPartial(text=f"[stt-error] {exc}", is_final=True, confidence=0.0)
            )
        finally:
            await self._results.put(None)

    async def _send_loop(self, ws) -> None:
        while True:
            chunk = await self._queue.get()
            if chunk is None:
                await ws.send(orjson.dumps({"event": "end"}).decode())
                return
            await ws.send(
                orjson.dumps(
                    {
                        "event": "audio_input",
                        "audio": base64.b64encode(chunk).decode("ascii"),
                    }
                ).decode()
            )

    async def _on_message(self, raw: str | bytes) -> None:
        try:
            msg = orjson.loads(raw)
        except Exception:
            return
        event = msg.get("event") or msg.get("type")
        if event in ("transcript.partial", "transcript.final"):
            text = (msg.get("text") or msg.get("transcript") or "").strip()
            if not text:
                return
            await self._results.put(
                SttPartial(
                    text=text,
                    is_final=event.endswith("final"),
                    language=msg.get("language") or self._language,
                )
            )
            return
        if event == "error":
            await self._results.put(
                SttPartial(
                    text=f"[stt-error] {msg.get('message')}",
                    is_final=True,
                )
            )
