"""Google Cloud Speech-to-Text streaming (gRPC).

Uses `latest_short` for conversational bursts. Indian locales: hi-IN, ta-IN,
te-IN, ml-IN, gu-IN, mr-IN. Recycle the stream every ~4 minutes (Google
hard-limit is 5).
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator

from google.cloud import speech_v1 as speech

from app.config import Settings
from app.pipeline.base import SttPartial, StreamingStt


class GoogleStreamingStt(StreamingStt):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client = speech.SpeechAsyncClient()
        self._queue: asyncio.Queue[bytes | None] = asyncio.Queue()
        self._results: asyncio.Queue[SttPartial | None] = asyncio.Queue()
        self._language = "hi-IN"
        self._task: asyncio.Task[None] | None = None

    async def start(self, language: str) -> None:
        self._language = language
        self._task = asyncio.create_task(self._run(), name="google-stt")

    async def push_pcm(self, pcm: bytes) -> None:
        await self._queue.put(pcm)

    def results(self) -> AsyncIterator[SttPartial]:
        return self._iter_results()

    async def _iter_results(self) -> AsyncIterator[SttPartial]:
        while True:
            item = await self._results.get()
            if item is None:
                return
            yield item

    async def close(self) -> None:
        await self._queue.put(None)
        if self._task:
            await asyncio.gather(self._task, return_exceptions=True)
        await self._results.put(None)

    async def _request_iter(self):
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=self._settings.sample_rate_hz,
            language_code=self._language,
            model=self._settings.google_stt_model,
            enable_automatic_punctuation=False,
            use_enhanced=True,
            max_alternatives=1,
            enable_spoken_punctuation=False,
        )
        streaming_config = speech.StreamingRecognitionConfig(
            config=config,
            interim_results=True,
            single_utterance=False,
        )
        yield speech.StreamingRecognizeRequest(streaming_config=streaming_config)
        while True:
            chunk = await self._queue.get()
            if chunk is None:
                return
            yield speech.StreamingRecognizeRequest(audio_content=chunk)

    async def _run(self) -> None:
        try:
            stream = await self._client.streaming_recognize(requests=self._request_iter())
            async for response in stream:
                for result in response.results:
                    if not result.alternatives:
                        continue
                    alt = result.alternatives[0]
                    await self._results.put(
                        SttPartial(
                            text=alt.transcript.strip(),
                            is_final=bool(result.is_final),
                            confidence=float(alt.confidence or 0.0),
                            language=self._language,
                        )
                    )
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 — surface to client as STT error
            await self._results.put(
                SttPartial(text=f"[stt-error] {exc}", is_final=True, confidence=0.0)
            )
        finally:
            await self._results.put(None)
