"""Google Cloud TTS — LINEAR16, no speaking_rate tricks (they add pre-roll).

Google's streaming TTS (StreamingSynthesize) is available on selected voices;
this client uses unary synthesize in 1-sentence bursts which is still within
budget for short Indic utterances. Swap to streaming when the voice supports it.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from google.cloud import texttospeech_v1 as tts

from app.config import Settings
from app.pipeline.base import StreamingTts

DEFAULT_VOICES = {
    "hi-IN": "hi-IN-Wavenet-A",
    "ta-IN": "ta-IN-Wavenet-A",
    "te-IN": "te-IN-Standard-A",
    "ml-IN": "ml-IN-Wavenet-A",
    "gu-IN": "gu-IN-Wavenet-A",
    "mr-IN": "mr-IN-Wavenet-A",
    "en-IN": "en-IN-Wavenet-A",
}


class GoogleStreamingTts(StreamingTts):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client = tts.TextToSpeechAsyncClient()

    async def stream_pcm(
        self, text: str, language: str, voice: str | None
    ) -> AsyncIterator[bytes]:
        if not text.strip():
            return
        voice_name = voice or DEFAULT_VOICES.get(language, f"{language}-Standard-A")
        request = tts.SynthesizeSpeechRequest(
            input=tts.SynthesisInput(text=text),
            voice=tts.VoiceSelectionParams(language_code=language, name=voice_name),
            audio_config=tts.AudioConfig(
                audio_encoding=tts.AudioEncoding.LINEAR16,
                sample_rate_hertz=self._settings.sample_rate_hz,
                speaking_rate=1.05,
            ),
        )
        response = await self._client.synthesize_speech(request=request)
        audio = response.audio_content
        # LINEAR16 responses may include a 44-byte WAV header.
        if audio[:4] == b"RIFF":
            audio = audio[44:]
        frame = self._settings.frame_bytes
        for i in range(0, len(audio), frame):
            yield audio[i : i + frame]

    async def close(self) -> None:
        return None
