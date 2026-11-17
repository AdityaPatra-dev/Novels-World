/// Comprehensive Indic and Multi-Language Script Helper & Phonetic Transliteration Engine.
/// Provides exact phonetic mapping from Odia script (U+0B00..U+0B7F) into Devanagari (U+0900..U+097F)
/// for high-fidelity neural speech synthesis using Microsoft Neural Indian voices.
class OdiaTransliteration {
  /// Converts Odia script text into phonetically identical Devanagari text.
  /// Preserves all non-Odia text (English, punctuation, numbers, spaces) intact.
  static String toDevanagari(String text) {
    if (text.isEmpty) return text;

    final sb = StringBuffer();
    final runes = text.runes.toList();

    for (int i = 0; i < runes.length; i++) {
      final cp = runes[i];

      // Odia Unicode block: U+0B00 to U+0B7F
      if (cp >= 0x0B01 && cp <= 0x0B71) {
        // Special case mappings:
        switch (cp) {
          // 0x0B5F is Odia ୟ (antahstha YA, e.g. ଉପନ୍ୟାସ, ସମୟ, ଦୟା) -> Devanagari य (0x092F)
          // Crucial: Devanagari 0x095F (य़) causes neural TTS engines to choke/mutilate pronunciation.
          case 0x0B5F:
            sb.writeCharCode(0x092F);
            break;
          // 0x0B2F is Odia ଯ (Ja). In Odia initial/standalone position it is pronounced 'J',
          // but in conjuncts preceded by Halanta/Virama (e.g. ସୂର୍ଯ୍ୟ) it is pronounced 'Ya'.
          case 0x0B2F:
            final prevCp = i > 0 ? runes[i - 1] : 0;
            if (prevCp == 0x0B4D) {
              sb.writeCharCode(0x092F); // Devanagari य
            } else {
              sb.writeCharCode(0x091C); // Devanagari ज
            }
            break;
          // 0x0B33 is Odia ଳ (retroflex L) -> Devanagari ल (0x0932) for flawless neural flow
          case 0x0B33:
            sb.writeCharCode(0x0932);
            break;
          // 0x0B35 is Odia ଵ (Va) -> Devanagari व (0x0935)
          case 0x0B35:
            sb.writeCharCode(0x0935);
            break;
          // 0x0B71 is Odia ୱ (Wa) -> Devanagari व (0x0935)
          case 0x0B71:
            sb.writeCharCode(0x0935);
            break;
          // 0x0B5C is Odia ଡ଼ (RRA) -> Devanagari ड़ (0x095C)
          case 0x0B5C:
            sb.writeCharCode(0x095C);
            break;
          // 0x0B5D is Odia ଢ଼ (RHA) -> Devanagari ढ़ (0x095D)
          case 0x0B5D:
            sb.writeCharCode(0x095D);
            break;
          // 0x0B56 is Odia AI length mark -> Devanagari AI
          case 0x0B56:
            sb.writeCharCode(0x0948);
            break;
          // 0x0B57 is Odia AU length mark -> Devanagari AU
          case 0x0B57:
            sb.writeCharCode(0x094C);
            break;
          default:
            // Standard Unicode offset between Odia and Devanagari is exactly -0x0200
            final devChar = cp - 0x0200;
            if (devChar >= 0x0900 && devChar <= 0x097F) {
              sb.writeCharCode(devChar);
            } else {
              sb.writeCharCode(cp);
            }
            break;
        }
      } else {
        sb.writeCharCode(cp);
      }
    }

    return sb.toString();
  }

  /// Detects the written script / language of a text sample.
  /// Returns standard 2-letter ISO 639-1 code if detected, or null.
  static String? detectScript(String text) {
    if (text.trim().isEmpty) return null;

    final clean = text.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return null;

    // 1. Odia (U+0B00..U+0B7F)
    if (RegExp(r'[\u0B00-\u0B7F]').hasMatch(clean)) return 'or';

    // 2. Hindi / Devanagari (U+0900..U+097F)
    if (RegExp(r'[\u0900-\u097F]').hasMatch(clean)) return 'hi';

    // 3. Bengali / Assamese (U+0980..U+09FF)
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(clean)) return 'bn';

    // 4. Tamil (U+0B80..U+0BFF)
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(clean)) return 'ta';

    // 5. Telugu (U+0C00..U+0C7F)
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(clean)) return 'te';

    // 6. Kannada (U+0C80..U+0CFF)
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(clean)) return 'kn';

    // 7. Malayalam (U+0D00..U+0D7F)
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(clean)) return 'ml';

    // 8. Gujarati (U+0A80..U+0AFF)
    if (RegExp(r'[\u0A80-\u0AFF]').hasMatch(clean)) return 'gu';

    // 9. Punjabi (Gurmukhi: U+0A00..U+0A7F)
    if (RegExp(r'[\u0A00-\u0A7F]').hasMatch(clean)) return 'pa';

    // 10. Arabic / Persian / Urdu (U+0600..U+06FF)
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(clean)) return 'ar';

    // 11. Japanese (Hiragana / Katakana / CJK)
    if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(clean)) return 'ja';

    // 12. Korean (Hangul: U+AC00..U+D7AF, U+1100..U+11FF)
    if (RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]').hasMatch(clean)) return 'ko';

    // 13. Chinese (CJK Unified Ideographs: U+4E00..U+9FFF)
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(clean)) return 'zh';

    // 14. Russian / Cyrillic (U+0400..U+04FF)
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(clean)) return 'ru';

    return null;
  }
}
