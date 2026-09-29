import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/contact.dart';
import '../state/call_controller.dart';
import '../widgets/language_card.dart';
import '../widgets/server_switch.dart';
import 'call_setup_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ServerSwitch(),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: const [
                  _ContactsTab(),
                  _KeypadTab(),
                  _LanguagesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.dialpad), label: 'Keypad'),
          NavigationDestination(icon: Icon(Icons.translate), label: 'Languages'),
        ],
      ),
    );
  }
}

class _ContactsTab extends StatelessWidget {
  const _ContactsTab();

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TranslateLanguage', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white54, letterSpacing: 1.3)),
          const SizedBox(height: 4),
          const Text('App-to-app translator', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('You speak ${call.src.englishName}  →  they hear ${call.dst.englishName}',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            call.signalingOk ? 'Online · server connected' : 'Connecting to server… keep the app open',
            style: TextStyle(
              color: call.signalingOk ? const Color(0xFF2EE6A6) : const Color(0xFFE6B62E),
              fontSize: 13,
            ),
          ),
          if (call.lastError != null) ...[
            const SizedBox(height: 6),
            Text(call.lastError!, style: const TextStyle(color: Color(0xFFE23B4A), fontSize: 13)),
          ],
          const SizedBox(height: 12),
          TextField(
            onChanged: call.setSearch,
            decoration: InputDecoration(
              hintText: 'Search contacts',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFF0E1C30),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (call.contactsLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: call.directory.isEmpty
                ? const Center(child: Text('No registered contacts yet.\nInvite someone to join with their phone number.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)))
                : ListView.separated(
              itemCount: call.directory.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = call.directory[i];
                return _ContactTile(contact: c);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final call = context.read<CallController>();
    return ListTile(
      onTap: () => showCallSetupSheet(context, contact),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: const Color(0xFF0E1C30),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF173154),
        child: Text(contact.initial),
      ),
      title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(contact.phone ?? contact.userId),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contact.online)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.circle, size: 10, color: Color(0xFF2EE6A6)),
            ),
          IconButton.filledTonal(
            onPressed: () => showCallSetupSheet(context, contact),
            icon: const Icon(Icons.call),
          ),
        ],
      ),
    );
  }
}

class _KeypadTab extends StatelessWidget {
  const _KeypadTab();

  static const keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallController>();
    return Column(
      children: [
        const SizedBox(height: 32),
        Text(
          call.keypadBuffer.isEmpty ? 'Enter user id' : call.keypadBuffer,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: 1.4),
        ),
        const Spacer(),
        for (final row in keys)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final d in row)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => call.keypadDigit(d),
                    child: Ink(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF173154)),
                      child: Center(child: Text(d, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(onPressed: call.keypadBackspace, icon: const Icon(Icons.backspace_outlined)),
            FilledButton.icon(
              onPressed: call.connecting || call.keypadBuffer.isEmpty ? null : call.placeCall,
              icon: const Icon(Icons.call),
              label: const Text('Call'),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LanguagesTab extends StatelessWidget {
  const _LanguagesTab();

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Call setup', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Pick what you speak and what the other person should hear. You can switch again during the call.',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
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
        ],
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
