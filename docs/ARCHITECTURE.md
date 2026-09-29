# TranslateLanguage — System Architecture

Bi-directional live-call translator. Speaker A (Tamil) talks; Speaker B hears
neural Hindi within **< 1 s**; the reverse path is independent and concurrent.

## 1. Why not naive WebRTC P2P?

A direct A↔B audio track delivers **original-language** speech. A translator
call must **replace** that track with TTS. The correct topology is a
**translation gateway** (SFU + AI agent):

- Each phone has a WebRTC PeerConnection to the gateway, not to the peer.
- CallKit / ConnectionService still present a native incoming/outgoing call.
- The gateway is the only place STT → MT → TTS runs, so both legs share one
  clock, one jitter buffer policy, and one barge-in policy.

```
┌─────────────┐  WebRTC audio + WS transcripts  ┌──────────────────────┐
│  Flutter A  │◄───────────────────────────────►│  Signaling (Node)    │
│  CallKit    │                                  │  rooms / VoIP push   │
└─────────────┘                                  └──────────┬───────────┘
                                                            │ session
                                                            ▼
                                                 ┌──────────────────────┐
                                                 │ Orchestrator (Py)    │
                                                 │ VAD → STT → MT → TTS │
                                                 └──────────────────────┘
                                                            ▲
┌─────────────┐                                             │
│  Flutter B  │◄────────────────────────────────────────────┘
│  ConnService│   translated TTS track + live subtitles
└─────────────┘
```

## 2. End-to-end data path (one utterance)

1. Mic PCM 16 kHz / 16-bit / mono, 20 ms frames (640 bytes).
2. WebRTC Opus uplink **or** raw PCM DataChannel/WebSocket (PCM is used for
   STT to avoid Opus round-trip decode on the server).
3. Server VAD (Silero ONNX, 180 ms silence; WebRTC VAD fallback) segments speech.
4. Streaming STT (Sarvam `saaras:v3-realtime`, Google Speech V2, or Azure) emits interims then a final.
5. Translation on **finals** (Mayura / Azure / gpt-4o-mini / Haiku) and optionally on **interims**
   (speculative TTS, cancelled if the final diverges).
6. Streaming neural TTS first-byte ~150–250 ms; PCM frames pushed immediately.
7. Client jitter buffer 40–80 ms, then play via the CallKit/Telecom audio
   session (earpiece default, AEC on).

## 3. Two audio transports

| Path | Role |
|------|------|
| **WebRTC (Opus)** | Native call audio route, AEC/NS/AGC, Bluetooth, CallKit mix |
| **WebSocket PCM** | Deterministic STT input + TTS output + subtitle JSON |

The Flutter client **mutes the WebRTC mic track to the peer** and instead
feeds the orchestrator. The remote WebRTC track you hear is **TTS injected
as a fake remote MediaStreamTrack** (or played through `just_audio` bound to
the call audio session). That keeps CallKit “in a call” while the words are
translated.

## 4. Feedback / echo (the silent killer)

If B is on speaker, B’s Hindi TTS re-enters B’s mic, gets transcribed as
Hindi, translated back to Tamil, and A hears an echo of themselves.

Mitigations (all enabled by default):

1. **Half-duplex ducking**: while local TTS is playing, uplink is muted
   (20 ms fade). Barge-in energy above threshold unmutes and cancels TTS.
2. **WebRTC AEC3 + NS** on the capture stream.
3. **Earpiece default** for translator calls.
4. **Playback-reference delay** sent to AEC (`setSpeakerphoneOn(false)`).

## 5. Indian language matrix

| Language   | BCP-47 | Google V2 | Azure | Sarvam Saaras / Bulbul | Azure TTS sample        |
|------------|--------|-----------|-------|------------------------|-------------------------|
| Hindi      | hi-IN  | yes       | yes   | yes                    | `hi-IN-SwaraNeural`     |
| Tamil      | ta-IN  | yes       | yes   | yes                    | `ta-IN-PallaviNeural`   |
| Telugu     | te-IN  | yes       | yes   | yes                    | `te-IN-ShrutiNeural`    |
| Malayalam  | ml-IN  | yes       | yes   | yes                    | `ml-IN-SobhanaNeural`   |
| Gujarati   | gu-IN  | yes       | yes   | yes                    | `gu-IN-DhwaniNeural`    |
| Marathi    | mr-IN  | yes       | yes   | yes                    | `mr-IN-AarohiNeural`    |

Translation: Sarvam Mayura, Azure/Google NMT, or gpt-4o-mini / Claude Haiku
(`Translator` interface). Swap in IndicTrans2 on GPU without changing the session.

## 6. Native telephony UX

**iOS — CallKit (`CXProvider`)**

- Incoming: VoIP Push (`PushKit`) → `reportNewIncomingCall` → audio session
  `PlayAndRecord` + `voiceChat` mode **before** WebRTC starts.
- Outgoing: `CXStartCallAction` then connect signaling.
- Audio must be started in `didActivate audioSession`.

**Android — ConnectionService / Telecom**

- `InCallService` + `Connection` with `CAPABILITY_SUPPORTS_VT` off,
  `PROPERTY_SELF_MANAGED` if not the default dialer.
- Audio route via `CallAudioState` (earpiece / speaker / BT).
- Incoming: FCM high-priority data message → full-screen intent
  (Android 10+) → `addNewIncomingCall`.

Plugin: `flutter_callkit_incoming` wraps both.

## 7. Process model

```
signaling (Node, 8080)     — rooms, SDP/ICE, JWT, VoIP push
orchestrator (Python, 8090)— media AI, one process per host, asyncio
redis (optional)           — multi-instance room presence
```

Horizontal scale: sticky sessions by `callId` to the same orchestrator
worker (Redis pub/sub for transcripts if you split WS).
