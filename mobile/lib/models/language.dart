class Language {
  const Language({
    required this.bcp47,
    required this.englishName,
    required this.nativeName,
    required this.flag,
    this.azureVoice,
  });

  final String bcp47;
  final String englishName;
  final String nativeName;
  final String flag;
  final String? azureVoice;

  String get iso => bcp47.split('-').first;
}

/// Keep voices aligned with backend/orchestrator/app/languages.py.
const supportedLanguages = <Language>[
  Language(
    bcp47: 'hi-IN',
    englishName: 'Hindi',
    nativeName: 'हिन्दी',
    flag: '🇮🇳',
    azureVoice: 'hi-IN-SwaraNeural',
  ),
  Language(
    bcp47: 'ta-IN',
    englishName: 'Tamil',
    nativeName: 'தமிழ்',
    flag: '🇮🇳',
    azureVoice: 'ta-IN-PallaviNeural',
  ),
  Language(
    bcp47: 'te-IN',
    englishName: 'Telugu',
    nativeName: 'తెలుగు',
    flag: '🇮🇳',
    azureVoice: 'te-IN-ShrutiNeural',
  ),
  Language(
    bcp47: 'ml-IN',
    englishName: 'Malayalam',
    nativeName: 'മലയാളം',
    flag: '🇮🇳',
    azureVoice: 'ml-IN-SobhanaNeural',
  ),
  Language(
    bcp47: 'gu-IN',
    englishName: 'Gujarati',
    nativeName: 'ગુજરાતી',
    flag: '🇮🇳',
    azureVoice: 'gu-IN-DhwaniNeural',
  ),
  Language(
    bcp47: 'mr-IN',
    englishName: 'Marathi',
    nativeName: 'मराठी',
    flag: '🇮🇳',
    azureVoice: 'mr-IN-AarohiNeural',
  ),
  Language(
    bcp47: 'bn-IN',
    englishName: 'Bengali',
    nativeName: 'বাংলা',
    flag: '🇮🇳',
    azureVoice: 'bn-IN-TanishaaNeural',
  ),
  Language(
    bcp47: 'en-IN',
    englishName: 'English (India)',
    nativeName: 'English',
    flag: '🇮🇳',
    azureVoice: 'en-IN-NeerjaNeural',
  ),
  Language(
    bcp47: 'de-DE',
    englishName: 'German',
    nativeName: 'Deutsch',
    flag: '🇩🇪',
    azureVoice: 'de-DE-KatjaNeural',
  ),
  Language(
    bcp47: 'zh-CN',
    englishName: 'Chinese Mandarin',
    nativeName: '中文',
    flag: '🇨🇳',
    azureVoice: 'zh-CN-XiaoxiaoNeural',
  ),
  Language(
    bcp47: 'fr-FR',
    englishName: 'French',
    nativeName: 'Français',
    flag: '🇫🇷',
    azureVoice: 'fr-FR-DeniseNeural',
  ),
  Language(
    bcp47: 'es-ES',
    englishName: 'Spanish',
    nativeName: 'Español',
    flag: '🇪🇸',
    azureVoice: 'es-ES-ElviraNeural',
  ),
  Language(
    bcp47: 'nl-NL',
    englishName: 'Dutch',
    nativeName: 'Nederlands',
    flag: '🇳🇱',
    azureVoice: 'nl-NL-ColetteNeural',
  ),
  Language(
    bcp47: 'pt-PT',
    englishName: 'Portuguese (Portugal)',
    nativeName: 'Português',
    flag: '🇵🇹',
    azureVoice: 'pt-PT-RaquelNeural',
  ),
  Language(
    bcp47: 'pt-BR',
    englishName: 'Portuguese (Brazil)',
    nativeName: 'Português',
    flag: '🇧🇷',
    azureVoice: 'pt-BR-FranciscaNeural',
  ),
];

Language languageByCode(String code) {
  final normalized = code.trim();
  for (final item in supportedLanguages) {
    if (item.bcp47.toLowerCase() == normalized.toLowerCase()) return item;
  }
  final iso = normalized.split('-').first.toLowerCase();
  for (final item in supportedLanguages) {
    if (item.iso == iso) return item;
  }
  return supportedLanguages.first;
}
