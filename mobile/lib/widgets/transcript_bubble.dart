import 'package:flutter/material.dart';

import '../models/call_session.dart';
import '../models/language.dart';

String subtitleTurn(TranscriptLine line) {
  final who = line.fromPeer ? 'Caller' : 'You';
  final name = languageByCode(line.srcLang).englishName;
  return '$who ($name): ${line.sourceText}';
}

class TranscriptList extends StatefulWidget {
  const TranscriptList({super.key, required this.lines, this.emptyHint});

  final List<TranscriptLine> lines;
  final String? emptyHint;

  @override
  State<TranscriptList> createState() => _TranscriptListState();
}

class _TranscriptListState extends State<TranscriptList> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(TranscriptList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final grew = widget.lines.length != oldWidget.lines.length;
    final edited = widget.lines.isNotEmpty &&
        oldWidget.lines.isNotEmpty &&
        widget.lines.last.sourceText != oldWidget.lines.last.sourceText;
    if (grew || edited) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return Center(
        child: Text(
          widget.emptyHint ?? 'Listening…\nSubtitles appear here as you speak.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: widget.lines.length,
      itemBuilder: (context, i) => TranscriptBubble(line: widget.lines[i]),
    );
  }
}

class TranscriptBubble extends StatelessWidget {
  const TranscriptBubble({super.key, required this.line});

  final TranscriptLine line;

  @override
  Widget build(BuildContext context) {
    final align = line.fromPeer ? Alignment.centerLeft : Alignment.centerRight;
    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: line.fromPeer ? const Color(0xFF132844) : const Color(0xFF0F3D32),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: line.isFinal ? Colors.transparent : const Color(0xFF2EE6A6),
          ),
        ),
        child: Text(
          subtitleTurn(line),
          style: TextStyle(
            fontSize: 16,
            height: 1.35,
            fontStyle: line.isFinal ? FontStyle.normal : FontStyle.italic,
            color: Colors.white.withValues(alpha: line.isFinal ? 1 : 0.85),
          ),
        ),
      ),
    );
  }
}
