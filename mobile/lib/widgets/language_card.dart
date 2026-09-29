import 'package:flutter/material.dart';

import '../models/language.dart';

class LanguagePickerSheet extends StatelessWidget {
  const LanguagePickerSheet({
    super.key,
    required this.title,
    required this.selected,
    required this.exclude,
    required this.onPick,
  });

  final String title;
  final Language selected;
  final Language exclude;
  final ValueChanged<Language> onPick;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0E1C30),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: supportedLanguages.length,
                  itemBuilder: (context, i) {
                    final lang = supportedLanguages[i];
                    final disabled = lang.bcp47 == exclude.bcp47;
                    final active = lang.bcp47 == selected.bcp47;
                    return ListTile(
                      enabled: !disabled,
                      leading: Text(lang.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(lang.englishName),
                      subtitle: Text(lang.nativeName),
                      trailing: active
                          ? const Icon(Icons.check_circle, color: Color(0xFF2EE6A6))
                          : null,
                      onTap: disabled
                          ? null
                          : () {
                              onPick(lang);
                              Navigator.pop(context);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageCard extends StatelessWidget {
  const LanguageCard({
    super.key,
    required this.label,
    required this.language,
    required this.onTap,
  });

  final String label;
  final Language language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1C30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 10),
            Text(language.flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(language.englishName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(language.nativeName, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
