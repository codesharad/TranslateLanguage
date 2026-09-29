from __future__ import annotations

from app.config import Settings
from app.pipeline.base import StreamingStt, StreamingTts, Translator
from app.providers.azure_stt import AzureStreamingStt
from app.providers.azure_translate import AzureTranslator
from app.providers.azure_tts import AzureStreamingTts
from app.providers.google_stt import GoogleStreamingStt
from app.providers.google_stt_v2 import GoogleV2StreamingStt
from app.providers.google_translate import GoogleTranslator
from app.providers.google_tts import GoogleStreamingTts
from app.providers.llm_translate import AnthropicTranslator, OpenAiTranslator
from app.providers.mock import MockStt, MockTranslator, MockTts
from app.providers.sarvam import SarvamStreamingTts, SarvamTranslator
from app.providers.sarvam_stt import SarvamStreamingStt


def build_stt(settings: Settings) -> StreamingStt:
    name = settings.resolved_stt()
    if name == "google_v2":
        return GoogleV2StreamingStt(settings)
    if name == "google":
        return GoogleStreamingStt(settings)
    if name == "azure":
        return AzureStreamingStt(settings)
    if name == "sarvam":
        return SarvamStreamingStt(settings)
    return MockStt(settings)


def build_translator(settings: Settings) -> Translator:
    name = settings.resolved_translator()
    if name == "google":
        return GoogleTranslator(settings)
    if name == "azure":
        return AzureTranslator(settings)
    if name == "sarvam":
        return SarvamTranslator(settings)
    if name == "openai":
        return OpenAiTranslator(settings)
    if name == "anthropic":
        return AnthropicTranslator(settings)
    return MockTranslator()


def build_tts(settings: Settings) -> StreamingTts:
    name = settings.resolved_tts()
    if name == "google":
        return GoogleStreamingTts(settings)
    if name == "azure":
        return AzureStreamingTts(settings)
    if name == "sarvam":
        return SarvamStreamingTts(settings)
    return MockTts(settings)
