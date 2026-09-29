from __future__ import annotations

import structlog
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.hub import PeerSocket, hub
from app.protocol import ControlType, SessionStart, loads
from app.session import TranslationLeg

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.dev.ConsoleRenderer(),
    ]
)
log = structlog.get_logger("orchestrator")
settings = get_settings()

app = FastAPI(title="TranslateLanguage Orchestrator", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict[str, str | int]:
    return {
        "status": "ok",
        "provider": settings.pipeline_provider,
        "stt": settings.resolved_stt(),
        "translator": settings.resolved_translator(),
        "tts": settings.resolved_tts(),
        "vad": settings.vad_backend,
        "sample_rate_hz": settings.sample_rate_hz,
        "frame_ms": settings.frame_ms,
        "target_e2e_ms": settings.target_e2e_ms,
    }


@app.websocket("/v1/media")
async def media_socket(ws: WebSocket) -> None:
    await ws.accept()
    start: SessionStart | None = None
    leg: TranslationLeg | None = None
    try:
        raw = await ws.receive_text()
        payload = loads(raw)
        if payload.get("type") != ControlType.SESSION_START:
            await ws.send_json({"type": "error", "code": "protocol", "message": "session.start required"})
            await ws.close(code=4400)
            return
        start = SessionStart.model_validate(payload)
        room = await hub.room(start.call_id)
        peer = PeerSocket(peer_id=start.peer_id, ws=ws)
        await room.add(peer)

        async def send_local(data: bytes | str) -> None:
            if isinstance(data, bytes) and data[:1] not in (b"{", b"["):
                await ws.send_bytes(data)
            else:
                await ws.send_text(data if isinstance(data, str) else data.decode())

        async def send_peer(data: bytes | str) -> None:
            await room.send_others(start.peer_id, data)

        log.info(
            "leg.start",
            call_id=start.call_id,
            peer=start.peer_id,
            src=start.src_lang,
            dst=start.dst_lang,
            forwarded=ws.headers.get("x-forwarded-for", ""),
        )
        leg = TranslationLeg(ws, settings, start, send_peer, send_local, room)
        await leg.run()
    except WebSocketDisconnect:
        log.info("leg.disconnect", call_id=getattr(start, "call_id", None))
    except Exception as exc:  # noqa: BLE001
        log.exception("leg.error", error=str(exc))
    finally:
        if leg:
            leg.stop()
        if start:
            room = await hub.room(start.call_id)
            await room.remove(start.peer_id, ws)
            await hub.drop_if_empty(start.call_id)


def run() -> None:
    import os

    import uvicorn

    # Render and Railway inject PORT. Local Docker keeps ORCHESTRATOR_PORT.
    port = int(os.environ.get("PORT") or settings.port)
    host = os.environ.get("HOST") or settings.host
    uvicorn.run(
        "app.main:app",
        host=host,
        port=port,
        proxy_headers=True,
        forwarded_allow_ips="*",
        ws_ping_interval=20,
        ws_ping_timeout=20,
        log_level="info",
    )


if __name__ == "__main__":
    run()
