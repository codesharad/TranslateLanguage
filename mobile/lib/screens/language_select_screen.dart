import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/call_session.dart';
import '../state/call_controller.dart';
import '../widgets/language_card.dart';
import 'in_call_screen.dart';

class LanguageSelectScreen extends StatefulWidget {
  const LanguageSelectScreen({super.key});

  @override
  State<LanguageSelectScreen> createState() => _LanguageSelectScreenState();
}

class _LanguageSelectScreenState extends State<LanguageSelectScreen> {
  final _callee = TextEditingController(text: 'user-b');
  bool _pushedCall = false;
  CallController? _call;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _call = context.read<CallController>();
      _call?.addListener(_onCallChanged);
    });
  }

  void _onCallChanged() {
    if (!mounted) return;
    final phase = _call?.session?.phase;
    final inCall = phase == CallPhase.ringing ||
        phase == CallPhase.connecting ||
        phase == CallPhase.active;
    if (inCall && !_pushedCall) {
      _pushedCall = true;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const InCallScreen()),
      ).then((_) {
        _pushedCall = false;
      });
    }
  }

  @override
  void dispose() {
    _call?.removeListener(_onCallChanged);
    _callee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallController>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TranslateLanguage',
                style: TextStyle(fontSize: 13, letterSpacing: 1.4, color: Colors.white54),
              ),
              const SizedBox(height: 6),
              const Text('Live call translator', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'You speak ${call.src.englishName}. They hear ${call.dst.englishName}.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: LanguageCard(
                      label: 'I SPEAK',
                      language: call.src,
                      onTap: () => _pick(context, isSource: true),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: IconButton.filledTonal(
                      onPressed: call.swapLanguages,
                      icon: const Icon(Icons.swap_horiz),
                    ),
                  ),
                  Expanded(
                    child: LanguageCard(
                      label: 'THEY HEAR',
                      language: call.dst,
                      onTap: () => _pick(context, isSource: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _callee,
                decoration: InputDecoration(
                  labelText: 'Callee user id',
                  filled: true,
                  fillColor: const Color(0xFF0E1C30),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onChanged: (v) => call.calleeUserId = v.trim(),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: call.connecting ? null : () => call.placeCall(),
                  icon: const Icon(Icons.call),
                  label: Text(call.connecting ? 'Calling…' : 'Start translated call'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pick(BuildContext context, {required bool isSource}) {
    final call = context.read<CallController>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LanguagePickerSheet(
        title: isSource ? 'I speak' : 'They hear',
        selected: isSource ? call.src : call.dst,
        exclude: isSource ? call.dst : call.src,
        onPick: isSource ? call.setSource : call.setTarget,
      ),
    );
  }
}
