import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'webrtc_service.dart';

class MediaEvent {
  MediaEvent(this.type, this.json, {this.bytes});
  final String type;
  final Map<String, dynamic> json;
  final Uint8List? bytes;
}

/// Orchestrator WebSocket: PCM uplink + TTS downlink + transcripts.
///
/// Reconnects with exponential backoff and resumes the same call/peer ids
/// after a network change. Application pings detect a half-open socket.
class TranslationSocket {
  TranslationSocket({required this.url, required this.onEvent});

  final String url;
  final void Function(MediaEvent event) onEvent;
  WebSocketChannel? _channel;
  Timer? _retry;
  Timer? _ping;
  int _seq = 0;
  int _generation = 0;
  int _attempt = 0;
  int _missedPongs = 0;
  bool _disposed = false;
  String? _callId;
  String? _peerId;
  String? _hearLang;
  String? _dstLang;
  String? _voice;

  Future<void> connect({
    required String callId,
    required String peerId,
    required String dstLang,
    String? hearLang,
    String? voice,
  }) async {
    _callId = callId;
    _peerId = peerId;
    _hearLang = hearLang;
    _dstLang = dstLang;
    _voice = voice;
    _disposed = false;
    await _open();
  }

  Future<void> _open() async {
    if (_disposed || _callId == null) return;
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
        _onData,
        onDone: () {
          if (_disposed || gen != _generation) return;
          debugPrint('media closed code=${channel.closeCode}');
          _scheduleReconnect();
        },
        onError: (Object e) {
          if (_disposed || gen != _generation) return;
          debugPrint('media ws $e');
          _scheduleReconnect();
        },
      );
      _sendJson({
        'type': 'session.start',
        'call_id': _callId,
        'peer_id': _peerId,
        'src_lang': 'auto',
        'hear_lang': _hearLang,
        'dst_lang': _dstLang,
        'voice': _voice,
        'sample_rate_hz': 16000,
      });
      _attempt = 0;
      _armHeartbeat(gen);
    } catch (e) {
      if (_disposed || gen != _generation) return;
      debugPrint('media connect $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _ping?.cancel();
    _retry?.cancel();
    final seconds = (1 << _attempt).clamp(1, 20);
    _attempt = (_attempt + 1).clamp(0, 5);
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void _armHeartbeat(int gen) {
    _ping?.cancel();
    _missedPongs = 0;
    _ping = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_disposed || gen != _generation || _channel == null) return;
      _missedPongs += 1;
      if (_missedPongs > 2) {
        debugPrint('media heartbeat lost');
        _scheduleReconnect();
        return;
      }
      _sendJson({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch});
    });
  }

  void sendPcm(Uint8List pcm, {bool utteranceEnd = false}) {
    if (_channel == null || pcm.isEmpty) return;
    _seq += 1;
    final framed = pcmHeader(seq: _seq, kind: 1, utteranceEnd: utteranceEnd, pcm: pcm);
    try {
      _channel?.sink.add(framed);
    } catch (e) {
      debugPrint('media send $e');
    }
  }

  void setTargetLanguage({required String dstLang, String? voice}) {
    _dstLang = dstLang;
    if (voice != null) _voice = voice;
    _sendJson({
      'type': 'languages.set',
      'dst_lang': dstLang,
    });
  }

  void _sendJson(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('media json $e');
    }
  }

  void _onData(dynamic event) {
    _missedPongs = 0;
    if (event is String) {
      final map = jsonDecode(event) as Map<String, dynamic>;
      _dispatchControl(map);
      return;
    }
    if (event is List<int>) {
      if (event.isNotEmpty && (event.first == 0x7b || event.first == 0x5b)) {
        try {
          final map = jsonDecode(utf8.decode(event)) as Map<String, dynamic>;
          _dispatchControl(map);
          return;
        } catch (e) {
          debugPrint('subtitle json decode $e');
        }
      }
      final bytes = Uint8List.fromList(event);
      onEvent(MediaEvent('pcm', const {}, bytes: bytes));
    }
  }

  void _dispatchControl(Map<String, dynamic> map) {
    final type = map['type'] as String? ?? 'unknown';
    if (type == 'pong') return;
    if (type.startsWith('subtitle')) {
      debugPrint('subtitle rx $type lang=${map['language']} final=${map['is_final']} text=${map['text']}');
    }
    onEvent(MediaEvent(type, map));
  }

  Future<void> close() async {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    _ping?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}
