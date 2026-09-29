enum CallPhase { idle, ringing, connecting, active, ended }

class TranscriptLine {
  TranscriptLine({
    required this.utteranceId,
    required this.fromPeer,
    required this.sourceText,
    required this.translatedText,
    required this.srcLang,
    required this.dstLang,
    required this.isFinal,
    this.latencyMs,
  });

  final String utteranceId;
  final bool fromPeer;
  final String sourceText;
  final String translatedText;
  final String srcLang;
  final String dstLang;
  final bool isFinal;
  final int? latencyMs;

  TranscriptLine copyWith({
    String? sourceText,
    String? translatedText,
    bool? isFinal,
    int? latencyMs,
  }) {
    return TranscriptLine(
      utteranceId: utteranceId,
      fromPeer: fromPeer,
      sourceText: sourceText ?? this.sourceText,
      translatedText: translatedText ?? this.translatedText,
      srcLang: srcLang,
      dstLang: dstLang,
      isFinal: isFinal ?? this.isFinal,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}

class CallSession {
  CallSession({
    required this.callId,
    required this.localUserId,
    required this.remoteUserId,
    required this.remoteName,
    required this.srcLang,
    required this.dstLang,
    required this.outbound,
  });

  String callId;
  final String localUserId;
  final String remoteUserId;
  final String remoteName;
  String srcLang;
  String dstLang;
  final bool outbound;
  CallPhase phase = CallPhase.connecting;
  bool micMuted = false;
  bool speakerOn = true;
  bool ducked = false;
}
