"""One map for speech recognition, translation, and the voice that speaks the result.

Hindi and the other Indic languages name a native script. The translator must
ask for that script. A Hindi voice reading Latin letters sounds like Indian English.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class LanguageProfile:
    name: str
    stt_code: str
    translator_code: str
    tts_voice: str
    script: str | None = None
    to_script: str | None = None


LANGUAGES: tuple[LanguageProfile, ...] = (
    LanguageProfile("Hindi", "hi-IN", "hi", "hi-IN-SwaraNeural", "Devanagari", "Deva"),
    LanguageProfile("Tamil", "ta-IN", "ta", "ta-IN-PallaviNeural", "Tamil", "Taml"),
    LanguageProfile("Telugu", "te-IN", "te", "te-IN-ShrutiNeural", "Telugu", "Telu"),
    LanguageProfile("Malayalam", "ml-IN", "ml", "ml-IN-SobhanaNeural", "Malayalam", "Mlym"),
    LanguageProfile("Gujarati", "gu-IN", "gu", "gu-IN-DhwaniNeural", "Gujarati", "Gujr"),
    LanguageProfile("Marathi", "mr-IN", "mr", "mr-IN-AarohiNeural", "Devanagari", "Deva"),
    LanguageProfile("Bengali", "bn-IN", "bn", "bn-IN-TanishaaNeural", "Bengali", "Beng"),
    LanguageProfile("English (India)", "en-IN", "en", "en-IN-NeerjaNeural"),
    LanguageProfile("German", "de-DE", "de", "de-DE-KatjaNeural"),
    LanguageProfile("Chinese Mandarin", "zh-CN", "zh-Hans", "zh-CN-XiaoxiaoNeural"),
    LanguageProfile("French", "fr-FR", "fr", "fr-FR-DeniseNeural"),
    LanguageProfile("Spanish", "es-ES", "es", "es-ES-ElviraNeural"),
    LanguageProfile("Dutch", "nl-NL", "nl", "nl-NL-ColetteNeural"),
    LanguageProfile("Portuguese (Portugal)", "pt-PT", "pt-pt", "pt-PT-RaquelNeural"),
    LanguageProfile("Portuguese (Brazil)", "pt-BR", "pt", "pt-BR-FranciscaNeural"),
)

_BY_CODE: dict[str, LanguageProfile] = {}
for _item in LANGUAGES:
    _BY_CODE[_item.stt_code.lower()] = _item
    _BY_CODE.setdefault(_item.stt_code.split("-")[0].lower(), _item)


def lookup(code: str | None) -> LanguageProfile | None:
    if not code:
        return None
    key = code.strip().lower()
    found = _BY_CODE.get(key)
    if found:
        return found
    return _BY_CODE.get(key.split("-")[0])


def voice_for(code: str | None) -> str:
    """Native TTS voice for this language. Never an English voice for Hindi."""
    profile = lookup(code)
    if profile:
        return profile.tts_voice
    fallback = (code or "en-IN").strip()
    return f"{fallback}-Neural"


def translator_pair(src: str, dst: str) -> tuple[str, str, str | None]:
    source = None if is_auto(src) else lookup(src)
    target = lookup(dst)
    if source:
        from_code = source.translator_code
    elif is_auto(src):
        from_code = ""
    else:
        from_code = src.split("-")[0]
    to_code = target.translator_code if target else dst.split("-")[0]
    to_script = target.to_script if target else None
    return from_code, to_code, to_script


def script_rule(dst: str) -> str:
    profile = lookup(dst)
    if not profile or not profile.script:
        return ""
    return (
        f" Write the {profile.name} translation in {profile.script} script only. "
        "Do not use Latin or Romanized letters."
    )


def is_latin_heavy(text: str) -> bool:
    letters = [ch for ch in text if ch.isalpha()]
    if not letters:
        return False
    latin = sum(1 for ch in letters if ("A" <= ch <= "Z") or ("a" <= ch <= "z"))
    return latin / len(letters) > 0.5


def is_auto(code: str | None) -> bool:
    return not code or code.strip().lower() in {"auto", "und"}


def same_language(left: str | None, right: str | None) -> bool:
    """True when both codes are the same translation language."""
    if is_auto(left) or is_auto(right):
        return False
    source = lookup(left)
    target = lookup(right)
    if source and target:
        return source.translator_code == target.translator_code
    return (left or "").split("-")[0].lower() == (right or "").split("-")[0].lower()


def lid_candidates(*priority: str | None, limit: int = 10) -> list[str]:
    """Locales for Azure continuous language identification.

    Azure accepts at most 10 candidates, and only one locale per base language.
    Preferred languages are pinned first so a call in those languages is detected.
    """
    ordered: list[str] = []
    seen: set[str] = set()

    def add(code: str | None) -> None:
        if len(ordered) >= limit or is_auto(code):
            return
        profile = lookup(code)
        stt = profile.stt_code if profile else ""
        if not stt:
            return
        base = stt.split("-")[0].lower()
        if base in seen:
            return
        seen.add(base)
        ordered.append(stt)

    for code in priority:
        add(code)
    for item in LANGUAGES:
        add(item.stt_code)
    return ordered
