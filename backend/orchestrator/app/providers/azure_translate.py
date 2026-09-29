from __future__ import annotations

import asyncio
import time

import httpx
import structlog

from app.config import Settings
from app.languages import is_latin_heavy, lookup, translator_pair
from app.pipeline.base import Translator

log = structlog.get_logger("azure-mt")
_CACHE_MAX = 2048


class AzureTranslator(Translator):
    def __init__(self, settings: Settings) -> None:
        self._endpoint = settings.azure_translator_endpoint.rstrip("/")
        self._key = settings.azure_translator_key
        self._region = settings.azure_translator_region
        self._cache: dict[tuple[str, str, str], str] = {}
        self._client = httpx.AsyncClient(
            timeout=httpx.Timeout(1.5, connect=0.4),
        )
        self._inflight: dict[tuple[str, str, str], asyncio.Task[str]] = {}

    async def translate(self, text: str, src: str, dst: str) -> str:
        cleaned = text.strip().strip(".,!?।").strip()
        if not cleaned:
            return ""
        key = (cleaned, src, dst)
        cached = self._cache.get(key)
        if cached is not None:
            return cached
        task = self._inflight.get(key)
        if task is None:
            task = asyncio.create_task(self._fetch(cleaned, src, dst, key))
            self._inflight[key] = task
        try:
            return await task
        finally:
            if self._inflight.get(key) is task and task.done():
                self._inflight.pop(key, None)

    async def _fetch(self, text: str, src: str, dst: str, key: tuple[str, str, str]) -> str:
        started = time.perf_counter()
        from_code, to_code, to_script = translator_pair(src, dst)
        params = {
            "api-version": "3.0",
            "from": from_code,
            "to": to_code,
        }
        if to_script:
            params["toScript"] = to_script
        headers = {
            "Ocp-Apim-Subscription-Key": self._key,
            "Ocp-Apim-Subscription-Region": self._region,
            "Content-Type": "application/json",
        }
        response = await self._client.post(
            f"{self._endpoint}/translate",
            params=params,
            headers=headers,
            json=[{"text": text}],
        )
        response.raise_for_status()
        out = response.json()[0]["translations"][0]["text"]
        target = lookup(dst)
        if target and target.to_script and is_latin_heavy(out):
            out = await self._to_native_script(out, target.translator_code, target.to_script)
        if len(self._cache) >= _CACHE_MAX:
            self._cache.clear()
        self._cache[key] = out
        log.info("translate.ms", ms=int((time.perf_counter() - started) * 1000), chars=len(text))
        return out

    async def _to_native_script(self, text: str, language: str, to_script: str) -> str:
        params = {
            "api-version": "3.0",
            "language": language.split("-")[0],
            "fromScript": "Latn",
            "toScript": to_script,
        }
        headers = {
            "Ocp-Apim-Subscription-Key": self._key,
            "Ocp-Apim-Subscription-Region": self._region,
            "Content-Type": "application/json",
        }
        response = await self._client.post(
            f"{self._endpoint}/transliterate",
            params=params,
            headers=headers,
            json=[{"text": text}],
        )
        if response.status_code >= 400:
            log.warning("translate.script_failed", status=response.status_code, to_script=to_script)
            return text
        converted = response.json()[0]["text"]
        log.info("translate.script", to_script=to_script, latin=True)
        return converted or text

    async def aclose(self) -> None:
        await self._client.aclose()
