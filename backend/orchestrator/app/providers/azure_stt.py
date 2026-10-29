"""Azure Speech SDK push-stream STT.

Azure's conversation / continuous recognizer is often 50–150 ms faster to
first partial than Google for Indic languages when the region is
`centralindia`.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator

import azure.cognitiveservices.speech as speechsdk
import structlog

from app.config import Settings
from app.languages import is_auto, lid_candidates
from app.pipeline.base import SttPartial, StreamingStt

log = structlog.get_logger("azure-stt")


class AzureStreamingStt(StreamingStt):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._push: speechsdk.audio.PushAudioInputStream | None = None
        self._recognizer: speechsdk.SpeechRecognizer | None = None
        self._results: asyncio.Queue[SttPartial | None] = asyncio.Queue()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._generation = 0
        self._priority: list[str] = []
        # True: automatic detection chooses only among the pinned languages. False fills the
        # list to ten from the catalog, which was the original behaviour (kept for evaluation).
        self.pin_only = True
        self._auto = False

    def prepare_detection(self, *codes: str) -> None:
        self._priority = [code for code in codes if code and not is_auto(code)]

    async def start(self, language: str) -> None:
        self._generation += 1
        generation = self._generation
        # The results queue is kept across restarts so the caption pump keeps reading it.
        self._loop = asyncio.get_running_loop()
        format_ = speechsdk.audio.AudioStreamFormat(
            samples_per_second=self._settings.sample_rate_hz,
            bits_per_sample=16,
            channels=1,
        )
        self._push = speechsdk.audio.PushAudioInputStream(stream_format=format_)
        audio_config = speechsdk.audio.AudioConfig(stream=self._push)
        speech_config = speechsdk.SpeechConfig(
            subscription=self._settings.azure_speech_key,
            region=self._settings.azure_speech_region,
        )
        # Pick only between the call's own languages. With all ten candidates, Hindi was
        # often heard as English and passed through untranslated.
        candidates = lid_candidates(*self._priority, fill=not (self._priority and self.pin_only))
        if is_auto(language) and len(candidates) == 1:
            language = candidates[0]
        self._auto = is_auto(language)
        lid_config = None
        if self._auto:
            log.info("stt.lid", candidates=candidates)
            speech_config.set_property(
                speechsdk.PropertyId.SpeechServiceConnection_LanguageIdMode,
                "Continuous",
            )
            lid_config = speechsdk.languageconfig.AutoDetectSourceLanguageConfig(languages=candidates)
        else:
            speech_config.speech_recognition_language = language
        speech_config.set_property(
            speechsdk.PropertyId.SpeechServiceConnection_InitialSilenceTimeoutMs,
            "2500",
        )
        speech_config.set_property(
            speechsdk.PropertyId.Speech_SegmentationSilenceTimeoutMs,
            str(min(self._settings.vad_silence_ms, 250)),
        )
        speech_config.set_property_by_name("SpeechServiceResponse_StablePartialResultThreshold", "2")
        if lid_config is None:
            self._recognizer = speechsdk.SpeechRecognizer(
                speech_config=speech_config,
                audio_config=audio_config,
            )
        else:
            self._recognizer = speechsdk.SpeechRecognizer(
                speech_config=speech_config,
                auto_detect_source_language_config=lid_config,
                audio_config=audio_config,
            )
        self._recognizer.recognizing.connect(lambda evt, gen=generation: self._on_recognizing(evt, gen))
        self._recognizer.recognized.connect(lambda evt, gen=generation: self._on_recognized(evt, gen))
        self._recognizer.canceled.connect(lambda evt, gen=generation: self._on_canceled(evt, gen))
        await asyncio.to_thread(self._recognizer.start_continuous_recognition)

    async def switch_language(self, language: str) -> None:
        """Restart recognition in another language without ending the result stream."""
        recognizer, push = self._recognizer, self._push
        self._generation += 1  # events from the old recognizer are ignored from here on
        self._recognizer = None
        self._push = None
        if recognizer is not None:
            await asyncio.to_thread(recognizer.stop_continuous_recognition)
        if push is not None:
            await asyncio.to_thread(push.close)
        await self.start(language)

    async def push_pcm(self, pcm: bytes) -> None:
        if self._push is not None and pcm:
            self._push.write(pcm)

    def results(self) -> AsyncIterator[SttPartial]:
        return self._iter_results()

    async def _iter_results(self) -> AsyncIterator[SttPartial]:
        while True:
            item = await self._results.get()
            if item is None:
                return
            yield item

    async def close(self) -> None:
        if self._recognizer:
            await asyncio.to_thread(self._recognizer.stop_continuous_recognition)
        if self._push:
            await asyncio.to_thread(self._push.close)
        await self._results.put(None)

    def _emit(self, text: str, is_final: bool, confidence: float, language: str = "") -> None:
        if not text or self._loop is None:
            return
        self._loop.call_soon_threadsafe(
            self._results.put_nowait,
            SttPartial(
                text=text.strip(),
                is_final=is_final,
                confidence=confidence,
                language=language,
            ),
        )

    def _detected(self, result: speechsdk.SpeechRecognitionResult) -> str:
        if not self._auto:
            return ""
        try:
            detected = speechsdk.AutoDetectSourceLanguageResult(result)
        except Exception:
            return ""
        return detected.language or ""

    def _on_recognizing(self, evt: speechsdk.SpeechRecognitionEventArgs, generation: int) -> None:
        if generation != self._generation:
            return
        self._emit(evt.result.text, False, 0.0, self._detected(evt.result))

    def _on_recognized(self, evt: speechsdk.SpeechRecognitionEventArgs, generation: int) -> None:
        if generation != self._generation:
            return
        if evt.result.reason == speechsdk.ResultReason.RecognizedSpeech:
            self._emit(evt.result.text, True, 0.0, self._detected(evt.result))

    def _on_canceled(self, evt: speechsdk.SpeechRecognitionCanceledEventArgs, generation: int) -> None:
        if generation != self._generation or self._loop is None:
            return
        self._loop.call_soon_threadsafe(self._results.put_nowait, None)
