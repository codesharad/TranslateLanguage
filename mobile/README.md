# Bootstrap the Flutter project once, then keep the files in this folder.

flutter create . --project-name translate_language --org com.translatelanguage

If `flutter create` offers to overwrite `lib/main.dart`, `AndroidManifest.xml`,
`Info.plist`, `AppDelegate.swift`, or `MainActivity.kt`, decline — those are
the translator-call implementations.

Debug builds use `http://127.0.0.1:8080`. On a USB phone, forward the port first:

```
adb -s <serial> reverse tcp:8080 tcp:8080
flutter run -d <serial>
```

Without USB, pass the PC's LAN address: `flutter run --dart-define=API_HOST=192.168.1.10:8080`.
Release builds use the hosted server. See the root README for every flag.
