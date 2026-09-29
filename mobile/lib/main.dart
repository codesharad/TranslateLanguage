import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'models/call_session.dart';
import 'screens/home_screen.dart';
import 'screens/in_call_screen.dart';
import 'screens/otp_phone_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'state/call_controller.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  runApp(TranslateLanguageApp(config: config));
}

class TranslateLanguageApp extends StatefulWidget {
  const TranslateLanguageApp({super.key, required this.config});
  final AppConfig config;

  @override
  State<TranslateLanguageApp> createState() => _TranslateLanguageAppState();
}

class _TranslateLanguageAppState extends State<TranslateLanguageApp> {
  late AppConfig _config;
  late ApiClient _api;
  late AuthService _auth;
  late CallController _call;
  final _navKey = GlobalKey<NavigatorState>();
  bool _restoring = true;
  bool _callRouteOpen = false;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _attach(_config);
    _restore();
  }

  void _attach(AppConfig config) {
    _api = ApiClient(baseUrl: config.apiBase);
    _auth = AuthService(_api);
    _call = CallController(app: config, api: _api);
    _call.addListener(_onCallChanged);
  }

  void _onCallChanged() {
    if (!mounted) return;
    setState(() {});
    final phase = _call.session?.phase;
    final inCall = phase == CallPhase.ringing ||
        phase == CallPhase.connecting ||
        phase == CallPhase.active;
    if (inCall && !_callRouteOpen) {
      _callRouteOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = _navKey.currentState;
        if (!mounted || navigator == null) {
          _callRouteOpen = false;
          return;
        }
        navigator
            .push(MaterialPageRoute<void>(builder: (_) => const InCallScreen()))
            .whenComplete(() => _callRouteOpen = false);
      });
    }
  }

  Future<void> _restore() async {
    final saved = await _auth.restore();
    if (saved != null) {
      try {
        await _call.startSession(saved.user, saved.token);
      } catch (e, st) {
        debugPrint('session restore failed: $e\n$st');
      }
    }
    if (mounted) setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _call.removeListener(_onCallChanged);
    _call.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _auth),
        ChangeNotifierProvider.value(value: _call),
      ],
      child: MaterialApp(
        title: 'TranslateLanguage',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navKey,
        theme: buildTheme(),
        home: _restoring
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : (_call.userId.isEmpty ? const OtpPhoneScreen() : const HomeScreen()),
      ),
    );
  }
}
