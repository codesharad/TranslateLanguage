from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


ProviderName = Literal["google", "google_v2", "azure", "sarvam", "openai", "anthropic", "mock"]
VadBackend = Literal["silero", "webrtc"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
        populate_by_name=True,
    )

    host: str = Field(default="0.0.0.0", validation_alias="ORCHESTRATOR_HOST")
    port: int = Field(default=8090, validation_alias="ORCHESTRATOR_PORT")

    # Convenience preset. Individual *_provider fields win when set to a
    # non-empty override via STT_PROVIDER / TRANSLATOR_PROVIDER / TTS_PROVIDER.
    pipeline_provider: Literal["google", "azure", "sarvam", "mock"] = "mock"
    stt_provider: str = ""
    translator_provider: str = ""
    tts_provider: str = ""

    sample_rate_hz: int = 16000
    frame_ms: int = 20
    target_e2e_ms: int = 1000

    google_project_id: str = ""
    google_stt_model: str = "latest_short"
    google_stt_location: str = "global"

    azure_speech_key: str = ""
    azure_speech_region: str = "centralindia"
    azure_translator_key: str = ""
    azure_translator_region: str = "centralindia"
    azure_translator_endpoint: str = "https://api.cognitive.microsofttranslator.com"

    sarvam_api_key: str = ""
    sarvam_stt_model: str = "saaras:v3-realtime"
    sarvam_tts_model: str = "bulbul:v3"
    sarvam_tts_speaker: str = "anushka"
    sarvam_base_url: str = "https://api.sarvam.ai"

    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    openai_base_url: str = "https://api.openai.com/v1"

    anthropic_api_key: str = ""
    anthropic_model: str = "claude-haiku-4-5"

    vad_backend: VadBackend = "silero"
    vad_aggressiveness: int = 2
    vad_silence_ms: int = 180
    vad_min_speech_ms: int = 120
    vad_max_utterance_ms: int = 1800
    vad_threshold: float = 0.45
    silero_onnx_path: str = "models/silero_vad.onnx"
    partial_translate: bool = True
    partial_min_chars: int = 4
    half_duplex: bool = True
    barge_in: bool = True

    @property
    def frame_bytes(self) -> int:
        return int(self.sample_rate_hz * (self.frame_ms / 1000.0) * 2)

    @property
    def samples_per_frame(self) -> int:
        return int(self.sample_rate_hz * (self.frame_ms / 1000.0))

    def resolved_stt(self) -> str:
        return _choose(self.stt_provider, _preset_stt(self._preset()), {"google", "google_v2", "azure", "sarvam", "mock"})

    def resolved_translator(self) -> str:
        return _choose(
            self.translator_provider,
            _preset_mt(self._preset()),
            {"google", "azure", "sarvam", "openai", "anthropic", "mock"},
        )

    def resolved_tts(self) -> str:
        return _choose(self.tts_provider, _preset_tts(self._preset()), {"google", "azure", "sarvam", "mock"})

    def _preset(self) -> str:
        name = self.pipeline_provider.split("#", 1)[0].strip().lower()
        return name if name in {"google", "azure", "sarvam", "mock"} else "mock"


def _choose(override: str, preset_value: str, allowed: set[str]) -> str:
    name = override.split("#", 1)[0].strip().lower()
    if name in allowed:
        return name
    return preset_value


def _preset_stt(preset: str) -> str:
    return {"google": "google_v2", "azure": "azure", "sarvam": "sarvam", "mock": "mock"}[preset]


def _preset_mt(preset: str) -> str:
    return {"google": "google", "azure": "azure", "sarvam": "sarvam", "mock": "mock"}[preset]


def _preset_tts(preset: str) -> str:
    return {"google": "google", "azure": "azure", "sarvam": "sarvam", "mock": "mock"}[preset]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
