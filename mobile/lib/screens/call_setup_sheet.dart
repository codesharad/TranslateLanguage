import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contact.dart';
import '../state/call_controller.dart';
import '../widgets/language_card.dart';

Future<void> showCallSetupSheet(BuildContext context, Contact contact) async {
  final call = context.read<CallController>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0E1C30),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Consumer<CallController>(
          builder: (_, call, __) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99))),
                ),
                const SizedBox(height: 16),
                Text('Call ${contact.displayName}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                Text(contact.phone ?? contact.userId, style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 16),
                const Text(
                  'You will hear them in your preferred language.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                LanguageCard(
                  label: 'PREFERRED LANGUAGE',
                  language: call.src,
                  onTap: () => _pick(ctx),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: call.connecting
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await call.callContact(contact);
                          },
                    icon: const Icon(Icons.call),
                    label: Text(call.connecting ? 'Calling…' : 'Call'),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

void _pick(BuildContext context) {
  final call = context.read<CallController>();
  showModalBottomSheet(
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
