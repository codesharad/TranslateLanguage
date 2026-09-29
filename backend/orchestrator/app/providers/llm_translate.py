"""Low-latency LLM translators.

Prompt is deliberately tiny: no JSON, no explanations, no quotes.
Keep-alive HTTP/2. Cache identical (text, src, dst) triples.

gpt-4o-mini and Claude Haiku are in the same ~80–200 ms band for a
short Indic sentence if the region is close (use a Mumbai/Singapore
proxy if the vendor has no India endpoint).
"""

from __future__ import annotations

import httpx

from app.config import Settings
from app.languages import script_rule
from app.pipeline.base import Translator

_SYS = (
    "You are a real-time voice translator for a live call. "
    "Translate from {src} to {dst}.\n"
    "{script}"
    "Rules:\n"
    "- If the input is silence, breath, static, ambient noise, or not clear human speech, output nothing.\n"
    "- Do not greet, initiate, or invent placeholders. Translate only what was spoken.\n"
    "- Output ONLY the translation. Preserve tone, intent, names, and numbers. "
    "No quotes, filler, notes, or intro phrases."
)
_CACHE_MAX = 2048


class _HttpTranslator(Translator):
    def __init__(self) -> None:
        self._cache: dict[tuple[str, str, str], str] = {}

    def _cached(self, text: str, src: str, dst: str) -> str | None:
        return self._cache.get((text, src, dst))

    def _store(self, text: str, src: str, dst: str, out: str) -> str:
        if len(self._cache) >= _CACHE_MAX:
            self._cache.clear()
        self._cache[(text, src, dst)] = out
        return out


class OpenAiTranslator(_HttpTranslator):
    def __init__(self, settings: Settings) -> None:
        super().__init__()
        self._model = settings.openai_model
        self._client = httpx.AsyncClient(
            base_url=settings.openai_base_url.rstrip("/"),
            headers={"Authorization": f"Bearer {settings.openai_api_key}"},
            timeout=httpx.Timeout(1.8, connect=0.6),
            http2=True,
        )

    async def translate(self, text: str, src: str, dst: str) -> str:
        if not text.strip():
            return ""
        hit = self._cached(text, src, dst)
        if hit is not None:
            return hit
        response = await self._client.post(
            "/chat/completions",
            json={
                "model": self._model,
                "temperature": 0,
                "max_tokens": 120,
                "messages": [
                    {"role": "system", "content": _SYS.format(src=src, dst=dst, script=script_rule(dst))},
                    {"role": "user", "content": text},
                ],
            },
        )
        response.raise_for_status()
        out = response.json()["choices"][0]["message"]["content"].strip()
        return self._store(text, src, dst, out)


class AnthropicTranslator(_HttpTranslator):
    def __init__(self, settings: Settings) -> None:
        super().__init__()
        self._model = settings.anthropic_model
        self._client = httpx.AsyncClient(
            base_url="https://api.anthropic.com/v1",
            headers={
                "x-api-key": settings.anthropic_api_key,
                "anthropic-version": "2023-06-01",
            },
            timeout=httpx.Timeout(1.8, connect=0.6),
            http2=True,
        )

    async def translate(self, text: str, src: str, dst: str) -> str:
        if not text.strip():
            return ""
        hit = self._cached(text, src, dst)
        if hit is not None:
            return hit
        response = await self._client.post(
            "/messages",
            json={
                "model": self._model,
                "max_tokens": 120,
                "temperature": 0,
                "system": _SYS.format(src=src, dst=dst, script=script_rule(dst)),
                "messages": [{"role": "user", "content": text}],
            },
        )
        response.raise_for_status()
        blocks = response.json().get("content") or []
        out = "".join(b.get("text", "") for b in blocks if b.get("type") == "text").strip()
        return self._store(text, src, dst, out)
