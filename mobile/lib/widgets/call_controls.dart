import 'package:flutter/material.dart';

class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.muted,
    required this.speakerOn,
    required this.onMute,
    required this.onSpeaker,
    required this.onLanguage,
    required this.onHangup,
  });

  final bool muted;
  final bool speakerOn;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onLanguage;
  final VoidCallback onHangup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Btn(icon: muted ? Icons.mic_off : Icons.mic, label: muted ? 'Unmute' : 'Mute', onTap: onMute),
          _Btn(
            icon: speakerOn ? Icons.volume_up : Icons.hearing,
            label: speakerOn ? 'Speaker' : 'Earpiece',
            onTap: onSpeaker,
          ),
          _Btn(icon: Icons.translate, label: 'Language', onTap: onLanguage),
          _Btn(
            icon: Icons.call_end,
            label: 'End',
            color: const Color(0xFFE23B4A),
            large: true,
            onTap: onHangup,
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 68.0 : 54.0;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color ?? const Color(0xFF173154),
            ),
            child: Icon(icon, color: Colors.white, size: large ? 30 : 22),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }
}
