import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/dial_country.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/server_switch.dart';
import 'otp_verify_screen.dart';

class OtpPhoneScreen extends StatefulWidget {
  const OtpPhoneScreen({super.key});

  @override
  State<OtpPhoneScreen> createState() => _OtpPhoneScreenState();
}

class _OtpPhoneScreenState extends State<OtpPhoneScreen> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  DialCountry _country = dialCountries.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
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
    });
    try {
      final auth = context.read<AuthService>();
      final issued = await auth.requestOtp(phoneNumber: national, countryCode: _country.dial);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerifyScreen(
            phone: issued.phone,
            countryCode: _country.dial,
            displayName: _name.text.trim().isEmpty ? issued.phone : _name.text.trim(),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TranslateLanguage', style: TextStyle(letterSpacing: 1.4, color: Colors.white54)),
              const SizedBox(height: 8),
              const Text('Sign in with your number', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('We will text a 6-digit code. It expires in 5 minutes.',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              const ServerSwitch(),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _field(label: 'Your name'),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: DropdownButtonFormField<String>(
                      initialValue: _country.iso,
                      decoration: _field(label: 'Country'),
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
                      decoration: _field(label: 'Phone number', hint: '98765 43210'),
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
                  child: Text(_busy ? 'Sending…' : 'Send OTP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _field({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFF0E1C30),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

String otpErrorText(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'otp_invalid':
        return 'That code is wrong. Try again.';
      case 'otp_expired':
        return 'That code has expired. Request a new one.';
      case 'otp_locked':
        return 'Too many wrong codes. Request a new one.';
      case 'otp_cooldown':
        final wait = error.retryAfterSec;
        return wait == null ? error.message : 'Wait ${wait}s before resending.';
      case 'otp_rate_limited':
        return 'Too many texts to this number. Try again in an hour.';
      case 'sms_unconfigured':
        return 'SMS is not set up on the server yet.';
      case 'invalid_phone':
        return 'Enter a valid phone number.';
      default:
        return error.message;
    }
  }
  return 'Network error. Check the connection and try again.';
}
