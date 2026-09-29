"""Sarvam Mayura translation + Bulbul neural TTS.

Translate REST: POST https://api.sarvam.ai/translate
TTS REST (chunked): POST https://api.sarvam.ai/text-to-speech
  Header: api-subscription-key  (not Bearer)

For sub-1 s we use REST TTS on short utterances (VAD already cut to ≤1.8 s
of speech → typically < 20 words). WebSocket TTS is wired as a follow-on
if you need first-byte on longer turns.
"""

from __future__ import annotations

import base64
from collections.abc import AsyncIterator

import httpx
import soxr
import numpy as np

from app.config import Settings
from app.pipeline.base import StreamingTts, Translator

SARVAM_VOICES = {
    "hi-IN": "anushka",
    "ta-IN": "anushka",
    "te-IN": "anushka",
    "ml-IN": "anushka",
    "gu-IN": "anushka",
    "mr-IN": "anushka",
    "en-IN": "anushka",
}

_CACHE_MAX = 2048


class SarvamTranslator(Translator):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client = httpx.AsyncClient(
            base_url=settings.sarvam_base_url,
            headers={"api-subscription-key": settings.sarvam_api_key},
            timeout=httpx.Timeout(2.0, connect=0.8),
            http2=True,
        )
        self._cache: dict[tuple[str, str, str], str] = {}

    async def translate(self, text: str, src: str, dst: str) -> str:
        if not text.strip() or src.split("-")[0] == dst.split("-")[0]:
            return text
        key = (text, src, dst)
        cached = self._cache.get(key)
        if cached is not None:
            return cached
        response = await self._client.post(
            "/translate",
            json={
                "input": text,
                "source_language_code": src,
                "target_language_code": dst,
                "speaker_gender": "Female",
                "mode": "formal",
                "model": "mayura:v1",
                "enable_preprocessing": True,
            },
        )
        response.raise_for_status()
        out = response.json().get("translated_text") or response.json().get("output") or ""
        if len(self._cache) >= _CACHE_MAX:
            self._cache.clear()
        self._cache[key] = out
        return out


class SarvamStreamingTts(StreamingTts):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client = httpx.AsyncClient(
            base_url=settings.sarvam_base_url,
            headers={"api-subscription-key": settings.sarvam_api_key},
            timeout=httpx.Timeout(4.0, connect=0.8),
            http2=True,
        )

    async def stream_pcm(
        self, text: str, language: str, voice: str | None
    ) -> AsyncIterator[bytes]:
        if not text.strip():
            return
        speaker = voice or self._settings.sarvam_tts_speaker or SARVAM_VOICES.get(language, "anushka")
        response = await self._client.post(
            "/text-to-speech",
            json={
                "inputs": [text],
                "target_language_code": language,
                "speaker": speaker,
                "model": self._settings.sarvam_tts_model,
                "pace": 1.05,
                "speech_sample_rate": 16000,
                "enable_preprocessing": True,
            },
        )
        response.raise_for_status()
        body = response.json()
        audios = body.get("audios") or []
        if not audios:
            return
        raw = base64.b64decode(audios[0])
        pcm = _to_pcm16_16k(raw, self._settings.sample_rate_hz)
        frame = self._settings.frame_bytes
        for i in range(0, len(pcm), frame):
            yield pcm[i : i + frame]

    async def close(self) -> None:
        await self._client.aclose()


def _to_pcm16_16k(blob: bytes, target_hz: int) -> bytes:
    if blob[:4] == b"RIFF":
        # WAV: skip 44-byte header; if extra chunks exist, take from data.
        pcm = blob[44:]
        src_hz = int.from_bytes(blob[24:28], "little") or 16000
    else:
        pcm = blob
        src_hz = 16000
    if src_hz == target_hz:
        return pcm
    samples = np.frombuffer(pcm, dtype=np.int16).astype(np.float32)
    resampled = soxr.resample(samples, src_hz, target_hz)
    return np.clip(resampled, -32768, 32767).astype(np.int16).tobytes()
