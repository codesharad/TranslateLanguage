import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SignalHandler = void Function(Map<String, dynamic> message);

/// Signaling: JWT auth, dial-user / incoming-call, SDP/ICE.
class SignalingService {
  SignalingService({required this.url, required this.onMessage, this.onStatus});

  final String url;
  final SignalHandler onMessage;
  final void Function(bool connected)? onStatus;
  WebSocketChannel? _channel;
  Timer? _retry;
  Timer? _ping;
  bool connected = false;
  bool _disposed = false;
  int _generation = 0;
  int _attempt = 0;
  int _missedPongs = 0;
  Map<String, dynamic>? _register;
  String? _accessToken;

  Future<void> connect({
    required String userId,
    required String deviceId,
    required String platform,
    required String displayName,
    String? accessToken,
    String? pushToken,
    String? language,
  }) async {
    _accessToken = accessToken;
    _register = {
      'type': 'register',
      'userId': userId,
      'deviceId': deviceId,
      'platform': platform,
      'displayName': displayName,
      if (pushToken != null && pushToken.isNotEmpty) 'pushToken': pushToken,
      if (language != null) 'language': language,
    };
    await _open();
  }

  Future<void> _open() async {
    if (_disposed) return;
    _retry?.cancel();
    final gen = ++_generation;
    final previous = _channel;
    _channel = null;
    try {
      await previous?.sink.close();
    } catch (_) {}

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      await channel.ready.timeout(const Duration(seconds: 8));
      if (_disposed || gen != _generation) {
        try {
          await channel.sink.close();
        } catch (_) {}
        return;
      }
      _channel = channel;
      channel.stream.listen(
        (event) {
          if (gen != _generation) return;
          _missedPongs = 0;
          final map = jsonDecode(event as String) as Map<String, dynamic>;
          onMessage(map);
        },
        onDone: () {
          if (_disposed || gen != _generation) return;
          debugPrint('signaling closed code=${channel.closeCode}');
          _scheduleReconnect();
        },
        onError: (e) {
          if (_disposed || gen != _generation) return;
          debugPrint('signaling error $e');
          _scheduleReconnect();
        },
      );
      if (_accessToken != null) {
        send({'type': 'auth', 'token': _accessToken});
      }
      if (_register != null) send(_register!);
      connected = true;
      _attempt = 0;
      onStatus?.call(true);
      _armHeartbeat(gen);
    } catch (e) {
      if (_disposed || gen != _generation) return;
      debugPrint('signaling connect $e');
      connected = false;
      onStatus?.call(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _ping?.cancel();
    connected = false;
    onStatus?.call(false);
    _retry?.cancel();
    final seconds = (1 << _attempt).clamp(1, 20);
    _attempt = (_attempt + 1).clamp(0, 5);
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void _armHeartbeat(int gen) {
    _ping?.cancel();
    _missedPongs = 0;
    _ping = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_disposed || gen != _generation || !connected) return;
      _missedPongs += 1;
      if (_missedPongs > 2) {
        debugPrint('signaling heartbeat lost');
        _scheduleReconnect();
        return;
      }
      send({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch});
    });
  }

  void dialUser({
    required String to,
    required String hearLang,
  }) {
    send({
      'type': 'dial-user',
      'to': to,
      'hearLang': hearLang,
      'srcLang': hearLang,
      'dstLang': hearLang,
    });
  }

  void accept(String callId) => send({'type': 'accept-call', 'callId': callId});

  void reject(String callId) => send({'type': 'reject-call', 'callId': callId});

  void hangup(String callId) => send({'type': 'end-call', 'callId': callId});

  void sendOffer(String callId, String sdp) =>
      send({'type': 'webrtc.offer', 'callId': callId, 'sdp': sdp});

  void sendAnswer(String callId, String sdp) =>
      send({'type': 'webrtc.answer', 'callId': callId, 'sdp': sdp});

  void sendIce(String callId, Map<String, dynamic> candidate) =>
      send({'type': 'webrtc.ice', 'callId': callId, 'candidate': candidate});

  void setPreferredLanguage({String? callId, required String hearLang}) {
    if (_register != null) {
      _register = {..._register!, 'language': hearLang};
      send(_register!);
    }
    if (callId != null && callId.isNotEmpty) {
      send({
        'type': 'languages.set',
        'callId': callId,
        'hearLang': hearLang,
        'srcLang': hearLang,
      });
    }
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    _ping?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    connected = false;
  }
}
