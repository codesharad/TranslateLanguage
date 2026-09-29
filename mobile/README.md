# Bootstrap the Flutter project once, then keep the files in this folder.

flutter create . --project-name translate_language --org com.translatelanguage

If `flutter create` offers to overwrite `lib/main.dart`, `AndroidManifest.xml`,
`Info.plist`, `AppDelegate.swift`, or `MainActivity.kt`, decline — those are
the translator-call implementations.

Physical devices cannot reach `127.0.0.1` on your PC. Pass your LAN IP:

```
flutter run --dart-define=SIGNALING_URL=ws://192.168.1.10:8080/v1/signal \
            --dart-define=ORCHESTRATOR_URL=ws://192.168.1.10:8090/v1/media \
            --dart-define=USER_ID=user-a
```
