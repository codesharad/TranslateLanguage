import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../state/call_controller.dart';
import 'otp_phone_screen.dart';

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({
    super.key,
    required this.phone,
    required this.displayName,
    required this.countryCode,
    this.resendAfterSec = 60,
  });

  final String phone;
  final String displayName;
  final String countryCode;
  final int resendAfterSec;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _code = TextEditingController();
  Timer? _ticker;
  bool _busy = false;
  String? _error;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = widget.resendAfterSec.clamp(0, 60);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _seconds <= 0) return;
      setState(() => _seconds -= 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the 6-digit code from the SMS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final call = context.read<CallController>();
      final user = await auth.verifyOtp(
        phone: widget.phone,
        code: code,
        displayName: widget.displayName,
      );
      await call.startSession(user, auth.accessToken!);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() => _error = otpErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_seconds > 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final issued = await auth.requestOtp(phoneNumber: widget.phone, countryCode: widget.countryCode);
      if (!mounted) return;
      setState(() => _seconds = issued.retryAfterSec.clamp(0, 60));
    } catch (e) {
      if (!mounted) return;
      final wait = e is ApiException ? e.retryAfterSec : null;
      setState(() {
        _error = otpErrorText(e);
        if (wait != null) _seconds = wait.clamp(0, 60);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _seconds > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code sent to ${widget.phone}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            const Text('The code expires in 5 minutes.', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '6-digit code',
                filled: true,
                fillColor: const Color(0xFF0E1C30),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => _busy ? null : _verify(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFE23B4A))),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: waiting || _busy ? null : _resend,
              child: Text(waiting ? 'Resend OTP in ${_seconds}s' : 'Resend OTP'),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _verify,
                child: Text(_busy ? 'Please wait…' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
