"""Measurements for the paper's results section.

Run inside the orchestrator container (it needs the Azure keys and the app package):

    docker compose cp backend/orchestrator/scripts/eval_pipeline.py orchestrator:/tmp/eval_pipeline.py
    docker compose exec -T orchestrator sh -c 'PYTHONPATH=$PWD python /tmp/eval_pipeline.py <command>'

Commands: synth, recog, mt, e2e, switch, echo. Results go to /tmp/eval/*.json.

All speech is synthetic (Azure neural voices speaking known text), so recognition scores are an
upper bound for clean speech, not a measurement on real callers.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import statistics
import struct
import sys
import time
import unicodedata
import uuid

OUT = "/tmp/eval"
CLIPS = f"{OUT}/clips"
FRAME = 640  # 20 ms of 16 kHz PCM16
HEADER = struct.Struct("<IBBH")
WS_URI = "ws://127.0.0.1:8090/v1/media"

SENTENCES = [
    "Hello, my name is Sharad and I am calling from Delhi.",
    "Can you hear me clearly?",
    "I will reach the station in about twenty minutes.",
    "Please send me the address of the hospital.",
    "What time does the meeting start tomorrow?",
    "The doctor said I should rest for three days.",
    "Could you repeat that a little more slowly?",
    "We booked two tickets for the evening train.",
    "My phone number ends with four seven two nine.",
    "Thank you for your help, I really appreciate it.",
]
SPOKEN = ["en-IN", "hi-IN", "mr-IN", "ta-IN"]
PARTNER = {"en-IN": "hi-IN", "hi-IN": "en-IN", "mr-IN": "en-IN", "ta-IN": "en-IN"}
INDIC = ["hi-IN", "ta-IN", "te-IN", "ml-IN", "gu-IN", "mr-IN", "bn-IN"]
SCRIPT_RANGE = {
    "hi-IN": (0x0900, 0x097F), "mr-IN": (0x0900, 0x097F), "ta-IN": (0x0B80, 0x0BFF),
    "te-IN": (0x0C00, 0x0C7F), "ml-IN": (0x0D00, 0x0D7F), "gu-IN": (0x0A80, 0x0AFF),
    "bn-IN": (0x0980, 0x09FF),
}
ROMANIZED = [
    "mera naam Sharad hai",
    "aap kaise ho",
    "mujhe ghar jaana hai",
    "kal subah milte hain",
    "kya aap meri awaaz sun sakte ho",
    "bahut dhanyavaad",
    "main das minute mein pahunch raha hoon",
    "mujhe thoda paani chahiye",
]


# ── helpers ───────────────────────────────────────────────────────────────────
def settings():
    from app.config import Settings
    return Settings()


def save(name: str, data) -> None:
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/{name}.json", "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1)
    print("saved", name, flush=True)


def load(name: str):
    with open(f"{OUT}/{name}.json", encoding="utf-8") as fh:
        return json.load(fh)


def norm(text: str) -> list[str]:
    text = unicodedata.normalize("NFC", text).lower().replace("।", " ")
    text = "".join(" " if unicodedata.category(c).startswith("P") else c for c in text)
    return text.split()


def edit_distance(a: list, b: list) -> int:
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def wer(ref: str, hyp: str) -> float:
    r, h = norm(ref), norm(hyp)
    return edit_distance(r, h) / max(len(r), 1)


def cer(ref: str, hyp: str) -> float:
    r, h = list("".join(norm(ref))), list("".join(norm(hyp)))
    return edit_distance(r, h) / max(len(r), 1)


def chrf(ref: str, hyp: str, n_max: int = 6, beta: float = 2.0) -> float:
    """chrF: character n-gram F-score, whitespace ignored (own implementation)."""
    r = "".join(unicodedata.normalize("NFC", ref).split())
    h = "".join(unicodedata.normalize("NFC", hyp).split())
    precisions, recalls = [], []
    for n in range(1, n_max + 1):
        rg = [r[i:i + n] for i in range(len(r) - n + 1)]
        hg = [h[i:i + n] for i in range(len(h) - n + 1)]
        if not rg or not hg:
            continue
        rc: dict[str, int] = {}
        for g in rg:
            rc[g] = rc.get(g, 0) + 1
        hc: dict[str, int] = {}
        for g in hg:
            hc[g] = hc.get(g, 0) + 1
        match = sum(min(c, rc.get(g, 0)) for g, c in hc.items())
        precisions.append(match / len(hg))
        recalls.append(match / len(rg))
    if not precisions:
        return 0.0
    p, r_ = sum(precisions) / len(precisions), sum(recalls) / len(recalls)
    if p + r_ == 0:
        return 0.0
    return 100 * (1 + beta**2) * p * r_ / (beta**2 * p + r_)


def pct(values: list[float], q: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    k = (len(ordered) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (k - lo)


def summarize(values: list[float]) -> dict:
    if not values:
        return {"n": 0}
    return {
        "n": len(values),
        "mean": statistics.fmean(values),
        "median": statistics.median(values),
        "p95": pct(values, 0.95),
        "min": min(values),
        "max": max(values),
    }


def script_share(text: str, lang: str) -> float:
    lo, hi = SCRIPT_RANGE[lang]
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    return sum(1 for c in letters if lo <= ord(c) <= hi) / len(letters)


def clip_pcm(lang: str, idx: int) -> bytes:
    with open(f"{CLIPS}/{lang}_{idx}.pcm", "rb") as fh:
        return fh.read()


def padded(pcm: bytes, lead_s: float = 0.3, tail_s: float = 3.0) -> bytes:
    return b"\x00\x00" * int(16000 * lead_s) + pcm + b"\x00\x00" * int(16000 * tail_s)


# ── synth: build the test clips ───────────────────────────────────────────────
async def cmd_synth() -> None:
    from app.providers.azure_translate import AzureTranslator
    from app.providers.azure_tts import AzureStreamingTts

    s = settings()
    mt, tts = AzureTranslator(s), AzureStreamingTts(s)
    os.makedirs(CLIPS, exist_ok=True)
    texts: dict[str, list[str]] = {"en-IN": SENTENCES}
    for lang in SPOKEN[1:]:
        texts[lang] = [await mt.translate(t, "en-IN", lang) for t in SENTENCES]
    meta: dict[str, list[dict]] = {}
    for lang in SPOKEN:
        meta[lang] = []
        for i, text in enumerate(texts[lang]):
            chunks = [c async for c in tts.stream_pcm(text, lang, None)]
            pcm = b"".join(chunks)
            with open(f"{CLIPS}/{lang}_{i}.pcm", "wb") as fh:
                fh.write(pcm)
            meta[lang].append({"text": text, "seconds": len(pcm) / 32000})
            print(lang, i, round(len(pcm) / 32000, 2), "s", flush=True)
    save("clips", meta)


# ── recog: language identification and WER under four conditions ──────────────
async def recognize(pcm: bytes, lang: str, mode: str) -> dict:
    from app.providers.azure_stt import AzureStreamingStt

    stt = AzureStreamingStt(settings())
    if mode == "fixed":
        await stt.start(lang)
    else:
        if mode == "pinned":
            stt.prepare_detection(lang, PARTNER[lang])
            stt.pin_only = True
        elif mode == "pinned_filled":
            stt.prepare_detection(lang, PARTNER[lang])
            stt.pin_only = False
        else:  # catalog order, no preferences
            stt.prepare_detection()
        await stt.start("auto")
    for i in range(0, len(pcm), FRAME):
        await stt.push_pcm(pcm[i:i + FRAME])
    finals: list[tuple[str, str]] = []
    try:
        while True:
            item = await asyncio.wait_for(stt._results.get(), timeout=5.0)
            if item is None:
                break
            if item.is_final:
                finals.append((item.text, item.language))
    except asyncio.TimeoutError:
        pass
    await stt.close()
    return {"hyp": " ".join(t for t, _ in finals), "langs": [lg for _, lg in finals]}


async def cmd_recog() -> None:
    meta = load("clips")
    modes = ["fixed", "pinned", "pinned_filled", "catalog"]
    jobs = [(lang, i, mode) for mode in modes for lang in SPOKEN for i in range(len(SENTENCES))]
    sem = asyncio.Semaphore(int(os.environ.get("EVAL_CONC", "2")))
    results: list[dict] = []

    async def run(lang: str, i: int, mode: str) -> None:
        async with sem:
            pcm = padded(clip_pcm(lang, i), 0.3, 1.5)
            try:
                out = await recognize(pcm, lang, mode)
            except Exception as exc:  # noqa: BLE001
                out = {"hyp": "", "langs": [], "error": repr(exc)}
            ref = meta[lang][i]["text"]
            base = lang.split("-")[0]
            langs = [x for x in out["langs"] if x]
            results.append({
                "lang": lang, "idx": i, "mode": mode, "ref": ref, **out,
                "wer": wer(ref, out["hyp"]), "cer": cer(ref, out["hyp"]),
                "lang_ok": (all(x.split("-")[0] == base for x in langs) if langs else None),
            })
            print(mode, lang, i, round(results[-1]["wer"], 2), langs[:2], flush=True)

    await asyncio.gather(*(run(*j) for j in jobs))
    save("recog", results)


# ── mt: translation time, script, round trip ──────────────────────────────────
async def cmd_mt() -> None:
    import app.providers.azure_translate as azt
    from app.providers.azure_translate import AzureTranslator

    s = settings()
    rows = []
    real_latin = azt.is_latin_heavy
    for variant in ("with_retry", "no_retry"):
        azt.is_latin_heavy = real_latin if variant == "with_retry" else (lambda _t: False)
        for lang in INDIC:
            mt = AzureTranslator(s)
            for i, text in enumerate(SENTENCES):
                t0 = time.perf_counter()
                out = await mt.translate(text, "en-IN", lang)
                ms = (time.perf_counter() - t0) * 1000
                back = await AzureTranslator(s).translate(out, lang, "en-IN") if variant == "with_retry" else ""
                rows.append({
                    "kind": "forward", "variant": variant, "lang": lang, "idx": i, "ms": ms,
                    "out": out, "script_share": script_share(out, lang),
                    "latin_heavy": real_latin(out),
                    "roundtrip_chrf": chrf(text, back) if back else None,
                })
        mt = AzureTranslator(s)
        for i, text in enumerate(ROMANIZED):
            t0 = time.perf_counter()
            out = await mt.translate(text, "auto", "hi-IN")
            rows.append({
                "kind": "romanized", "variant": variant, "lang": "hi-IN", "idx": i,
                "ms": (time.perf_counter() - t0) * 1000, "out": out,
                "script_share": script_share(out, "hi-IN"), "latin_heavy": real_latin(out),
            })
        print(variant, "done", flush=True)
    azt.is_latin_heavy = real_latin
    save("mt", rows)


# ── e2e: full pipeline through the media websocket ────────────────────────────
async def pace(ws, pcm: bytes, seq: int, clock: dict | None = None) -> int:
    """Send PCM as 20 ms uplink frames at real-time speed."""
    start = time.perf_counter()
    n = 0
    for i in range(0, len(pcm), FRAME):
        await ws.send(HEADER.pack(seq, 1, 0, 0) + pcm[i:i + FRAME].ljust(FRAME, b"\x00"))
        seq += 1
        n += 1
        delay = start + n * 0.02 - time.perf_counter()
        if delay > 0:
            await asyncio.sleep(delay)
    return seq


async def open_leg(connect, call_id: str, peer: str, hear: str, dst: str):
    ws = await connect(WS_URI, max_size=2**22)
    await ws.send(json.dumps({
        "type": "session.start", "call_id": call_id, "peer_id": peer, "src_lang": "auto",
        "dst_lang": dst, "hear_lang": hear, "sample_rate_hz": 16000,
    }))
    return ws


async def e2e_run(src: str, dst: str, idx: int, meta: dict) -> dict:
    import websockets

    call = f"eval-{uuid.uuid4().hex[:8]}"
    a = await open_leg(websockets.connect, call, f"a-{call}", src, dst)
    b = await open_leg(websockets.connect, call, f"b-{call}", dst, src)
    ev: dict = {"b_audio_first": None, "b_audio_bytes": 0, "a_final": None, "a_text": "",
                "a_first_partial": None, "b_remote_first": None, "b_remote_final": None,
                "b_remote_text": "", "latency": None, "errors": [], "tts_end": None}

    async def read_a() -> None:
        async for m in a:
            if isinstance(m, bytes):
                continue
            j = json.loads(m)
            now = time.perf_counter()
            if j.get("type") == "subtitle_local":
                if ev["a_first_partial"] is None:
                    ev["a_first_partial"] = now
                if j.get("is_final"):
                    ev["a_final"] = now
                    ev["a_text"] += " " + j.get("text", "")
            elif j.get("type") == "latency" and ev["latency"] is None:
                ev["latency"] = j.get("stages_ms")
            elif j.get("type") == "error":
                ev["errors"].append(j)

    async def read_b() -> None:
        async for m in b:
            now = time.perf_counter()
            if isinstance(m, bytes):
                ev["b_audio_bytes"] += max(len(m) - 8, 0)
                if ev["b_audio_first"] is None:
                    ev["b_audio_first"] = now
                continue
            j = json.loads(m)
            if j.get("type") == "subtitle_remote":
                if ev["b_remote_first"] is None:
                    ev["b_remote_first"] = now
                if j.get("is_final"):
                    ev["b_remote_final"] = now
                    ev["b_remote_text"] += " " + j.get("text", "")
            elif j.get("type") == "tts.end":
                ev["tts_end"] = now

    ra, rb = asyncio.create_task(read_a()), asyncio.create_task(read_b())
    await asyncio.sleep(1.0)
    speech = clip_pcm(src, idx)
    lead = b"\x00\x00" * int(16000 * 0.3)
    t_send = time.perf_counter()
    seq = await pace(a, lead + speech, 0)
    t_speech_end = time.perf_counter()
    await pace(a, b"\x00\x00" * int(16000 * 4.0), seq)
    await asyncio.sleep(4.0)
    for t in (ra, rb):
        t.cancel()
    await a.close()
    await b.close()
    ref = meta[src][idx]["text"]

    def d(x):
        return None if x is None else (x - t_speech_end) * 1000

    return {
        "src": src, "dst": dst, "idx": idx, "seconds": len(speech) / 32000,
        "first_audio_ms": d(ev["b_audio_first"]), "stt_final_ms": d(ev["a_final"]),
        "caption_first_ms": d(ev["b_remote_first"]), "caption_final_ms": d(ev["b_remote_final"]),
        "tts_end_ms": d(ev["tts_end"]), "audio_seconds": ev["b_audio_bytes"] / 32000,
        "server_stages": ev["latency"], "errors": len(ev["errors"]),
        "wer": wer(ref, ev["a_text"]), "heard": ev["a_text"].strip(), "translated": ev["b_remote_text"].strip(),
        "sent_ms": (t_speech_end - t_send) * 1000,
    }


async def cmd_e2e() -> None:
    meta = load("clips")
    pairs = [("en-IN", "hi-IN"), ("hi-IN", "en-IN"), ("en-IN", "ta-IN"), ("mr-IN", "en-IN")]
    out: list[dict] = []
    for conc, per_pair in ((1, 6), (3, 3)):
        sem = asyncio.Semaphore(conc)
        rows: list[dict] = []

        async def run(src: str, dst: str, i: int) -> None:
            async with sem:
                try:
                    r = await e2e_run(src, dst, i, meta)
                except Exception as exc:  # noqa: BLE001
                    r = {"src": src, "dst": dst, "idx": i, "error": repr(exc)}
                r["concurrency"] = conc
                rows.append(r)
                print(conc, src, dst, i, r.get("first_audio_ms"), flush=True)

        offset = 0 if conc == 1 else 6
        await asyncio.gather(*(run(s_, d_, i + offset) for s_, d_ in pairs for i in range(per_pair)))
        out.extend(rows)
    save("e2e", out)


# ── switch: speaker changes the language they speak mid-call ──────────────────
async def switch_run(first: str, second: str, i: int, j: int, gap_s: float, do_switch: bool, meta: dict) -> dict:
    import websockets

    call = f"eval-{uuid.uuid4().hex[:8]}"
    a = await open_leg(websockets.connect, call, f"a-{call}", first, second)
    b = await open_leg(websockets.connect, call, f"b-{call}", second, first)
    texts: list[tuple[float, str, str]] = []

    async def read_a() -> None:
        async for m in a:
            if isinstance(m, bytes):
                continue
            jn = json.loads(m)
            if jn.get("type") == "subtitle_local" and jn.get("is_final"):
                texts.append((time.perf_counter(), jn.get("text", ""), jn.get("bcp47", "")))

    async def drain_b() -> None:
        async for _ in b:
            pass

    ra, rb = asyncio.create_task(read_a()), asyncio.create_task(drain_b())
    await asyncio.sleep(1.0)
    seq = await pace(a, b"\x00\x00" * 4800 + clip_pcm(first, i), 0)
    seq = await pace(a, b"\x00\x00" * int(16000 * 3.0), seq)
    # Let the translated voice finish so the echo guard is not in play, then switch.
    await asyncio.sleep(4.0)
    t_switch = time.perf_counter()
    if do_switch:
        await a.send(json.dumps({"type": "languages.set", "hear_lang": second}))
    seq = await pace(a, b"\x00\x00" * int(16000 * gap_s), seq)
    t_second = time.perf_counter()
    seq = await pace(a, clip_pcm(second, j), seq)
    await pace(a, b"\x00\x00" * int(16000 * 3.0), seq)
    await asyncio.sleep(2.5)
    for t in (ra, rb):
        t.cancel()
    await a.close()
    await b.close()
    after = " ".join(t for ts, t, _ in texts if ts >= t_second)
    ref = meta[second][j]["text"]
    return {"first": first, "second": second, "gap_s": gap_s, "switched": do_switch,
            "hyp": after, "ref": ref, "wer": wer(ref, after), "cer": cer(ref, after)}


async def cmd_switch() -> None:
    meta = load("clips")
    rows = []
    sem = asyncio.Semaphore(2)

    async def run(first, second, i, j, gap, do):
        async with sem:
            try:
                r = await switch_run(first, second, i, j, gap, do, meta)
            except Exception as exc:  # noqa: BLE001
                r = {"first": first, "second": second, "gap_s": gap, "switched": do, "error": repr(exc)}
            rows.append(r)
            print(first, second, gap, do, r.get("wer"), flush=True)

    jobs = []
    for first, second in (("hi-IN", "en-IN"), ("en-IN", "mr-IN")):
        for n in range(4):
            for gap, do in ((0.3, True), (1.0, True), (1.0, False)):
                jobs.append(run(first, second, n, n + 4, gap, do))
    await asyncio.gather(*jobs)
    save("switch", rows)


# ── echo: guard coverage on real chunk timings ────────────────────────────────
async def cmd_echo() -> None:
    import app.hub as hub
    from app.providers.azure_tts import AzureStreamingTts

    s = settings()
    meta = load("clips")
    tts = AzureStreamingTts(s)
    tail = hub.ECHO_TAIL_S
    rows = []
    for lang, idx in (("en-IN", 0), ("en-IN", 2), ("en-IN", 6), ("hi-IN", 0), ("hi-IN", 2), ("ta-IN", 2)):
        text = meta[lang][idx]["text"]
        arrivals: list[tuple[float, int]] = []
        t0 = time.perf_counter()
        async for pcm in tts.stream_pcm(text, lang, None):
            arrivals.append((time.perf_counter() - t0, len(pcm)))
        total = sum(n for _, n in arrivals) / 32000
        first = arrivals[0][0]
        # Assume the phone starts playing at the first chunk and plays the queue without gaps.
        play_start, play_end = first, first + total

        def guard_old(t: float) -> bool:
            until = 0.0
            for at, n in arrivals:
                if at <= t:
                    until = max(until, at + n / 32000 + tail)
            return t < until

        class Clock:
            now = 0.0

        room = hub.CallRoom(call_id="eval")
        room.peers = {"speaker": object(), "listener": object()}  # type: ignore[assignment]
        real_monotonic = hub.time.monotonic
        hub.time.monotonic = lambda: Clock.now  # type: ignore[assignment]

        def guard_new(t: float) -> bool:
            Clock.now = 1000.0 + t
            room.echo_guard_until.clear()
            room.playback_end.clear()
            for at, n in arrivals:
                if at <= t:
                    Clock.now = 1000.0 + at
                    room.mark_receivers_playing("speaker", n, 16000)
            Clock.now = 1000.0 + t
            return room.uplink_is_echo("listener")

        step = 0.01
        grid = [play_start + k * step for k in range(int((play_end - play_start) / step))]
        old_cov = sum(guard_old(t) for t in grid) / len(grid)
        new_cov = sum(guard_new(t) for t in grid) / len(grid)
        hub.time.monotonic = real_monotonic
        last_arrival = arrivals[-1][0]
        rows.append({
            "lang": lang, "idx": idx, "audio_s": total, "chunks": len(arrivals),
            "first_chunk_s": first, "last_chunk_s": last_arrival,
            "delivery_x_realtime": total / max(last_arrival - first, 1e-3),
            "old_coverage": old_cov, "new_coverage": new_cov,
            "old_unguarded_s": (1 - old_cov) * total, "new_unguarded_s": (1 - new_cov) * total,
        })
        print(rows[-1], flush=True)
    save("echo", rows)


COMMANDS = {"synth": cmd_synth, "recog": cmd_recog, "mt": cmd_mt, "e2e": cmd_e2e,
            "switch": cmd_switch, "echo": cmd_echo}

if __name__ == "__main__":
    asyncio.run(COMMANDS[sys.argv[1]]())
