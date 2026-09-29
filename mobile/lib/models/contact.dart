class Contact {
  const Contact({
    required this.userId,
    required this.displayName,
    this.phone,
    this.language,
    this.online = false,
    this.registered = false,
  });

  final String userId;
  final String displayName;
  final String? phone;
  final String? language;
  final bool online;
  final bool registered;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['userId'] as String? ?? '',
      phone: json['phone'] as String?,
      language: json['language'] as String?,
      online: json['online'] as bool? ?? true,
      registered: json['registered'] as bool? ?? true,
    );
  }

  Contact copyWith({bool? online, bool? registered, String? displayName}) {
    return Contact(
      userId: userId,
      displayName: displayName ?? this.displayName,
      phone: phone,
      language: language,
      online: online ?? this.online,
      registered: registered ?? this.registered,
    );
  }

  String get initial => displayName.isEmpty ? '?' : displayName[0].toUpperCase();
}

const demoDirectory = <Contact>[
  Contact(userId: 'user-a', displayName: 'Anand', language: 'ta-IN', phone: '+910000000001'),
  Contact(userId: 'user-b', displayName: 'Priya', language: 'hi-IN', phone: '+910000000002'),
];
