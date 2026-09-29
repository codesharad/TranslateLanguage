import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  AppConfig({
    required this.apiBase,
    required this.signalingUrl,
    required this.orchestratorUrl,
    required this.useCloud,
    required this.cloudHost,
  });

  final String apiBase;
  final String signalingUrl;
  final String orchestratorUrl;
  final bool useCloud;
  final String cloudHost;

  static const _modeKey = 'use_cloud';
  static const _hostKey = 'cloud_host';

  /// Local USB/LAN socket, or the public `wss://` host when [useCloud] is set.
  factory AppConfig.choose({required bool useCloud, required String cloudHost}) {
    const localHost = String.fromEnvironment('API_HOST', defaultValue: '127.0.0.1');
    const compiledCloud = String.fromEnvironment('CLOUD_HOST', defaultValue: '');
    const forcedTls = bool.fromEnvironment('API_TLS', defaultValue: false);
    final cleaned = _cleanHost(cloudHost.isNotEmpty ? cloudHost : compiledCloud);
    final cloud = useCloud && cleaned.isNotEmpty;
    final host = cloud ? cleaned : localHost;
    return _from(
      host: host,
      tls: cloud || forcedTls,
      useCloud: cloud,
      cloudHost: cleaned,
    );
  }

  factory AppConfig.fromEnvironment() => AppConfig.choose(useCloud: false, cloudHost: '');

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    const compiledCloud = String.fromEnvironment('CLOUD_HOST', defaultValue: '');
    return AppConfig.choose(
      useCloud: prefs.getBool(_modeKey) ?? false,
      cloudHost: prefs.getString(_hostKey) ?? compiledCloud,
    );
  }

  static Future<void> save({required bool useCloud, required String cloudHost}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_modeKey, useCloud);
    await prefs.setString(_hostKey, _cleanHost(cloudHost));
  }

  static AppConfig _from({
    required String host,
    required bool tls,
    required bool useCloud,
    required String cloudHost,
  }) {
    const api = String.fromEnvironment('API_BASE', defaultValue: '');
    const signaling = String.fromEnvironment('SIGNALING_URL', defaultValue: '');
    const orchestrator = String.fromEnvironment('ORCHESTRATOR_URL', defaultValue: '');
    final http = tls ? 'https' : 'http';
    final ws = tls ? 'wss' : 'ws';
    final port = tls ? '' : ':8080';
    final base = api.isNotEmpty ? api : '$http://$host$port';
    return AppConfig(
      apiBase: base,
      signalingUrl: signaling.isNotEmpty ? signaling : '$ws://$host$port/v1/signal',
      orchestratorUrl: orchestrator.isNotEmpty ? orchestrator : '$ws://$host$port/v1/media',
      useCloud: useCloud,
      cloudHost: cloudHost,
    );
  }

  static String _cleanHost(String raw) {
    var host = raw.trim();
    host = host.replaceFirst(RegExp(r'^https?://'), '');
    host = host.replaceFirst(RegExp(r'^wss?://'), '');
    final slash = host.indexOf('/');
    if (slash >= 0) host = host.substring(0, slash);
    return host;
  }
}
