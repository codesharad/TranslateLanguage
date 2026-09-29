# CallKit (iOS) and ConnectionService (Android)

Native call UI is **not** optional if you want Bluetooth headsets, Now Playing
audio session, and the system incoming-call banner.

## iOS

1. Enable **PushKit VoIP** + **CallKit** + **Background Modes**: `audio`,
   `voip`, `remote-notification`.
2. `UIBackgroundModes` must include `voip`. Using a generic remote
   notification for an incoming call **will be rejected** by App Review and
   will not reliably wake the process.
3. On VoIP push: immediately `CXProvider.reportNewIncomingCall`. You have
   ~2–3 s. Do **not** await network before reporting.
4. Configure `RTCAudioSession` in `provider:didActivate:audioSession`:

```objc
RTCAudioSession.sharedInstance.useManualAudio = YES;
[RTCAudioSession.sharedInstance audioSessionDidActivate:audioSession];
```

5. Info.plist microphone usage string is required.
6. Entitlement: `com.apple.developer.pushkit.unrestricted-voip` is restricted;
   standard VoIP pushes are enough if you report CallKit immediately.

## Android

1. Declare `MANAGE_OWN_CALLS`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`,
   `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`,
   `FOREGROUND_SERVICE_PHONE_CALL`, `USE_FULL_SCREEN_INTENT`.
2. Use `ConnectionService` (`flutter_callkit_incoming` does this) so the
   Telecom stack owns the call. A custom Activity alone will lose audio
   focus on many OEMs (Xiaomi, Oppo, Samsung).
3. Incoming FCM: `priority: high`, data-only payload, full-screen intent
   on Android 10+.
4. Start a **microphone** typed foreground service while in call (Android 14+).
5. Route: `AudioManager.MODE_IN_COMMUNICATION` + AEC.

## Audio session conflict

Flutter plugins that start their own `AudioSession` (just_audio, record)
**will fight CallKit**. Bind playback to the WebRTC / callkit audio session:

- iOS: `AVAudioSessionCategoryPlayAndRecord`, mode `voiceChat`,
  options `allowBluetoothA2DP` off, `allowBluetooth` on.
- Android: `MODE_IN_COMMUNICATION`, `VOICE_COMMUNICATION` AudioSource.
