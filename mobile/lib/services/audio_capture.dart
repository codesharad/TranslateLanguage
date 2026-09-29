import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// 16 kHz / 16-bit / mono PCM capture for the call uplink.
///
/// Android uses [AndroidAudioSource.voiceCommunication] so the hardware
/// acoustic echo canceller is on the same path as playback.
/// iOS uses playAndRecord; the PCM player then pins the session to voiceChat.
class AudioCaptureService {
  AudioCaptureService({required this.onFrame});

  final void Function(Uint8List pcm) onFrame;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final BytesBuilder _stash = BytesBuilder(copy: false);
  static const frameBytes = 640; // 16000 * 0.02 * 2
  bool _ducked = false;

  Future<void> start() async {
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      throw StateError('microphone permission denied');
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceCommunication,
          audioManagerMode: AudioManagerMode.modeInCommunication,
          speakerphone: true,
        ),
        iosConfig: IosRecordConfig(
          categoryOptions: [
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetooth,
          ],
        ),
      ),
    );
    _sub = stream.listen(_onBytes);
  }

  void setDucked(bool ducked) {
    if (ducked && !_ducked) _stash.clear();
    _ducked = ducked;
  }

  void _onBytes(Uint8List data) {
    if (_ducked) return;
    _stash.add(data);
    var buf = _stash.takeBytes();
    var offset = 0;
    while (buf.length - offset >= frameBytes) {
      onFrame(Uint8List.sublistView(buf, offset, offset + frameBytes));
      offset += frameBytes;
    }
    if (offset < buf.length) {
      _stash.add(Uint8List.sublistView(buf, offset));
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _stash.clear();
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('recorder stop: $e');
    }
  }
}
