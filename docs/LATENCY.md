# Latency budget — target < 1.0 s mouth-to-ear

Measured from **end of a short utterance** (Silero VAD cut) to **first audible
TTS sample** on the far side.

Sub-second is a **pipeline** property, not a single model. The 180 ms VAD
silence is still the largest term. Everything else must stay in the 100–200 ms
band.

## Budget (India region)

| Stage                         | Target | Hard cap | How |
|-------------------------------|--------|----------|-----|
| Capture + 20 ms packetize     | 25 ms  | 40 ms    | 16 kHz PCM, no device resample |
| Uplink                        | 60 ms  | 100 ms   | WS PCM on LAN / 5G; TURN only if ICE needs it |
| Silero VAD endpointing        | 180 ms | 220 ms   | `VAD_SILENCE_MS=180`, max utterance 1.8 s |
| Streaming STT (first usable)  | 150 ms | 280 ms   | Sarvam `saaras:v3-realtime` `stream_type=fast`, or Google V2 `latest_short` interims |
| Translation                   | 80 ms  | 150 ms   | Mayura / Azure NMT / gpt-4o-mini, HTTP/2, cache |
| Streaming TTS first byte      | 150 ms | 250 ms   | Azure pull-stream or Sarvam Bulbul on a short phrase |
| Downlink + 2-frame jitter     | 50 ms  | 80 ms    | Play after 40 ms, do not wait for `tts.end` |
| **Total**                     | **~695 ms** | **< 1000 ms** | |

## Practices that hit sub-1 s

1. **Silero, not punctuation.** Cut at 180 ms silence. 400 ms VAD makes 1 s impossible.
2. **Speculative TTS** on stable interims (`PARTIAL_TRANSLATE=true`, 4+ chars). Cancel if the final diverges.
3. **Barge-in** on `speech_start` — cancel far-side TTS immediately.
4. **20 ms LINEAR16 frames.** No MP3/AAC. No 100 ms batches.
5. **Regional endpoints.** `centralindia` / `asia-south1` / Sarvam (India).
6. **Reuse sockets.** One STT websocket per call leg. `config.update` for language switch — no reconnect.
7. **LLM prompts must be tiny.** Translate-only, `max_tokens=120`, `temperature=0`. Neural MT is usually faster than an LLM; use gpt-4o-mini/Haiku only if quality needs it.
8. **Half-duplex ducking** so AEC tail does not add 100–200 ms of “is that echo?”.
9. **Earpiece default.** Speakerphone without AEC re-translates TTS.
10. **Client jitter = 2 frames.** `TtsPlaybackService` starts at 40 ms.

## What blows the budget

- Waiting for STT `is_final` without Silero (1–2 s).
- Google `latest_long` / Chirp-2 “accuracy” models.
- Synthesizing a full WAV then sending it.
- New TLS session per utterance.
- `just_audio` / ExoPlayer preroll.
- Translating entire paragraphs (cap utterance at 1.8 s).

## Instrumentation

`vad_end → stt_first_partial → stt_final → mt_done → tts_first_byte`

Shown on the in-call HUD (`server XXXms`). Alert if `e2e_server_ms > 850`.
