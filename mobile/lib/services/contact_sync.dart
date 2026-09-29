import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';

import '../models/contact.dart';
import 'api_client.dart';

class ContactSync {
  ContactSync(this._api);
  final ApiClient _api;

  Future<List<Contact>> sync() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) return [];
    final locals = await fc.FlutterContacts.getContacts(withProperties: true);
    final numbers = <String>[];
    final byPhone = <String, String>{};
    for (final c in locals) {
      for (final p in c.phones) {
        final n = p.number;
        if (n.trim().length < 8) continue;
        numbers.add(n);
        byPhone[n] = c.displayName;
      }
    }
    if (numbers.isEmpty) return [];
    final json = await _api.post('/v1/contacts/match', {'phones': numbers});
    final matches = (json['matches'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Contact.fromJson(Map<String, dynamic>.from(e)))
        .map((c) {
          String? local;
          final want = _digits(c.phone ?? '');
          for (final e in byPhone.entries) {
            if (_digits(e.key) == want) {
              local = e.value;
              break;
            }
          }
          return c.copyWith(displayName: (local != null && local.isNotEmpty) ? local : c.displayName);
        })
        .toList();
    return matches;
  }

  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');
}
