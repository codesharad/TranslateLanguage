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
  // The controller mutates one list in place, so the old widget's list always looks the
  // same as the new one. Compare against what was last seen here instead.
  int _seenCount = 0;
  String _seenLastText = '';
  bool _seenLastFinal = true;

  @override
  void initState() {
    super.initState();
    _remember();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd(animate: false));
  }

  void _remember() {
    final lines = widget.lines;
    _seenCount = lines.length;
    _seenLastText = lines.isEmpty ? '' : lines.last.sourceText;
    _seenLastFinal = lines.isEmpty ? true : lines.last.isFinal;
  }

  @override
  void didUpdateWidget(TranscriptList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lines = widget.lines;
    final changed = lines.length != _seenCount ||
        (lines.isNotEmpty &&
            (lines.last.sourceText != _seenLastText || lines.last.isFinal != _seenLastFinal));
    _remember();
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if (!animate) {
      _scroll.jumpTo(end);
      return;
    }
    _scroll.animateTo(
      end,
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
