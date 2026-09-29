from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass


@dataclass(slots=True, frozen=True)
class SttPartial:
    text: str
    is_final: bool
    confidence: float = 0.0
    language: str = ""


class StreamingStt(ABC):
    def prepare_detection(self, *codes: str) -> None:
        """Locales to pin when recognition language is automatic."""
        return None

    @abstractmethod
    async def start(self, language: str) -> None: ...

    @abstractmethod
    async def push_pcm(self, pcm: bytes) -> None: ...

    @abstractmethod
    def results(self) -> AsyncIterator[SttPartial]: ...

    @abstractmethod
    async def close(self) -> None: ...

    async def reconfigure(self, language: str) -> None:
        await self.close()
        await self.start(language)


class Translator(ABC):
    @abstractmethod
    async def translate(self, text: str, src: str, dst: str) -> str: ...


class StreamingTts(ABC):
    @abstractmethod
    def stream_pcm(self, text: str, language: str, voice: str | None) -> AsyncIterator[bytes]: ...

    @abstractmethod
    async def close(self) -> None: ...
