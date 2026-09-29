# WebRTC audio pipeline (CallKit / ConnectionService)

This is the VoIP path. Translation PCM is a **parallel** stream; see
`mobile/lib/services/webrtc_service.dart` and `translation_socket.dart`.

```
  Mic
   │  AudioSource.VOICE_COMMUNICATION / AVAudioSession voiceChat
   ▼
  WebRTC AEC3 + NS + AGC          ← 20 ms, 16 kHz or 48 kHz
   │
   ├──────────── capture tap ──► PCM 16 kHz ──► Orchestrator WS (STT)
   │
   ▼
  RTCPeerConnection (gateway)     ← SDP/ICE via signaling
   │  local audio track.enabled = false  (do not send original speech)
   ▼
  Remote "translated" track       ← optional: inject TTS as a fake track
   │
   ▼
  CallKit / Telecom audio unit    ← earpiece default, BT SCO
   ▲
   └── TTS PCM player (USAGE_VOICE_COMMUNICATION / voiceChat)
```

## Offer / answer (what the Flutter service does)

1. `getUserMedia({ audio: { echoCancellation, noiseSuppression, sampleRate: 16000 }})`
2. `addTrack` then **disable** the track toward the peer.
3. `createOffer({ offerToReceiveAudio: 1, voiceActivityDetection: true })`
4. Trickle ICE through signaling (`webrtc.ice`).
5. Bind `RTCAudioSession` only after CallKit `didActivate`.

## Why the mic track is disabled

If original Tamil reaches B’s earpiece, B hears Tamil **and** Hindi TTS.
Disable the track, keep the PeerConnection for AEC/routing, and play TTS
through the call audio session.

## Production upgrade

Replace the second `record` capture with a WebRTC **audio processor tap**
(native `RTCAudioDeviceModule` on iOS / `JavaAudioDeviceModule` on Android)
so there is one capture graph, one AEC reference, and no session fighting.
