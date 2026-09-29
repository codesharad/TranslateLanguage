import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../models/call_session.dart';
import '../models/contact.dart';
import '../models/language.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/audio_capture.dart';
import '../services/callkit_service.dart';
import '../services/contact_sync.dart';
import '../services/signaling_service.dart';
import '../services/translation_socket.dart';
import '../services/tts_playback.dart';
import '../services/webrtc_service.dart';

class CallController extends ChangeNotifier {
  CallController({required this.app, required this.api});

  final AppConfig app;
  final ApiClient api;
  final callkit = CallKitService();
  final playback = TtsPlaybackService();

  String userId = '';
  String displayName = '';
  String phone = '';
  String? accessToken;
  List<Contact> matched = [];
  String searchQuery = '';
  bool contactsLoading = false;

  /// Language this person hears and reads.
  Language src = languageByCode('ta-IN');

  /// The other person's preferred language. Known once a call is placed.
  Language dst = languageByCode('ta-IN');
  String calleeUserId = 'user-b';
  String keypadBuffer = '';
  List<Contact> online = [];

  CallSession? session;
  final List<TranscriptLine> transcripts = [];
  String? lastLatencyLabel;
  String? lastError;
  String sttProvider = '';
  bool connecting = false;
  bool signalingOk = false;

  SignalingService? _signaling;
  WebrtcCallService? _webrtc;
  TranslationSocket? _media;
  AudioCaptureService? _capture;
  int _ttsGeneration = 0;
  bool _hearingRemote = false;
  String? _pendingRemoteSdp;
  final List<Map<String, dynamic>> _pendingIce = [];
  bool _answering = false;

  Future<void> startSession(AuthUser user, String token) async {
    userId = user.id;
    displayName = user.displayName;
    phone = user.phone;
    accessToken = token;
    api.accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('preferred_lang') ?? prefs.getString('src_lang') ?? user.defaultLang;
    src = languageByCode(saved);
    dst = src;
    await boot();
    await syncContacts();
  }

  Future<void> boot() async {
    await Permission.microphone.request();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final voip = await callkit.voipToken();
        if (accessToken != null) {
          await api.put('/v1/devices', {
            'deviceId': userId,
            'platform': 'ios',
            'voipToken': voip,
            'fcmToken': voip,
          });
        }
      } catch (e) {
        debugPrint('device register $e');
      }
    }

    final previous = _signaling;
    _signaling = null;
    await previous?.dispose();

    _signaling = SignalingService(
      url: app.signalingUrl,
      onMessage: _onSignal,
      onStatus: (ok) {
        signalingOk = ok;
        notifyListeners();
      },
    );
    await _signaling!.connect(
      userId: userId,
      deviceId: userId,
      platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      displayName: displayName,
      accessToken: accessToken,
      pushToken: null,
      language: src.bcp47,
    );
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      callkit.events.listen(_onCallkitEvent);
    }
  }

  Future<void> syncContacts() async {
    contactsLoading = true;
    notifyListeners();
    try {
      final sync = ContactSync(api);
      final book = await sync.sync();
      List<Contact> invited = [];
      try {
        invited = await sync.invites();
      } catch (e) {
        debugPrint('invites $e');
      }
      final merged = <String, Contact>{};
      for (final contact in invited) {
        merged[contact.userId] = contact;
      }
      for (final contact in book) {
        merged[contact.userId] = contact;
      }
      matched = merged.values.toList();
    } catch (e) {
      debugPrint('contacts $e');
    } finally {
      contactsLoading = false;
      notifyListeners();
    }
  }

  void setSearch(String q) {
    searchQuery = q.trim().toLowerCase();
    notifyListeners();
  }

  void setPreferred(Language language) {
    src = language;
    if (session != null) session!.srcLang = language.bcp47;
    notifyListeners();
    _rememberLanguages();
    _signaling?.setPreferredLanguage(callId: session?.callId, hearLang: language.bcp47);
  }

  void _rememberLanguages() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('preferred_lang', src.bcp47);
      prefs.setString('src_lang', src.bcp47);
    });
  }

  List<Contact> get directory {
    final liveIds = {for (final c in online) c.userId};
    final registered = <Contact>[
      ...matched,
      ...online.where((c) => !matched.any((m) => m.userId == c.userId)),
    ];
    final merged = [
      ...registered.map((c) => c.copyWith(online: liveIds.contains(c.userId) || c.online, registered: true)),
    ];
    if (searchQuery.isEmpty) return merged;
    return merged
        .where((c) =>
            c.displayName.toLowerCase().contains(searchQuery) ||
            (c.phone ?? '').contains(searchQuery) ||
            c.userId.toLowerCase().contains(searchQuery))
        .toList();
  }

  void selectContact(Contact contact) {
    calleeUserId = contact.userId;
    keypadBuffer = contact.userId;
    notifyListeners();
  }

  void keypadDigit(String digit) {
    keypadBuffer += digit;
    calleeUserId = keypadBuffer;
    notifyListeners();
  }

  void keypadBackspace() {
    if (keypadBuffer.isEmpty) return;
    keypadBuffer = keypadBuffer.substring(0, keypadBuffer.length - 1);
    calleeUserId = keypadBuffer;
    notifyListeners();
  }

  Future<void> callContact(Contact contact) async {
    selectContact(contact);
    await placeCall();
  }

  Future<void> placeCall() async {
    lastError = null;
    if (!(_signaling?.connected ?? false)) {
      lastError = 'Not connected to server. Keep the app open.';
      notifyListeners();
      return;
    }
    connecting = true;
    final peerLang = _languageFor(calleeUserId);
    if (peerLang != null) dst = peerLang;
    session = CallSession(
      callId: '',
      localUserId: userId,
      remoteUserId: calleeUserId,
      remoteName: _displayNameFor(calleeUserId),
      srcLang: src.bcp47,
      dstLang: dst.bcp47,
      outbound: true,
    );
    session!.phase = CallPhase.ringing;
    notifyListeners();
    _signaling?.dialUser(to: calleeUserId, hearLang: src.bcp47);
  }

  void updateAccount(AuthUser user, String token) {
    phone = user.phone;
    displayName = user.displayName;
    accessToken = token;
    api.accessToken = token;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (session != null) await hangup();
    final previous = _signaling;
    _signaling = null;
    await previous?.dispose();
    userId = '';
    displayName = '';
    phone = '';
    accessToken = null;
    matched = [];
    online = [];
    notifyListeners();
  }

  Future<void> hangup({bool notifyPeer = true}) async {
    final id = session?.callId;
    if (notifyPeer && id != null && id.isNotEmpty) {
      _signaling?.hangup(id);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          await callkit.end(id);
        } catch (e) {
          debugPrint('callkit end $e');
        }
      }
    }
    await _teardown();
  }

  Future<void> toggleMute() async {
    if (session == null) return;
    session!.micMuted = !session!.micMuted;
    _syncMicGate();
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    if (session == null) return;
    session!.speakerOn = !session!.speakerOn;
    await _webrtc?.setSpeaker(session!.speakerOn);
    await playback.setSpeaker(session!.speakerOn);
    notifyListeners();
  }

  void _onSignal(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'register':
      case 'auth':
        signalingOk = true;
        notifyListeners();
        if (type == 'register' || type == 'presence.sync') {
          _applyPresence(msg['payload']?['users']);
        }
        break;
      case 'presence.sync':
        _applyPresence(msg['payload']?['users']);
        break;
      case 'error':
        final message = msg['payload']?['message']?.toString() ?? 'Call failed';
        debugPrint('signaling error $message');
        lastError = message;
        connecting = false;
        if (session != null &&
            (session!.callId.isEmpty || session!.phase == CallPhase.ringing)) {
          unawaited(_teardown());
        } else {
          notifyListeners();
        }
        break;
      case 'dial-user':
      case 'call.invite':
        if (msg['payload']?['ringing'] == true) {
          final payload = msg['payload'];
          final calleeHear = msg['calleeHear'] as String? ??
              (payload is Map ? payload['calleeHear'] as String? : null);
          _applyPeerLanguage(calleeHear);
          final callId = msg['callId'] as String;
          _beginOutgoing(callId);
        } else {
          _onIncoming(msg);
        }
        break;
      case 'incoming-call':
        _onIncoming(msg);
        break;
      case 'accept-call':
      case 'call.accept':
        _onAccepted(msg['callId'] as String);
        break;
      case 'end-call':
      case 'reject-call':
      case 'call.hangup':
      case 'call.reject':
        hangup(notifyPeer: false);
        break;
      case 'webrtc.offer':
        _pendingRemoteSdp = msg['sdp'] as String?;
        unawaited(_flushRemoteSignal());
        break;
      case 'webrtc.answer':
        _webrtc?.acceptAnswer(msg['sdp'] as String);
        break;
      case 'webrtc.ice':
        final c = Map<String, dynamic>.from(msg['candidate'] as Map);
        if (_webrtc != null) {
          _webrtc!.addIce(c);
        } else {
          _pendingIce.add(c);
        }
        break;
      case 'languages.set':
        final from = msg['from'] as String?;
        if (from != null && from != userId) {
          _applyPeerLanguage(msg['hearLang'] as String? ?? msg['srcLang'] as String?);
        }
        break;
    }
  }

  void _applyPresence(dynamic raw) {
    if (raw is! List) return;
    online = raw
        .whereType<Map>()
        .map((e) => Contact.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.userId != userId)
        .toList();
    notifyListeners();
  }

  Future<void> _beginOutgoing(String callId) async {
    session ??= CallSession(
      callId: callId,
      localUserId: userId,
      remoteUserId: calleeUserId,
      remoteName: _displayNameFor(calleeUserId),
      srcLang: src.bcp47,
      dstLang: dst.bcp47,
      outbound: true,
    );
    session!.callId = callId;
    session!.phase = CallPhase.ringing;
    _signaling?.setPreferredLanguage(callId: callId, hearLang: src.bcp47);
    lastError = null;
    notifyListeners();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await callkit.startOutgoing(
          callId: callId,
          calleeName: _displayNameFor(calleeUserId),
          handle: calleeUserId,
        );
      } catch (e) {
        debugPrint('callkit outgoing $e');
      }
    }
    try {
      await _startMedia(asOfferer: true);
    } catch (e, st) {
      debugPrint('startMedia $e\n$st');
      connecting = false;
      notifyListeners();
    }
  }

  Language? _languageFor(String userId) {
    for (final contact in [...online, ...matched]) {
      if (contact.userId == userId && (contact.language ?? '').isNotEmpty) {
        return languageByCode(contact.language!);
      }
    }
    return null;
  }

  void _applyPeerLanguage(String? code) {
    if (code == null || code.isEmpty) return;
    dst = languageByCode(code);
    if (session != null) session!.dstLang = dst.bcp47;
    _media?.setTargetLanguage(dstLang: dst.bcp47, voice: dst.azureVoice);
    notifyListeners();
  }

  Future<void> _onIncoming(Map<String, dynamic> msg) async {
    final callId = msg['callId'] as String;
    final from = msg['from'] as String;
    final rawPayload = msg['payload'];
    final payload = rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : null;
    final name = payload?['callerName'] as String? ?? from;
    final callerHear = (msg['callerHear'] ?? payload?['callerHear'] ?? msg['srcLang']) as String?;
    session = CallSession(
      callId: callId,
      localUserId: userId,
      remoteUserId: from,
      remoteName: name,
      srcLang: src.bcp47,
      dstLang: callerHear ?? dst.bcp47,
      outbound: false,
    );
    dst = languageByCode(session!.dstLang);
    session!.phase = CallPhase.ringing;
    lastError = null;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await callkit.showIncoming(callId: callId, callerName: name, handle: from);
      } catch (e) {
        debugPrint('callkit incoming $e');
      }
    }
    notifyListeners();
  }

  Future<void> _onCallkitEvent(dynamic event) async {
    final type = event?.event;
    if (type.toString().contains('ACTION_CALL_ACCEPT')) {
      final callId = session?.callId;
      if (callId != null) {
        _signaling?.accept(callId);
        await _startMedia(asOfferer: false);
      }
    } else if (type.toString().contains('ACTION_CALL_DECLINE')) {
      await hangup();
    }
    // Ignore ACTION_CALL_ENDED on Android: ConnectionService fires it
    // immediately and was tearing down live calls.
  }

  Future<void> answerIncoming() async {
    final callId = session?.callId;
    if (callId == null || callId.isEmpty || _answering) return;
    _answering = true;
    session?.phase = CallPhase.connecting;
    notifyListeners();
    _signaling?.accept(callId);
    try {
      await _startMedia(asOfferer: false);
    } catch (e, st) {
      debugPrint('answerIncoming $e\n$st');
      lastError = 'Could not start call audio';
      notifyListeners();
    } finally {
      _answering = false;
    }
  }

  Future<void> _onAccepted(String callId) async {
    session?.phase = CallPhase.active;
    notifyListeners();
  }

  Future<void> _startMedia({required bool asOfferer}) async {
    await WakelockPlus.enable();
    try {
      _webrtc = WebrtcCallService(
        onIce: (c) {
          _signaling?.sendIce(session!.callId, {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          });
        },
        onRemoteStream: (_) {},
      );
      await _webrtc!.start(asOfferer: asOfferer, captureMic: false);
      await _webrtc!.setSpeaker(true);
      if (asOfferer) {
        final offer = await _webrtc!.createOffer();
        _signaling?.sendOffer(session!.callId, offer.sdp ?? '');
      } else {
        await _flushRemoteSignal();
      }
    } catch (e) {
      debugPrint('webrtc $e');
    }
    _media = TranslationSocket(
      url: app.orchestratorUrl,
      onEvent: _onMediaEvent,
    );
    await _media!.connect(
      callId: session!.callId,
      peerId: userId,
      hearLang: session!.srcLang,
      dstLang: session!.dstLang,
      voice: languageByCode(session!.dstLang).azureVoice,
    );
    try {
      await playback.start();
      playback.onPlayback = (playing) {
        _hearingRemote = playing;
        _syncMicGate();
      };
      await playback.setSpeaker(session?.speakerOn ?? true);
    } catch (e) {
      debugPrint('tts playback $e');
    }
    _capture = AudioCaptureService(onFrame: (pcm) => _media?.sendPcm(pcm));
    await _capture!.start();
    session?.phase = CallPhase.active;
    connecting = false;
    notifyListeners();
  }

  Future<void> _flushRemoteSignal() async {
    if (_webrtc == null || _pendingRemoteSdp == null || session == null) return;
    final sdp = _pendingRemoteSdp!;
    _pendingRemoteSdp = null;
    final answer = await _webrtc!.createAnswer(sdp);
    _signaling?.sendAnswer(session!.callId, answer.sdp ?? '');
    for (final c in _pendingIce) {
      await _webrtc!.addIce(c);
    }
    _pendingIce.clear();
  }

  void _onMediaEvent(MediaEvent event) {
    if (event.bytes != null) {
      final pcm = event.bytes!;
      if (pcm.length > 8) {
        playback.enqueue(Uint8List.sublistView(pcm, 8), generation: _ttsGeneration);
      }
      return;
    }
    switch (event.type) {
      case 'session.ready':
        sttProvider = event.json['provider'] as String? ?? '';
        debugPrint('subtitle session provider=$sttProvider');
        notifyListeners();
        break;
      case 'subtitle_local':
      case 'subtitle_remote':
        debugPrint(
          'subtitle ${event.type} lang=${event.json['language']} '
          'final=${event.json['is_final']} text=${event.json['text']}',
        );
        _upsertSubtitle(event.type, event.json);
        break;
      case 'transcript.partial':
      case 'transcript.final':
        debugPrint('subtitle legacy ${event.type} ${event.json['source_text']}');
        _upsertTranscript(event.json);
        break;
      case 'audio.duck':
        session?.ducked = event.json['duck'] == true;
        _syncMicGate();
        break;
      case 'tts.cancel':
        _ttsGeneration = (event.json['generation'] as int?) ?? _ttsGeneration + 1;
        playback.cancel(generation: _ttsGeneration);
        break;
      case 'languages.set':
        final dstCode = event.json['dst_lang'] as String?;
        if (dstCode != null && dstCode.isNotEmpty && dstCode != 'auto') {
          dst = languageByCode(dstCode);
          session?.dstLang = dst.bcp47;
          notifyListeners();
        }
        break;
      case 'error':
        final raw = event.json['message']?.toString() ?? 'Speech recognition failed';
        lastError = raw.replaceFirst(RegExp(r'^\[stt-error\]\s*'), '');
        debugPrint('subtitle error $lastError');
        notifyListeners();
        break;
      case 'latency':
        final stages = Map<String, dynamic>.from(event.json['stages_ms'] as Map? ?? {});
        final e2e = stages['e2e_server_ms'];
        if (e2e != null) lastLatencyLabel = 'server ${e2e}ms';
        notifyListeners();
        break;
    }
  }

  void _upsertSubtitle(String type, Map<String, dynamic> json) {
    final text = (json['text'] as String? ?? '').trim();
    if (text.isEmpty) return;
    final bcp = (json['bcp47'] as String?) ?? _bcp47(json['language'] as String?);
    final id = json['utterance_id'] as String? ?? '';
    final line = TranscriptLine(
      utteranceId: id.isEmpty ? '${type}_${transcripts.length}' : '$type:$id',
      fromPeer: type == 'subtitle_remote',
      sourceText: text,
      translatedText: '',
      srcLang: bcp,
      dstLang: bcp,
      isFinal: json['is_final'] == true,
    );
    final idx = transcripts.indexWhere((t) => t.utteranceId == line.utteranceId);
    if (idx >= 0) {
      transcripts[idx] = line;
    } else {
      transcripts.add(line);
      if (transcripts.length > 80) transcripts.removeAt(0);
    }
    notifyListeners();
  }

  String _bcp47(String? language) {
    final code = (language ?? '').toLowerCase();
    if (code.isEmpty) return src.bcp47;
    for (final item in supportedLanguages) {
      if (item.bcp47.toLowerCase() == code || item.iso == code) return item.bcp47;
    }
    return src.bcp47;
  }

  void _upsertTranscript(Map<String, dynamic> json) {
    final id = json['utterance_id'] as String? ?? '';
    final fromPeer = json['call_id'] != null &&
        (json['src_lang'] as String?) != session?.srcLang;
    final line = TranscriptLine(
      utteranceId: id,
      fromPeer: fromPeer,
      sourceText: json['source_text'] as String? ?? '',
      translatedText: json['translated_text'] as String? ?? '',
      srcLang: json['src_lang'] as String? ?? '',
      dstLang: json['dst_lang'] as String? ?? '',
      isFinal: json['is_final'] == true,
      latencyMs: (json['t_ms'] as Map?)?['e2e_server_ms'] as int?,
    );
    final idx = transcripts.indexWhere((t) => t.utteranceId == id && id.isNotEmpty);
    if (idx >= 0) {
      transcripts[idx] = line;
    } else {
      transcripts.add(line);
      if (transcripts.length > 80) transcripts.removeAt(0);
    }
    notifyListeners();
  }

  Future<void> _teardown() async {
    await _capture?.stop();
    await playback.stop();
    await _media?.close();
    await _webrtc?.hangup();
    await WakelockPlus.disable();
    _capture = null;
    _media = null;
    _webrtc = null;
    session?.phase = CallPhase.ended;
    session = null;
    transcripts.clear();
    connecting = false;
    _answering = false;
    _pendingRemoteSdp = null;
    _pendingIce.clear();
    _hearingRemote = false;
    notifyListeners();
  }

  void _syncMicGate() {
    _capture?.setDucked(
      session?.micMuted == true || session?.ducked == true || _hearingRemote,
    );
  }

  @override
  void dispose() {
    unawaited(_signaling?.dispose());
    super.dispose();
  }

  String _displayNameFor(String userId) {
    for (final c in directory) {
      if (c.userId == userId) return c.displayName;
    }
    return userId;
  }
}
