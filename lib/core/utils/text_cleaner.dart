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
}

