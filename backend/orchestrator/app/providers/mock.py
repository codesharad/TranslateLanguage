"""Offline providers so the pipeline can be exercised without cloud keys."""

from __future__ import annotations

import asyncio
import math
import struct
from collections.abc import AsyncIterator

import structlog

from app.config import Settings
from app.pipeline.base import SttPartial, StreamingStt, StreamingTts, Translator

# Only used when real STT text matches. Never invented on silence.
_DEMO = {
    ("ta-IN", "hi-IN"): {
        "வணக்கம்": "नमस्ते",
        "எப்படி இருக்கிறீர்கள்": "आप कैसे हैं",
    },
    ("hi-IN", "ta-IN"): {
        "नमस्ते": "வணக்கம்",
        "आप कैसे हैं": "எப்படி இருக்கிறீர்கள்",
    },
}

# ~2% of full-scale 16-bit. Below this is silence / breath / room noise.
_SPEECH_RMS = 650.0


def _pcm_rms(pcm: bytes) -> float:
    if len(pcm) < 2:
        return 0.0
    n = len(pcm) // 2
    samples = struct.unpack(f"<{n}h", pcm[: n * 2])
    return math.sqrt(sum(s * s for s in samples) / n)


log = structlog.get_logger("mock-stt")


class MockStt(StreamingStt):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._results: asyncio.Queue[SttPartial | None] = asyncio.Queue()
        self._language = "ta-IN"
        self._logged_speech = False

    async def start(self, language: str) -> None:
        self._language = language
        self._logged_speech = False

    async def push_pcm(self, pcm: bytes) -> None:
        # No cloud recognizer in mock mode. Speech energy is not a transcript.
        if _pcm_rms(pcm) < _SPEECH_RMS:
            return
        if not self._logged_speech:
            self._logged_speech = True
            log.info("subtitle.skip", reason="mock STT heard speech but cannot transcribe it")
        return

    def results(self) -> AsyncIterator[SttPartial]:
        return self._iter()

    async def _iter(self) -> AsyncIterator[SttPartial]:
        while True:
            item = await self._results.get()
            if item is None:
                return
            yield item

    async def close(self) -> None:
        await self._results.put(None)


class MockTranslator(Translator):
    async def translate(self, text: str, src: str, dst: str) -> str:
        cleaned = text.strip()
        if not cleaned:
            return ""
        table = _DEMO.get((src, dst), {})
        return table.get(cleaned, "")


class MockTts(StreamingTts):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def stream_pcm(
        self, text: str, language: str, voice: str | None
    ) -> AsyncIterator[bytes]:
        # 400 ms of a 440 Hz tone so the client playback path is testable.
        n_frames = int(0.4 / (self._settings.frame_ms / 1000.0))
        sr = self._settings.sample_rate_hz
        samples = self._settings.samples_per_frame
        for i in range(n_frames):
            frame = bytearray()
            for n in range(samples):
                t = (i * samples + n) / sr
                sample = int(8000 * math.sin(2 * math.pi * 440 * t))
                frame.extend(struct.pack("<h", sample))
            yield bytes(frame)
            await asyncio.sleep(self._settings.frame_ms / 1000.0)

    async def close(self) -> None:
        return None
