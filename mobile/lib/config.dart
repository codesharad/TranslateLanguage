class AppConfig {
  AppConfig({
    required this.apiBase,
    required this.signalingUrl,
    required this.orchestratorUrl,
  });

  final String apiBase;
  final String signalingUrl;
  final String orchestratorUrl;

  static const host = 'translatelanguage.onrender.com';

  factory AppConfig.production() => _from(host);

  static Future<AppConfig> load() async => AppConfig.production();

  static AppConfig _from(String host) {
    const api = String.fromEnvironment('API_BASE', defaultValue: '');
    const signaling = String.fromEnvironment('SIGNALING_URL', defaultValue: '');
    const orchestrator = String.fromEnvironment('ORCHESTRATOR_URL', defaultValue: '');
    return AppConfig(
      apiBase: api.isNotEmpty ? api : 'https://$host',
      signalingUrl: signaling.isNotEmpty ? signaling : 'wss://$host/v1/signal',
      orchestratorUrl: orchestrator.isNotEmpty ? orchestrator : 'wss://$host/v1/media',
    );
  }
}
