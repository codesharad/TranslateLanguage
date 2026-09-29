import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// CallKit (iOS) + ConnectionService (Android).
/// VoIP / FCM payloads must call [showIncoming] within ~2s.
class CallKitService {
  Future<String?> voipToken() async {
    try {
      return await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    } catch (_) {
      return null;
    }
  }

  Future<void> showIncoming({
    required String callId,
    required String callerName,
    required String handle,
    Map<String, dynamic>? extra,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'TranslateLanguage',
      handle: handle,
      type: 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: {'callId': callId, ...?extra},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        incomingCallNotificationChannelName: 'Incoming Translator Call',
        missedCallNotificationChannelName: 'Missed Translator Call',
        isShowCallID: false,
        isShowFullLockedScreen: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0B1F3A',
        actionColor: '#2EE6A6',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 16000,
        audioSessionPreferredIOBufferDuration: 0.02,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> startOutgoing({
    required String callId,
    required String calleeName,
    required String handle,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: calleeName,
      handle: handle,
      type: 0,
      extra: {'callId': callId},
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: false,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 16000,
      ),
    );
    await FlutterCallkitIncoming.startCall(params);
  }

  Future<void> setConnected(String callId) async {
    await FlutterCallkitIncoming.setCallConnected(callId);
  }

  Future<void> end(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  Stream<CallEvent?> get events => FlutterCallkitIncoming.onEvent;
}
