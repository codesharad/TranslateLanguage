import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig({
    required this.apiBase,
    required this.signalingUrl,
    required this.orchestratorUrl,
  });

  final String apiBase;
  final String signalingUrl;
  final String orchestratorUrl;

  /// Hosted server used by release builds.
  static const hostedHost = 'translatelanguage.onrender.com';

  /// Debug builds on a USB phone reach this PC through `adb reverse tcp:8080 tcp:8080`.
  static const localHost = '127.0.0.1:8080';

  static Future<AppConfig> load() async => fromEnvironment();

  /// Defaults: debug → http://127.0.0.1:8080, release → https://translatelanguage.onrender.com.
  /// `--dart-define=API_HOST=192.168.1.10:8080` picks another server (`API_TLS=true` for https/wss).
  /// API_BASE, SIGNALING_URL, and ORCHESTRATOR_URL still override each URL on its own.
  static AppConfig fromEnvironment() {
    const hostOverride = String.fromEnvironment('API_HOST', defaultValue: '');
    const tlsOverride = String.fromEnvironment('API_TLS', defaultValue: '');
    final host = hostOverride.isNotEmpty ? hostOverride : (kReleaseMode ? hostedHost : localHost);
    final tls = tlsOverride.isNotEmpty ? tlsOverride == 'true' : hostOverride.isEmpty && kReleaseMode;
    final http = tls ? 'https' : 'http';
    final ws = tls ? 'wss' : 'ws';

    const api = String.fromEnvironment('API_BASE', defaultValue: '');
    const signaling = String.fromEnvironment('SIGNALING_URL', defaultValue: '');
    const orchestrator = String.fromEnvironment('ORCHESTRATOR_URL', defaultValue: '');
    return AppConfig(
      apiBase: api.isNotEmpty ? api : '$http://$host',
      signalingUrl: signaling.isNotEmpty ? signaling : '$ws://$host/v1/signal',
      orchestratorUrl: orchestrator.isNotEmpty ? orchestrator : '$ws://$host/v1/media',
    );
  }
}
