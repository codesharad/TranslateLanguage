"""Azure neural TTS with pull audio stream — first byte typically 150–300 ms."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator

import azure.cognitiveservices.speech as speechsdk

import structlog

from app.config import Settings
from app.languages import voice_for
from app.pipeline.base import StreamingTts

log = structlog.get_logger("azure-tts")


class AzureStreamingTts(StreamingTts):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._speech_config = speechsdk.SpeechConfig(
            subscription=settings.azure_speech_key,
            region=settings.azure_speech_region,
        )
        self._speech_config.set_speech_synthesis_output_format(
            speechsdk.SpeechSynthesisOutputFormat.Raw16Khz16BitMonoPcm
        )

    async def stream_pcm(
        self, text: str, language: str, voice: str | None
    ) -> AsyncIterator[bytes]:
        if not text.strip():
            return
        voice_name = voice_for(language)
        self._speech_config.speech_synthesis_voice_name = voice_name
        # Stream through the synthesizing event. A pull stream's read() never returns 0
        # after the last chunk, so the old loop hung after the first sentence.
        synth = speechsdk.SpeechSynthesizer(speech_config=self._speech_config, audio_config=None)
        loop = asyncio.get_running_loop()
        chunks: asyncio.Queue[bytes | None] = asyncio.Queue()
        frame = self._settings.frame_bytes

        def on_chunk(evt: speechsdk.SpeechSynthesisEventArgs) -> None:
            data = evt.result.audio_data
            if data:
                loop.call_soon_threadsafe(chunks.put_nowait, bytes(data))

        def on_done(_evt: speechsdk.SpeechSynthesisEventArgs) -> None:
            loop.call_soon_threadsafe(chunks.put_nowait, None)

        synth.synthesizing.connect(on_chunk)
        synth.synthesis_completed.connect(on_done)
        synth.synthesis_canceled.connect(on_done)
        future = synth.speak_text_async(text)
        waiter = asyncio.create_task(asyncio.to_thread(future.get))
        pending = b""
        try:
            while True:
                chunk = await chunks.get()
                if chunk is None:
                    break
                pending += chunk
                while len(pending) >= frame:
                    yield pending[:frame]
                    pending = pending[frame:]
            if pending:
                yield pending
            result = await waiter
            if result.reason != speechsdk.ResultReason.SynthesizingAudioCompleted:
                details = result.cancellation_details
                log.warning(
                    "tts.failed",
                    reason=str(getattr(details, "reason", "")),
                    error=str(getattr(details, "error_details", "")),
                )
        finally:
            if not waiter.done():
                waiter.cancel()

    async def close(self) -> None:
        return None
