import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/dial_country.dart';
import '../services/auth_service.dart';
import 'otp_phone_screen.dart';
import 'otp_verify_screen.dart';

class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _phone = TextEditingController();
  DialCountry _country = dialCountries.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final national = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (national.length < 6) {
      setState(() => _error = 'Enter the new number without the country code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final issued = await context.read<AuthService>().requestOtp(
            phoneNumber: national,
            countryCode: _country.dial,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerifyScreen(
            phone: issued.phone,
            countryCode: _country.dial,
            displayName: '',
            changePhone: true,
            resendAfterSec: issued.retryAfterSec,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = otpErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change number')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We text a code to the new number. Your account stays the same after it is verified.',
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
                    decoration: _field('New phone number'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFE23B4A))),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Sending…' : 'Send code'),
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
