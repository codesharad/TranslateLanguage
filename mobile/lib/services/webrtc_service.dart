import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC audio PeerConnection bound to CallKit / ConnectionService.
///
/// Translation audio does **not** ride this path as original speech.
/// We still create a PC so:
///   1. Native AEC/NS/AGC and Bluetooth routing stay alive.
///   2. CallKit considers the call "connected".
///   3. ICE proves media connectivity (TURN fallback).
///
/// The uplink mic track is published then immediately `enabled = false`
/// toward the peer. PCM for STT is captured separately at 16 kHz via
/// [AudioCaptureService] and sent on the orchestrator WebSocket.
class WebrtcCallService {
  WebrtcCallService({
    required this.onIce,
    required this.onRemoteStream,
  });

  final void Function(RTCIceCandidate candidate) onIce;
  final void Function(MediaStream stream) onRemoteStream;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  final _iceQueue = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;

  static const _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  Future<void> start({required bool asOfferer, bool captureMic = false}) async {
    _pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) onIce(c);
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) onRemoteStream(event.streams.first);
    };

    if (captureMic) {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'channelCount': 1,
          'sampleRate': 16000,
        },
        'video': false,
      });
      for (final track in _local!.getAudioTracks()) {
        track.enabled = false;
        await _pc!.addTrack(track, _local!);
      }
    }

    await Helper.setSpeakerphoneOn(false);
  }

  Future<RTCSessionDescription> createOffer() async {
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
      'voiceActivityDetection': true,
    });
    await _pc!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer(String remoteSdp) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(remoteSdp, 'offer'));
    _remoteDescriptionSet = true;
    await _drainIce();
    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await _pc!.setLocalDescription(answer);
    return answer;
  }

  Future<void> acceptAnswer(String sdp) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _remoteDescriptionSet = true;
    await _drainIce();
  }

  Future<void> addIce(Map<String, dynamic> json) async {
    final c = RTCIceCandidate(
      json['candidate'] as String?,
      json['sdpMid'] as String?,
      json['sdpMLineIndex'] as int?,
    );
    if (!_remoteDescriptionSet) {
      _iceQueue.add(c);
      return;
    }
    await _pc!.addCandidate(c);
  }

  Future<void> _drainIce() async {
    for (final c in _iceQueue) {
      await _pc!.addCandidate(c);
    }
    _iceQueue.clear();
  }

  Future<void> setMicEnabled(bool enabled) async {
    for (final t in _local?.getAudioTracks() ?? []) {
      // Local AEC path stays alive; we still don't send to peer.
      t.enabled = false;
    }
  }

  Future<void> setSpeaker(bool on) async {
    await Helper.setSpeakerphoneOn(on);
  }

  Future<void> hangup() async {
    await _local?.dispose();
    await _pc?.close();
    _pc = null;
    _local = null;
  }
}

/// Tiny helper: pack PCM16 into a ByteBuffer for the orchestrator.
Uint8List pcmHeader({
  required int seq,
  required int kind,
  required bool utteranceEnd,
  required Uint8List pcm,
}) {
  final out = ByteData(8 + pcm.length);
  out.setUint32(0, seq, Endian.little);
  out.setUint8(4, kind);
  out.setUint8(5, utteranceEnd ? 1 : 0);
  out.setUint16(6, 0, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(8, 8 + pcm.length, pcm);
  return bytes;
}
