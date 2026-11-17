import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for Kavita Kosh (http://kavitakosh.org).
/// India's grandest digital treasury of Hindi, Braj Bhasha, Awadhi, and Maithili poetry,
/// epics (Ramcharitmanas, Rashmirathi, Kamayani), and classical verses.
class KavitaKoshExtractor implements NovelSource {
  @override
  final String id = 'kavitakosh';

  @override
  final String name = 'Kavita Kosh (कविता कोश)';

  @override
  final String baseUrl = 'http://kavitakosh.org';

  @override
  final String lang = 'hi';

  @override
  final String iconUrl = 'http://kavitakosh.org/favicon.ico';

  @override
  final int estimatedNovelCount = 25000;

  late final http.Client _client;

  KavitaKoshExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'hi,en-US,en;q=0.9',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    const popularQueries = [
      'रश्मिरथी',
      'रामचरितमानस',
      'कामायनी',
      'मधुशाला',
      'निराला',
      'महादेवी वर्मा',
      'रामधारी सिंह दिनकर',
    ];
    final query = popularQueries[(page - 1) % popularQueries.length];
    return search(query, page: 1);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    const latestQueries = [
      'कविता',
      'गीत',
      'गज़ल',
      'दोहे',
      'छंद',
      'पद',
    ];
    final query = latestQueries[(page - 1) % latestQueries.length];
    return search(query, page: 1);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final offset = (page - 1) * 25;
    final encodedQuery = Uri.encodeComponent(cleanQuery);
    final url = '$baseUrl/kk/api.php?action=query&list=search&srsearch=$encodedQuery&srlimit=25&sroffset=$offset&format=json';

    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final searchResults = data['query']?['search'] as List<dynamic>? ?? [];

      return parseSearchResults(searchResults);
    } catch (_) {
      return [];
    }
  }

  List<Novel> parseSearchResults(List<dynamic> results) {
    final List<Novel> novels = [];

    for (final item in results) {
      final rawTitle = item['title']?.toString() ?? '';
      if (rawTitle.isEmpty) continue;

      if (rawTitle.startsWith('श्रेणी:') ||
          rawTitle.startsWith('विशेष:') ||
          rawTitle.startsWith('वार्ता:') ||
          rawTitle.startsWith('सदस्य:')) {
        continue;
      }

      var title = rawTitle;
      var author = 'कविता कोश संग्रह';

      if (rawTitle.contains('/')) {
        final parts = rawTitle.split('/').map((s) => s.trim()).toList();
        title = parts[0];
        if (parts.length >= 2) {
          author = parts.last;
        }
      }

      final snippetRaw = item['snippet']?.toString() ?? '';
      final snippet = snippetRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

      final encodedTitle = Uri.encodeComponent(rawTitle.replaceAll(' ', '_'));
      final novelUrl = '$baseUrl/kk/index.php?title=$encodedTitle';

      novels.add(Novel(
        id: '${id}_${rawTitle.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: snippet,
        coverUrl: 'https://kavitakosh.org/kk/otherapps/images/KK-18-Years-Logo-small.png',
        genres: const ['Hindi', 'Poetry', 'Epics', 'Sahitya'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      ));
    }

    return novels;
  }

  Uri _parseSafeUri(String url) {
    var clean = url.trim();
    try {
      return Uri.parse(clean);
    } catch (_) {
      try {
        final schemeMatch = RegExp(r'^(https?://[^/]+)(.*)$').firstMatch(clean);
        if (schemeMatch != null) {
          final prefix = schemeMatch.group(1)!;
          final pathAndQuery = schemeMatch.group(2)!;
          final encodedPath = Uri.encodeFull(pathAndQuery);
          return Uri.parse('$prefix$encodedPath');
        }
      } catch (_) {}
      return Uri.parse(Uri.encodeFull(clean));
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    try {
      final response = await _client.get(_parseSafeUri(novelUrl), headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to load page');
      }

      final doc = html_parser.parse(response.body);
      final heading = doc.querySelector('#firstHeading')?.text.trim() ?? '';
      var title = heading;
      var author = 'कविता कोश';

      if (heading.contains('/')) {
        final parts = heading.split('/').map((s) => s.trim()).toList();
        title = parts[0];
        if (parts.length >= 2) {
          author = parts.last;
        }
      }

      final contentElem = doc.querySelector('#mw-content-text');
      final desc = contentElem?.querySelector('p')?.text.trim() ?? '';

      return Novel(
        id: '${id}_${heading.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: desc,
        coverUrl: 'https://kavitakosh.org/kk/otherapps/images/KK-18-Years-Logo-small.png',
        genres: const ['Hindi', 'Poetry', 'Epics'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      );
    } catch (_) {
      return Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: 'Hindi Poem / Epic',
        author: 'Unknown Author',
        coverUrl: 'https://kavitakosh.org/kk/otherapps/images/KK-18-Years-Logo-small.png',
        sourceUrl: novelUrl,
      );
    }
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    try {
      final response = await _client.get(_parseSafeUri(novelUrl), headers: _headers);
      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final contentElem = doc.querySelector('#mw-content-text');
      if (contentElem == null) return [];

      for (final bad in contentElem.querySelectorAll(
        '.infobox, .navbox, #toc, .catlinks, .plainlinks, .printfooter, .mw-jump-link, .metadata, .dablink, header, nav, footer, .sister-projects',
      )) {
        bad.remove();
      }

      final List<Chapter> chapters = [];
      final heading = doc.querySelector('#firstHeading')?.text.trim() ?? 'Kavita';
      final novelId = '${id}_${heading.hashCode.abs()}';

      var novelTitle = heading;
      var authorName = 'Unknown Author';
      if (heading.contains('/')) {
        final parts = heading.split('/').map((s) => s.trim()).toList();
        novelTitle = parts[0];
        if (parts.length >= 2) {
          authorName = parts[1];
        }
      }

      final anchors = contentElem.querySelectorAll('a[href*="/kk/"], a[href*="title="]');
      final ignoredPrefixes = [
        'रचनाकारों की सूची',
        'अंगिका',
        'अवधी',
        'ब्रजभाषा',
        'भोजपुरी',
        'गुजराती',
        'नेपाली',
        'मैथिली',
        'राजस्थानी',
        'हरियाणवी',
        'खड़ी बोली',
        'उर्दू',
        'सिंधी',
        'संस्कृत',
        'कन्नड़',
        'तमिल',
        'तेलुगु',
        'मलयालम',
        'मराठी',
        'बांग्ला',
        'असमिया',
        'पंजाबी',
        'कश्मीरी',
        'हिन्दी',
        'कविता कोश',
        'गद्य कोश',
        'विशेष:',
        'श्रेणी:',
        'सहायता:',
        'दान',
        'Script',
        'Devanagari',
        'Roman',
        'मुखपृष्ठ',
        'चौपाल',
        'संपादकीय',
        'लेखक सूची',
      ];

      for (final a in anchors) {
        final text = a.text.trim();
        final href = a.attributes['href'] ?? '';
        if (text.isEmpty || href.isEmpty) continue;
        if (href.contains('&oldid=') || href.contains('printable=yes')) continue;

        String normalizedHref = href;
        try {
          normalizedHref = Uri.decodeFull(href).replaceAll('_', ' ');
        } catch (_) {}

        if (ignoredPrefixes.any((p) => text == p || text.startsWith(p) || normalizedHref.contains(p))) {
          continue;
        }

        // Exclude author bio links: author names on Kavita Kosh do not have '/'
        if (!text.contains('/') && !normalizedHref.contains('/')) {
          continue;
        }

        if (text == heading ||
            text == novelTitle ||
            text == authorName ||
            (authorName.isNotEmpty && (text.contains(authorName) || authorName.contains(text))) ||
            text.contains('"') ||
            text.length < 2) {
          continue;
        }

        var cleanHref = href;
        if (cleanHref.startsWith('/kk/') && !cleanHref.contains('index.php')) {
          cleanHref = '/kk/index.php?title=${cleanHref.substring(4)}';
        } else if (cleanHref.startsWith('http') && cleanHref.contains('/kk/') && !cleanHref.contains('index.php')) {
          cleanHref = cleanHref.replaceFirst('/kk/', '/kk/index.php?title=');
        }

        final chapterUrl = cleanHref.startsWith('http') ? cleanHref : '$baseUrl$cleanHref';
        final cleanTitle = text.contains('/') ? text.split('/')[0].trim() : text;

        chapters.add(Chapter(
          id: '${id}_${chapterUrl.hashCode.abs()}',
          novelId: novelId,
          title: cleanTitle,
          url: chapterUrl,
          chapterNumber: (chapters.length + 1).toDouble(),
        ));
      }

      // If no subchapters were found, this page itself is a standalone poem / work!
      if (chapters.isEmpty) {
        chapters.add(Chapter(
          id: '${id}_${novelUrl.hashCode.abs()}',
          novelId: novelId,
          title: novelTitle.isNotEmpty ? novelTitle : heading,
          url: novelUrl,
          chapterNumber: 1.0,
        ));
      }

      onBatchLoaded?.call(chapters);
      return chapters;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    var effectiveUrl = chapterUrl;
    if (effectiveUrl.contains('/kk/') && !effectiveUrl.contains('index.php')) {
      effectiveUrl = effectiveUrl.replaceFirst('/kk/', '/kk/index.php?title=');
    }

    final response = await _client.get(_parseSafeUri(effectiveUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter content from $effectiveUrl');
    }

    final doc = html_parser.parse(response.body);
    final heading = doc.querySelector('#firstHeading')?.text.trim() ?? 'Kavita';
    final contentElem = doc.querySelector('#mw-content-text');

    if (contentElem == null) {
      throw Exception('No readable content found at $chapterUrl');
    }

    for (final bad in contentElem.querySelectorAll(
      'script, style, nav, table, .btn-group, .gkrachna, .catlinks, #toc, .printfooter, .mw-jump-link',
    )) {
      bad.remove();
    }

    final rawText = contentElem.text;
    final rawLines = rawText.split('\n');
    final List<String> paragraphs = [];

    const ignoredHeaders = {'हिन्दी/उर्दू', 'अंगिका', 'अवधी', 'गुजराती', 'नेपाली', 'भोजपुरी', 'मैथिली', 'राजस्थानी', 'हरियाणवी', 'Script', 'Devanagari', 'Roman'};

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.length < 2) continue;
      if (ignoredHeaders.contains(trimmed)) continue;
      if (trimmed.startsWith('»') || trimmed.endsWith('»')) continue;
      if (trimmed.startsWith('<<') || trimmed.endsWith('>>')) continue;

      paragraphs.add(trimmed);
    }

    final cleanTitle = heading.contains('/') ? heading.split('/')[0].trim() : heading;

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: '${id}_${cleanTitle.hashCode.abs()}',
      title: cleanTitle,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
