import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/call_session.dart';
import '../models/language.dart';
import '../state/call_controller.dart';
import '../widgets/call_controls.dart';
import '../widgets/language_card.dart';
import '../widgets/transcript_bubble.dart';

class InCallScreen extends StatelessWidget {
  const InCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallController>();
    final session = call.session;
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: Center(child: Text('Call ended')));
    }
    final status = session.phase == CallPhase.ringing
        ? (session.outbound ? 'Ringing…' : 'Incoming call')
        : session.phase == CallPhase.connecting
            ? 'Connecting…'
            : 'Live translator';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) call.hangup();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF173154),
                      child: Text(
                        session.remoteName.isEmpty ? '?' : session.remoteName[0].toUpperCase(),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.remoteName,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            status,
                            style: TextStyle(
                              color: session.outbound == false && session.phase == CallPhase.ringing
                                  ? const Color(0xFF2EE6A6)
                                  : Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'You hear ${languageByCode(session.srcLang).englishName}'
                            '${session.dstLang == session.srcLang ? '' : ' · ${session.remoteName} hears ${languageByCode(session.dstLang).englishName}'}'
                            '${call.lastLatencyLabel == null ? '' : '  ·  ${call.lastLatencyLabel}'}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (session.ducked)
                      const Chip(label: Text('TTS'), visualDensity: VisualDensity.compact),
                  ],
                ),
              ),
              const DualLiveCaptions(),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: TranscriptList(
                  lines: call.transcripts,
                  emptyHint: call.lastError ??
                      (call.sttProvider == 'mock'
                          ? 'Listening…\nSubtitles stay blank until a speech key is set on the server.'
                          : null),
                ),
              ),
              CallControls(
                muted: session.micMuted,
                speakerOn: session.speakerOn,
                onMute: call.toggleMute,
                onSpeaker: call.toggleSpeaker,
                onLanguage: () => _switchLanguage(context),
                onHangup: () async {
                  await call.hangup();
                },
              ),
              if (session.phase == CallPhase.ringing && !session.outbound)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: call.answerIncoming,
                      icon: const Icon(Icons.call),
                      label: const Text('Answer'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DualLiveCaptions extends StatelessWidget {
  const DualLiveCaptions({super.key});

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallController>();
    final live = call.transcripts.where((t) => !t.isFinal);
    final last = live.isEmpty ? (call.transcripts.isEmpty ? null : call.transcripts.last) : live.last;
    final caption = last == null ? '' : subtitleTurn(last);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF12324A), Color(0xFF0E2A22)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE  ·  ORIGINAL  /  TRANSLATED',
            style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          if (caption.isNotEmpty)
            Text(caption, style: const TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

void _switchLanguage(BuildContext context) {
  final call = context.read<CallController>();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => LanguagePickerSheet(
      title: 'Preferred language',
      selected: call.src,
      onPick: call.setPreferred,
    ),
  );
}
