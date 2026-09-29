import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/dial_country.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../state/call_controller.dart';
import 'otp_phone_screen.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _phone = TextEditingController();
  DialCountry _country = dialCountries.first;
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final national = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (national.length < 6) {
      setState(() => _error = 'Enter the phone number without the country code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      final json = await context.read<AuthService>().invite(
            phoneNumber: national,
            countryCode: _country.dial,
          );
      if (!mounted) return;
      final phone = json['phone'] as String? ?? json['contact']?['phone'] as String? ?? national;
      final already = json['status'] == 'already_registered';
      setState(() {
        _done = already
            ? '$phone is already on TranslateLanguage and was added to your contacts.'
            : 'Invite saved for $phone. They will show up here after they register.';
        _phone.clear();
      });
      await context.read<CallController>().syncContacts();
    } catch (e) {
      setState(() => _error = e is ApiException ? otpErrorText(e) : 'Could not send the invite.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter their mobile number. If they already have an account, they are added to your contacts. Otherwise they appear after they register.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 118,
                  child: DropdownButtonFormField<String>(
                    initialValue: _country.iso,
                    decoration: _field('Country'),
                    dropdownColor: const Color(0xFF0E1C30),
                    items: [
                      for (final country in dialCountries)
                        DropdownMenuItem(value: country.iso, child: Text(country.label)),
                    ],
                    onChanged: _busy
                        ? null
                        : (iso) {
                            if (iso == null) return;
                            setState(() => _country = dialCountryByIso(iso));
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                    decoration: _field('Their phone number'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFE23B4A))),
            ],
            if (_done != null) ...[
              const SizedBox(height: 12),
              Text(_done!, style: const TextStyle(color: Color(0xFF2EE6A6))),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.person_add_alt),
                label: Text(_busy ? 'Saving…' : 'Invite'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _field(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFF0E1C30),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}
