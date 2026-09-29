from __future__ import annotations

from google.cloud import translate_v3 as translate

from app.config import Settings
from app.pipeline.base import Translator

_CACHE_MAX = 2048


class GoogleTranslator(Translator):
    def __init__(self, settings: Settings) -> None:
        self._client = translate.TranslationServiceAsyncClient()
        self._parent = f"projects/{settings.google_project_id}/locations/global"
        self._cache: dict[tuple[str, str, str], str] = {}

    async def translate(self, text: str, src: str, dst: str) -> str:
        if not text.strip():
            return ""
        key = (text, src, dst)
        cached = self._cache.get(key)
        if cached is not None:
            return cached
        response = await self._client.translate_text(
            request={
                "parent": self._parent,
                "contents": [text],
                "mime_type": "text/plain",
                "source_language_code": src.split("-")[0],
                "target_language_code": dst.split("-")[0],
            }
        )
        out = response.translations[0].translated_text
        if len(self._cache) >= _CACHE_MAX:
            self._cache.clear()
        self._cache[key] = out
        return out
