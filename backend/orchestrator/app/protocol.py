"""Wire protocol between the Flutter client and the media orchestrator.

Control plane: JSON text frames.
Media plane: binary frames with a 8-byte header + PCM16LE payload.

Binary header (little-endian):
  u32 seq
  u8  kind     1 = uplink PCM (mic), 2 = downlink PCM (TTS)
  u8  flags    bit0 = utterance_end hint
  u16 reserved
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from enum import IntEnum
from typing import Any, Literal

import orjson
from pydantic import BaseModel, Field

HEADER_STRUCT = struct.Struct("<IBBH")
HEADER_SIZE = HEADER_STRUCT.size  # 8


class FrameKind(IntEnum):
    UPLINK_PCM = 1
    DOWNLINK_PCM = 2


class ControlType:
    SESSION_START = "session.start"
    SESSION_READY = "session.ready"
    SESSION_END = "session.end"
    TRANSCRIPT_PARTIAL = "transcript.partial"
    TRANSCRIPT_FINAL = "transcript.final"
    SUBTITLE_LOCAL = "subtitle_local"
    SUBTITLE_REMOTE = "subtitle_remote"
    TTS_START = "tts.start"
    TTS_END = "tts.end"
    TTS_CANCEL = "tts.cancel"
    LANGUAGES_SET = "languages.set"
    LATENCY = "latency"
    ERROR = "error"
    DUCK = "audio.duck"  # tell client to mute mic (half-duplex)
    PING = "ping"
    PONG = "pong"


class SessionStart(BaseModel):
    type: Literal["session.start"] = ControlType.SESSION_START
    call_id: str
    peer_id: str
    src_lang: str = Field(examples=["ta-IN"])
    dst_lang: str = Field(examples=["hi-IN"])
    voice: str | None = None
    sample_rate_hz: int = 16000


class SessionReady(BaseModel):
    type: Literal["session.ready"] = ControlType.SESSION_READY
    call_id: str
    frame_ms: int
    sample_rate_hz: int
    provider: str


class TranscriptEvent(BaseModel):
    type: str
    call_id: str
    utterance_id: str
    src_lang: str
    dst_lang: str
    source_text: str
    translated_text: str = ""
    is_final: bool = False
    confidence: float = 0.0
    t_ms: dict[str, int] = Field(default_factory=dict)


class TtsEvent(BaseModel):
    type: str
    call_id: str
    utterance_id: str
    generation: int = 0


class LatencyEvent(BaseModel):
    type: Literal["latency"] = ControlType.LATENCY
    call_id: str
    utterance_id: str
    stages_ms: dict[str, int]


class ErrorEvent(BaseModel):
    type: Literal["error"] = ControlType.ERROR
    code: str
    message: str


@dataclass(slots=True)
class PcmFrame:
    seq: int
    kind: FrameKind
    utterance_end: bool
    pcm: bytes
    speaker_tag: int = 0

    def pack(self) -> bytes:
        flags = 1 if self.utterance_end else 0
        return HEADER_STRUCT.pack(self.seq, int(self.kind), flags, self.speaker_tag & 0xFFFF) + self.pcm

    @classmethod
    def unpack(cls, data: bytes) -> "PcmFrame":
        if len(data) < HEADER_SIZE:
            raise ValueError("short audio frame")
        seq, kind, flags, speaker_tag = HEADER_STRUCT.unpack_from(data)
        return cls(
            seq=seq,
            kind=FrameKind(kind),
            utterance_end=bool(flags & 1),
            pcm=data[HEADER_SIZE:],
            speaker_tag=speaker_tag,
        )


def dumps(model: BaseModel | dict[str, Any]) -> bytes:
    if isinstance(model, BaseModel):
        return orjson.dumps(model.model_dump())
    return orjson.dumps(model)


def loads(raw: str | bytes) -> dict[str, Any]:
    return orjson.loads(raw)
