import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

/// Plays 16 kHz PCM16 (peer voice and TTS) on the voice-communication path.
///
/// While frames are playing, [onPlayback] is true so the mic uplink is muted.
/// It stays true for 200 ms after the last frame so speaker tail does not
/// leak back into the microphone.
class TtsPlaybackService {
  static const _channel = MethodChannel('translatelanguage/pcm_player');
  final Queue<Uint8List> _buffer = Queue();
  bool _started = false;
  bool _playing = false;
  int _generation = 0;
  Timer? _tail;

  void Function(bool playing)? onPlayback;

  Future<void> start() async {
    if (_started) return;
    await _channel.invokeMethod('start', {'sampleRate': 16000});
    _started = true;
  }

  Future<void> setSpeaker(bool on) async {
    if (!_started) return;
    try {
      await _channel.invokeMethod('setSpeaker', {'on': on});
    } catch (_) {}
  }

  Future<void> enqueue(Uint8List pcm, {required int generation}) async {
    if (generation != _generation || pcm.isEmpty) return;
    if (!_started) await start();
    _noteStart();
    _buffer.add(pcm);
    if (_buffer.length >= 2) {
      while (_buffer.isNotEmpty) {
        final frame = _buffer.removeFirst();
        await _channel.invokeMethod('write', {'bytes': frame});
      }
    }
    _armTail();
  }

  void _noteStart() {
    _tail?.cancel();
    if (_playing) return;
    _playing = true;
    onPlayback?.call(true);
  }

  void _armTail() {
    _tail?.cancel();
    _tail = Timer(const Duration(milliseconds: 200), () {
      if (!_playing) return;
      _playing = false;
      onPlayback?.call(false);
    });
  }

  Future<void> cancel({required int generation}) async {
    _generation = generation;
    _buffer.clear();
    if (_started) {
      await _channel.invokeMethod('flush');
    }
    _armTail();
  }

  Future<void> stop() async {
    _tail?.cancel();
    _buffer.clear();
    if (_playing) {
      _playing = false;
      onPlayback?.call(false);
    }
    if (_started) {
      await _channel.invokeMethod('stop');
      _started = false;
    }
  }
}
