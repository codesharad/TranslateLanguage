"""Google Cloud Speech-to-Text V2 streaming (Chirp / latest_short).

Recognizer `_` is the auto recognizer (no pre-provisioned resource). Use a
regional location (`asia-south1`) for India RTT; `global` is the default.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator

from google.api_core.client_options import ClientOptions
from google.cloud.speech_v2 import SpeechAsyncClient
from google.cloud.speech_v2.types import cloud_speech

from app.config import Settings
from app.pipeline.base import SttPartial, StreamingStt


class GoogleV2StreamingStt(StreamingStt):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        loc = settings.google_stt_location
        if loc and loc != "global":
            self._client = SpeechAsyncClient(
                client_options=ClientOptions(api_endpoint=f"{loc}-speech.googleapis.com")
            )
        else:
            self._client = SpeechAsyncClient()
        self._queue: asyncio.Queue[bytes | None] = asyncio.Queue()
        self._results: asyncio.Queue[SttPartial | None] = asyncio.Queue()
        self._language = "hi-IN"
        self._task: asyncio.Task[None] | None = None

    async def start(self, language: str) -> None:
        self._language = language
        self._queue = asyncio.Queue()
        self._results = asyncio.Queue()
        self._task = asyncio.create_task(self._run(), name="google-stt-v2")

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
            self._task = None
        await self._results.put(None)

    async def _request_iter(self):
        location = self._settings.google_stt_location
        recognizer = (
            f"projects/{self._settings.google_project_id}/locations/{location}/recognizers/_"
        )
        config = cloud_speech.RecognitionConfig(
            explicit_decoding_config=cloud_speech.ExplicitDecodingConfig(
                encoding=cloud_speech.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
                sample_rate_hertz=self._settings.sample_rate_hz,
                audio_channel_count=1,
            ),
            language_codes=[self._language],
            model=self._settings.google_stt_model,
            features=cloud_speech.RecognitionFeatures(
                enable_automatic_punctuation=False,
                max_alternatives=1,
            ),
        )
        streaming_config = cloud_speech.StreamingRecognitionConfig(
            config=config,
            streaming_features=cloud_speech.StreamingRecognitionFeatures(interim_results=True),
        )
        yield cloud_speech.StreamingRecognizeRequest(
            recognizer=recognizer,
            streaming_config=streaming_config,
        )
        while True:
            chunk = await self._queue.get()
            if chunk is None:
                return
            yield cloud_speech.StreamingRecognizeRequest(audio=chunk)

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
                            confidence=float(getattr(alt, "confidence", 0.0) or 0.0),
                            language=self._language,
                        )
                    )
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            await self._results.put(
                SttPartial(text=f"[stt-error] {exc}", is_final=True, confidence=0.0)
            )
        finally:
            await self._results.put(None)
