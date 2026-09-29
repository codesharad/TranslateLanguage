from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field

from fastapi import WebSocket

from app.protocol import dumps

# Covers the client playback buffer plus a 200 ms tail after the speaker stops.
ECHO_TAIL_S = 0.35


@dataclass
class PeerSocket:
    peer_id: str
    ws: WebSocket

    async def send(self, payload: bytes | str) -> None:
        try:
            if isinstance(payload, (bytes, bytearray)) and payload[:1] in (b"{", b"["):
                await self.ws.send_text(payload.decode())
            elif isinstance(payload, (bytes, bytearray)):
                await self.ws.send_bytes(payload)
            else:
                await self.ws.send_text(payload)
        except Exception:
            return


@dataclass
class CallRoom:
    call_id: str
    peers: dict[str, PeerSocket] = field(default_factory=dict)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    # peer_id -> monotonic time until which that peer's mic is treated as echo.
    echo_guard_until: dict[str, float] = field(default_factory=dict)

    async def add(self, peer: PeerSocket) -> None:
        async with self.lock:
            previous = self.peers.get(peer.peer_id)
            self.peers[peer.peer_id] = peer
        if previous and previous.ws is not peer.ws:
            try:
                await previous.ws.close(code=4001)
            except Exception:
                return

    async def remove(self, peer_id: str, ws: WebSocket | None = None) -> None:
        async with self.lock:
            current = self.peers.get(peer_id)
            if current is None:
                return
            if ws is not None and current.ws is not ws:
                return
            self.peers.pop(peer_id, None)
            self.echo_guard_until.pop(peer_id, None)

    def mark_receivers_playing(self, speaker_id: str, pcm_bytes: int, sample_rate_hz: int) -> None:
        """Ignore the listeners' mics while this speaker's audio is still coming out of their speaker."""
        seconds = pcm_bytes / float(sample_rate_hz * 2) if pcm_bytes else 0.02
        until = time.monotonic() + seconds + ECHO_TAIL_S
        for peer_id in list(self.peers):
            if peer_id == speaker_id:
                continue
            if until > self.echo_guard_until.get(peer_id, 0.0):
                self.echo_guard_until[peer_id] = until

    def uplink_is_echo(self, peer_id: str) -> bool:
        return time.monotonic() < self.echo_guard_until.get(peer_id, 0.0)

    async def send_to(self, peer_id: str, payload: bytes | str) -> None:
        peer = self.peers.get(peer_id)
        if peer:
            await peer.send(payload)

    async def send_others(self, sender_id: str, payload: bytes | str) -> None:
        for pid, peer in list(self.peers.items()):
            if pid != sender_id:
                await peer.send(payload)

    async def broadcast_control(self, payload: dict) -> None:
        raw = dumps(payload)
        for peer in list(self.peers.values()):
            await peer.send(raw)


class Hub:
    def __init__(self) -> None:
        self._rooms: dict[str, CallRoom] = {}
        self._lock = asyncio.Lock()

    async def room(self, call_id: str) -> CallRoom:
        async with self._lock:
            if call_id not in self._rooms:
                self._rooms[call_id] = CallRoom(call_id=call_id)
            return self._rooms[call_id]

    async def drop_if_empty(self, call_id: str) -> None:
        async with self._lock:
            room = self._rooms.get(call_id)
            if room and not room.peers:
                self._rooms.pop(call_id, None)


hub = Hub()
