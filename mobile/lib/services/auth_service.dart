import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'api_client.dart';

class AuthService {
  AuthService(this._api);
  final ApiClient _api;

  String? get accessToken => _api.accessToken;

  static const _tokenKey = 'access_token';
  static const _userKey = 'user_json';

  Future<({String phone, int retryAfterSec})> requestOtp({
    required String phoneNumber,
    String? countryCode,
  }) async {
    final json = await _postWithRetry('/v1/auth/otp/request', {
      'phoneNumber': phoneNumber,
      if (countryCode != null) 'countryCode': countryCode,
    });
    return (
      phone: json['phone'] as String,
      retryAfterSec: (json['retryAfterSec'] as num?)?.toInt() ?? 60,
    );
  }

  Future<AuthUser> verifyOtp({
    required String phone,
    required String code,
    required String displayName,
  }) async {
    final json = await _postWithRetry('/v1/auth/otp/verify', {
      'phoneNumber': phone,
      'code': code,
      'displayName': displayName,
    });
    final token = json['accessToken'] as String;
    final user = AuthUser.fromJson(json['user'] as Map<String, dynamic>);
    _api.accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, user.displayName);
    await prefs.setString('user_id', user.id);
    await prefs.setString('user_phone', user.phone);
    await prefs.setString('user_name', user.displayName);
    return user;
  }

  Future<Map<String, dynamic>> _postWithRetry(String path, Map<String, dynamic> body) async {
    try {
      return await _api.post(path, body);
    } on ApiException {
      rethrow;
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return _api.post(path, body);
    }
  }

  Future<({String token, AuthUser user})?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final id = prefs.getString('user_id');
    final phone = prefs.getString('user_phone');
    final name = prefs.getString('user_name');
    if (token == null || id == null || phone == null) return null;
    _api.accessToken = token;
    return (
      token: token,
      user: AuthUser(id: id, phone: phone, displayName: name ?? phone),
    );
  }

  Future<void> signOut() async {
    _api.accessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove('user_id');
  }
}
