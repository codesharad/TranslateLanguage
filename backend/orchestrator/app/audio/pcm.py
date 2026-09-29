from __future__ import annotations

import time
from dataclasses import dataclass, field


def now_ms() -> int:
    return int(time.perf_counter() * 1000)


@dataclass
class LatencyProbe:
    """Per-utterance timestamps, milliseconds on the orchestrator clock."""

    utterance_id: str
    t0: int = field(default_factory=now_ms)
    vad_end: int | None = None
    stt_first_partial: int | None = None
    stt_final: int | None = None
    mt_done: int | None = None
    tts_first_byte: int | None = None

    def mark(self, stage: str) -> None:
        setattr(self, stage, now_ms())

    def stages_ms(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for name in (
            "vad_end",
            "stt_first_partial",
            "stt_final",
            "mt_done",
            "tts_first_byte",
        ):
            value = getattr(self, name)
            if value is not None:
                out[name] = value - self.t0
        if self.tts_first_byte is not None:
            out["e2e_server_ms"] = self.tts_first_byte - self.t0
        return out
