class TextCleaner {
  static final List<RegExp> _adPatterns = [
    RegExp(r'read\s+latest\s+chapters?\s+at\s+.*', caseSensitive: false),
    RegExp(r'translated\s+by\s+.*', caseSensitive: false),
    RegExp(r'if\s+you\s+find\s+any\s+errors.*please\s+let\s+us\s+know.*', caseSensitive: false),
    RegExp(r'visit\s+.*novel.*for\s+more\s+chapters', caseSensitive: false),
    RegExp(r'visit\s+.*novel.*', caseSensitive: false),
    RegExp(r'support\s+the\s+author\s+at\s+.*', caseSensitive: false),
    RegExp(r'this\s+chapter\s+is\s+updated\s+by\s+.*', caseSensitive: false),
    RegExp(r'find\s+authorized\s+novels\s+in\s+.*', caseSensitive: false),
  ];

  static List<String> cleanParagraphs(List<String> rawParagraphs) {
    final List<String> cleaned = [];

    for (final raw in rawParagraphs) {
      String p = raw.trim();
      if (p.isEmpty) continue;

      // Filter known ad / watermark paragraphs
      bool isAd = false;
      for (final pattern in _adPatterns) {
        if (pattern.hasMatch(p)) {
          isAd = true;
          break;
        }
      }
      if (isAd) continue;

      // Normalize unicode quotes and dashes
      p = p
          .replaceAll('“', '"')
          .replaceAll('”', '"')
          .replaceAll('’', "'")
          .replaceAll('‘', "'")
          .replaceAll('—', ' - ')
          .replaceAll('…', '...');

      // Strip unwanted HTML artifacts if any leaked through
      p = p.replaceAll(RegExp(r'<[^>]*>'), '');

      if (p.trim().isNotEmpty) {
        cleaned.add(p);
      }
    }

    return cleaned;
  }

  static String toCleanRawText(List<String> paragraphs) {
    return paragraphs.join('\n\n');
  }

  static bool isValidNovelTitle(String title, String url) {
    final t = title.trim().toLowerCase();
    if (t.length < 2) return false;

    // Filter common navigation / login / utility links
    const junkTitles = [
      'sign in',
      'login',
      'log in',
      'register',
      'logout',
      'sign up',
      'my account',
      'cart',
      'checkout',
      'privacy policy',
      'terms of service',
      'terms of use',
      'dmca',
      'contact us',
      'about us',
      'disclaimer',
      'ongoing novels',
      'latest novels',
      'popular novels',
      'browse novels',
      'search novels',
      'home',
      'all novels',
      'bookmarked',
      'bookmark',
      'discord',
      'telegram',
      'facebook',
      'twitter',
      'subscribe',
    ];

    if (junkTitles.contains(t)) return false;

    // Filter known parked domain / spam blog titles
    if (t.contains('denver broncos') ||
        t.contains('ai chatgpt') ||
        t.contains('zaman yönetimi') ||
        t.contains('casino') ||
        t.contains('slot online')) {
      return false;
    }

    // Filter invalid URLs
    final u = url.toLowerCase();
    if (u == '#' ||
        u.contains('wp-login') ||
        u.contains('/login') ||
        u.contains('/register') ||
        u.contains('/cart') ||
        u.contains('/my-account')) {
      return false;
    }

    return true;
  }

  /// Cleans, normalizes, and smooths a sentence specifically for high-quality TTS prosody.
  /// Expands abbreviations, eliminates awkward symbols, and ensures natural start/end cadence.
  static String prepareSentenceForSpeech(String rawSentence) {
    String s = rawSentence.trim();
    if (s.isEmpty) return '';

    // Remove markdown formatting
    s = s.replaceAll(RegExp(r'\*\*|\*|__|_|~~'), '');

    // Remove ASCII dividers: ***, ---, ===, ___
    s = s.replaceAll(RegExp(r'^[*\-=_]{3,}$', multiLine: true), '');

    // Format bracketed game/novel system messages: [System: Level Up] -> System: Level Up.
    s = s.replaceAllMapped(RegExp(r'\[(.*?)\]'), (m) {
      final inner = m[1]?.trim() ?? '';
      return inner.isNotEmpty ? '$inner. ' : '';
    });

    // Normalize quotes and dashes to natural pauses
    s = s
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('—', ', ')
        .replaceAll('–', ', ')
        .replaceAll('…', '...');

    // Expand abbreviations that trip TTS engines into awkward monotonic stops
    final abbrevs = <RegExp, String>{
      RegExp(r'\bMr\.'): 'Mister',
      RegExp(r'\bMrs\.'): 'Missus',
      RegExp(r'\bMs\.'): 'Miss',
      RegExp(r'\bDr\.'): 'Doctor',
      RegExp(r'\bProf\.'): 'Professor',
      RegExp(r'\bVol\.'): 'Volume',
      RegExp(r'\bCh\.'): 'Chapter',
      RegExp(r'\bNo\.'): 'Number',
      RegExp(r'\bvs\.'): 'versus',
      RegExp(r'\betc\.'): 'etcetera',
      RegExp(r'\bSt\.'): 'Saint',
      RegExp(r'\be\.g\.'): 'for example',
      RegExp(r'\bi\.e\.'): 'that is',
    };
    for (final entry in abbrevs.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }

    // Clean stray leading and trailing punctuation that cause audio popping
    s = s.replaceAll(RegExp(r'^[“"«»\u0027\-—–\s,;:.]+'), '');
    s = s.replaceAll(RegExp(r'[“"«»\u0027\s]+$'), '');

    // Ensure sentence ends with punctuation for natural descending cadence
    final trimmed = s.trim();
    if (trimmed.isNotEmpty && !RegExp(r'[.!?…]$').hasMatch(trimmed)) {
      s = '$trimmed.';
    }

    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
}

