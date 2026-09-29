class AuthUser {
  const AuthUser({
    required this.id,
    required this.phone,
    required this.displayName,
    this.defaultLang = 'ta-IN',
  });

  final String id;
  final String phone;
  final String displayName;
  final String defaultLang;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      phone: json['phone'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['display_name'] as String? ?? '',
      defaultLang: json['defaultLang'] as String? ?? json['default_lang'] as String? ?? 'ta-IN',
    );
  }
}
