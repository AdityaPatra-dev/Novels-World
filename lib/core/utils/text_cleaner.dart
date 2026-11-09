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

      // Preserve image tokens for embedded illustrations and cover pages
      if (p.startsWith('[IMAGE:')) {
        cleaned.add(p);
        continue;
      }

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

  static final Set<String> _genreAndCategoryTitles = {
    // Standard Genres & Sub-genres
    'action', 'adventure', 'comedy', 'drama', 'fantasy', 'romance', 'harem',
    'xianxia', 'wuxia', 'xuanhuan', 'sci-fi', 'science fiction', 'mystery',
    'supernatural', 'thriller', 'horror', 'historical', 'martial arts', 'mecha',
    'psychological', 'slice of life', 'tragedy', 'ecchi', 'shoujo', 'shounen',
    'seinen', 'josei', 'isekai', 'urban', 'game', 'games', 'magic',
    'virtual reality', 'reincarnation', 'system', 'cultivation', 'litrpg',
    'smut', 'yaoi', 'yuri', 'bl', 'gl', 'gender bender', 'mature', 'adult',
    'school life', 'sports', 'web novel', 'light novel', 'chinese', 'korean',
    'japanese', 'western', 'eastern', 'danmei', 'transmigration', 'modern',
    'fantasy & sci-fi', 'action & adventure', 'mystery & thriller',
    'shounen ai', 'shoujo ai', 'super power', 'vampire', 'military',

    // Category / Navigation Panels
    'genres', 'genre', 'categories', 'category', 'tags', 'tag', 'all genres',
    'all categories', 'novel list', 'series list', 'manga list', 'top rated',
    'most viewed', 'popular novels', 'latest novels', 'completed novels',
    'ongoing novels', 'hot novels', 'new novels', 'updates', 'latest updates',
    'latest release', 'new release', 'most popular', 'all novels', 'ranking',
    'rankings', 'leaderboard', 'directory', 'filter', 'advanced search',
    'random novel', 'random', 'featured', 'bookmarks', 'library', 'history',
    'sign in', 'login', 'log in', 'register', 'logout', 'sign up', 'my account',
    'cart', 'checkout', 'privacy policy', 'terms of service', 'terms of use',
    'dmca', 'contact us', 'about us', 'disclaimer', 'faq', 'help', 'donate',
    'patreon', 'paypal', 'discord', 'telegram', 'facebook', 'twitter',
    'subscribe', 'rss', 'feed', 'home', 'main page', 'front page',
  };

  static final List<String> _forbiddenUrlPatterns = [
    '/genre/',
    '/genres/',
    '/genres-',
    '/the-loai/',
    '/theloai/',
    '/kategori/',
    '/kategoriler/',
    '/categoria/',
    '/categorias/',
    '/category/',
    '/categories/',
    '/tag/',
    '/tags/',
    '/novel-tag/',
    '/tag-novel/',
    '/manga-tag/',
    '/etiket/',
    '/author/',
    '/authors/',
    '/tac-gia/',
    '/yazar/',
    '/autor/',
    '/autores/',
    '/sort/',
    '/filter/',
    '/order/',
    '/browse/',
    '/search/',
    '/type/',
    '/status/',
    'wp-login',
    '/login',
    '/register',
    '/cart',
    '/checkout',
    '/my-account',
    '/admin',
    '/user/',
    '/profile/',
    '/contact',
    '/about',
    '/dmca',
    '/privacy',
    '/terms',
    '/disclaimer',
    '/faq',
    '/feed',
    '/rss',
  ];

  static bool isGenreOrCategoryUrl(String url) {
    final u = url.toLowerCase().trim();
    if (u == '#' || u == '/' || u.isEmpty) return true;
    for (final pattern in _forbiddenUrlPatterns) {
      if (u.contains(pattern)) return true;
    }
    // Also check if path ends with pure page pagination e.g. /page/2/
    if (RegExp(r'/page/\d+/?$').hasMatch(u)) return true;
    return false;
  }

  static bool isValidNovelTitle(String title, String url) {
    final t = title.trim().toLowerCase();
    if (t.length < 2) return false;

    // Filter genre/category/panel titles
    if (_genreAndCategoryTitles.contains(t)) return false;

    // Filter title prefixed with "genre: " or "category: "
    if (t.startsWith('genre:') || t.startsWith('category:') || t.startsWith('tag:')) {
      return false;
    }

    // Filter known parked domain / spam blog titles
    if (t.contains('denver broncos') ||
        t.contains('ai chatgpt') ||
        t.contains('zaman yönetimi') ||
        t.contains('casino') ||
        t.contains('slot online')) {
      return false;
    }

    // Filter invalid, genre, category, author or navigation URLs
    if (isGenreOrCategoryUrl(url)) {
      return false;
    }

    return true;
  }

  /// Cleans, normalizes, and strips promotional/SEO clutter from novel titles.
  /// Eliminates prefixes like "Read [Title] Online for Free", trailing watermarks
  /// like "- NovelFull", leaked badges like "HOT", "NEW", "COMPLETED", and author suffixes.
  static String cleanNovelTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';

    String t = rawTitle;

    // Decode common HTML entities if leaked through
    t = t
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');

    // Normalize unicode quotes and dashes
    t = t
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('—', ' - ')
        .replaceAll('–', ' - ');

    // Replace newlines and extra spaces with a single space
    t = t.replaceAll(RegExp(r'[\r\n\t]+'), ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    // 1. Strip leading promotional prefixes:
    // e.g. "Read Novel Shadow Slave", "Read Shadow Slave", "Free Novel Shadow Slave", "[HOT] Shadow Slave"
    t = t.replaceAll(RegExp(r'^(?:Read\s+)?Novel\s+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'^Read\s+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'^Free\s+(?:Web\s*)?Novel\s+', caseSensitive: false), '');
    t = t.replaceAll(
      RegExp(r'^\[(?:HOT|NEW|RAW|TRANSLATED|COMPLETED|ONGOING|WEB\s*NOVEL|LIGHT\s*NOVEL|WN|LN)\]\s*', caseSensitive: false),
      '',
    );

    // 2. Strip trailing "Online for Free by [Author]" or "Online Free by [Author]" (AllFreeNovel / FreeWebNovel format)
    t = t.replaceAll(RegExp(r'\s+Online\s+(?:for\s+)?Free(?:\s+by\s+.*)?$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+Free\s+Online(?:\s+by\s+.*)?$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+Novel\s+Online(?:\s+by\s+.*)?$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+Online(?:\s+by\s+.*)?$', caseSensitive: false), '');

    // 3. Strip trailing site watermarks, aggregator branding, and domain names:
    // e.g. "Shadow Slave - NovelFull", "Solo Leveling | ReadNovelFull", "Lord of the Mysteries - Free Web Novel"
    t = t.replaceAll(
      RegExp(
        r'\s*[-|~•]\s*(?:(?:Read|Free|All)\s*)?(?:Web\s*|Light\s*)?(?:Novel(?:Full|Bin|Cool|Read|Updates|Pub|Fire|Spot)?|BoxNovel|LibRead|WuxiaBox|ReadWN|KolNovel|KnoxT|MangaPeak|AsuraScans|RoyalRoad|ScribbleHub|Kakuyomu)(?:\.com|\.net|\.org)?\s*$',
        caseSensitive: false,
      ),
      '',
    );

    // 4. Strip trailing bracketed format tags:
    // e.g. "(Web Novel)", "(Light Novel)", "(WN)", "(LN)", "(Raw)", "(Translated)", "[Completed]"
    t = t.replaceAll(
      RegExp(
        r'\s*[\(\[](?:Web\s*Novel|Light\s*Novel|WN|LN|Raw|Translated|Completed|Ongoing|Official)[\)\]]\s*$',
        caseSensitive: false,
      ),
      '',
    );

    // 5. Strip trailing status words leaked from HTML badge spans:
    // e.g. "Solo Leveling HOT", "Martial Peak COMPLETED"
    t = t.replaceAll(RegExp(r'\s+(?:HOT|NEW|COMPLETED|ONGOING)$', caseSensitive: false), '');

    // 6. Strip trailing chapter range in title:
    // e.g. "Shadow Slave - Chapter 1 - 2500" or "Shadow Slave - 1 - 2500"
    t = t.replaceAll(RegExp(r'\s*[-|]\s*(?:Chapter\s*)?\d+(?:\s*[-–]\s*\d+)?\s*$', caseSensitive: false), '');

    // Clean any trailing or leading punctuation leftover from stripping
    t = t.replaceAll(RegExp(r'^[-–|~:;\s]+'), '').replaceAll(RegExp(r'[-–|~:;\s]+$'), '').trim();

    return t.isNotEmpty ? t : rawTitle.trim();
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

    // Normalize quotes, dashes, and novel formatting to natural pauses
    s = s
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('—', ', ')
        .replaceAll('–', ', ')
        .replaceAll(RegExp(r'-{2,}'), ', ')
        .replaceAll('…', '...')
        .replaceAll(RegExp(r'\.{4,}'), '...')
        .replaceAll('~', '')
        .replaceAll(RegExp(r'\?{2,}'), '?')
        .replaceAll(RegExp(r'!{2,}'), '!');

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
      RegExp(r'\b1st\b'): 'first',
      RegExp(r'\b2nd\b'): 'second',
      RegExp(r'\b3rd\b'): 'third',
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

  /// Checks whether a cover URL is a valid, high-quality novel book cover
  /// rather than a website logo, header banner, icon, avatar, or dummy placeholder.
  static bool isValidCoverUrl(String? url) {
    if (url == null) return false;
    final u = url.trim().toLowerCase();
    if (u.isEmpty || u == '#' || u == '/') return false;
    if (u.startsWith('data:')) return false;

    // NovelCool and similar novel sources store legitimate covers under /logo/ paths or specific subdomains
    if (u.contains('novelcool.com') || u.contains('img.novelcool.com') || u.contains('vdoc.pub')) {
      return true;
    }

    // Filter out common site logos, headers, favicons, avatars, banners, and placeholders
    final badPatterns = [
      'logo',
      'favicon',
      'avatar',
      'dflazy',
      'placeholder',
      'blank.gif',
      'dummy',
      'default-cover',
      'default_cover',
      'no-cover',
      'nocover',
      'anon-art',
      'site-icon',
      'app-icon',
      'header-banner',
      'top-banner',
      'banner.',
      'banner-',
      'badge',
      'loading',
      'spinner',
      'icon-',
      '-icon.',
      'icon.',
    ];

    for (final pattern in badPatterns) {
      if (u.contains(pattern)) return false;
    }

    // Must be a valid http/https or file URL or relative path
    if (!u.startsWith('http://') &&
        !u.startsWith('https://') &&
        !u.startsWith('file://') &&
        !u.startsWith('//') &&
        !u.startsWith('/')) {
      return false;
    }

    return true;
  }
}

