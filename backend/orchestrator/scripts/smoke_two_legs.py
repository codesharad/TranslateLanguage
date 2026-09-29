"""Two-leg mock call: proves PCM framing, transcripts, and TTS downlink."""

from __future__ import annotations

import asyncio
import json
import struct

import websockets

HEADER = struct.Struct("<IBBH")


async def leg(peer_id: str, src: str, dst: str) -> None:
    uri = "ws://127.0.0.1:8090/v1/media"
    async with websockets.connect(uri, max_size=2**22) as ws:
        await ws.send(
            json.dumps(
                {
                    "type": "session.start",
                    "call_id": "demo-call",
                    "peer_id": peer_id,
                    "src_lang": src,
                    "dst_lang": dst,
                    "sample_rate_hz": 16000,
                }
            )
        )
        async def reader() -> None:
            async for message in ws:
                if isinstance(message, bytes):
                    print(f"[{peer_id}] pcm {len(message)} bytes")
                else:
                    print(f"[{peer_id}] {message}")

        reader_task = asyncio.create_task(reader())
        silence = b"\x00\x00" * 320  # 20 ms of PCM16 silence @ 16 kHz
        for seq in range(80):  # ~1.6 s
            await ws.send(HEADER.pack(seq, 1, 0, 0) + silence)
            await asyncio.sleep(0.02)
        await asyncio.sleep(1.0)
        reader_task.cancel()


async def main() -> None:
    await asyncio.gather(
        leg("user-a", "ta-IN", "hi-IN"),
        leg("user-b", "hi-IN", "ta-IN"),
    )


if __name__ == "__main__":
    asyncio.run(main())
