import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for Gadya Kosh (http://gadyakosh.org).
/// The definitive digital treasury of Hindi classical literature, historical prose,
/// novels, and short stories (Munshi Premchand, Hazari Prasad Dwivedi, Yashpal, etc.).
class GadyaKoshExtractor implements NovelSource {
  @override
  final String id = 'gadyakosh';

  @override
  final String name = 'Gadya Kosh (गद्य कोश)';

  @override
  final String baseUrl = 'http://gadyakosh.org';

  @override
  final String lang = 'hi';

  @override
  final String iconUrl = 'http://gadyakosh.org/favicon.ico';

  @override
  final int estimatedNovelCount = 15000;

  late final http.Client _client;

  GadyaKoshExtractor({http.Client? client}) {
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
      'प्रेमचंद',
      'मानसरोवर',
      'उपन्यास',
      'यशपाल',
      'हजारी प्रसाद द्विवेदी',
      'सुदर्शन',
    ];
    final query = popularQueries[(page - 1) % popularQueries.length];
    return search(query, page: 1);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    const latestQueries = [
      'कहानी',
      'कहानियां',
      'निबंध',
      'संस्मरण',
      'ऐतिहासिक',
      'नाटक',
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
    final url = '$baseUrl/gk/api.php?action=query&list=search&srsearch=$encodedQuery&srlimit=25&sroffset=$offset&format=json';

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

      // Ignore MediaWiki internal and category namespaces
      if (rawTitle.startsWith('श्रेणी:') ||
          rawTitle.startsWith('विशेष:') ||
          rawTitle.startsWith('वार्ता:') ||
          rawTitle.startsWith('सदस्य:')) {
        continue;
      }

      var title = rawTitle;
      var author = 'Unknown Author';

      if (rawTitle.contains('/')) {
        final parts = rawTitle.split('/').map((s) => s.trim()).toList();
        title = parts[0];
        if (parts.length >= 2) {
          author = parts[1];
        }
      }

      final snippetRaw = item['snippet']?.toString() ?? '';
      final snippet = snippetRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

      final encodedTitle = Uri.encodeComponent(rawTitle.replaceAll(' ', '_'));
      final novelUrl = '$baseUrl/gk/index.php?title=$encodedTitle';

      novels.add(Novel(
        id: '${id}_${rawTitle.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: snippet,
        coverUrl: 'https://gadyakosh.org/gk/otherapps/images/Gadya-Kosh-Logo.png',
        genres: const ['Hindi', 'Classics', 'Sahitya'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      ));
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to load page: ${response.statusCode}');
      }

      final doc = html_parser.parse(response.body);
      final heading = doc.querySelector('#firstHeading')?.text.trim() ?? '';
      var title = heading;
      var author = 'Unknown Author';

      if (heading.contains('/')) {
        final parts = heading.split('/').map((s) => s.trim()).toList();
        title = parts[0];
        if (parts.length >= 2) {
          author = parts[1];
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
        coverUrl: 'https://gadyakosh.org/gk/otherapps/images/Gadya-Kosh-Logo.png',
        genres: const ['Hindi', 'Classics', 'Sahitya'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      );
    } catch (_) {
      return Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: 'Hindi Classic',
        author: 'Unknown Author',
        coverUrl: 'https://gadyakosh.org/gk/otherapps/images/Gadya-Kosh-Logo.png',
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
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final contentElem = doc.querySelector('#mw-content-text');
      if (contentElem == null) return [];

      final List<Chapter> chapters = [];
      final heading = doc.querySelector('#firstHeading')?.text.trim() ?? 'Novel';
      final novelId = '${id}_${heading.hashCode.abs()}';

      // Find sub-story / sub-chapter links inside mw-content-text
      final anchors = contentElem.querySelectorAll('a[href*="/gk/"], a[href*="title="]');
      final ignoredPrefixes = [
        'रचनाकारों की सूची',
        'अंगिका',
        'राजस्थानी',
        'हिन्दी',
        'गद्य कोश',
        'विशेष:',
        'श्रेणी:',
        'सहायता:',
        'दान',
      ];

      for (final a in anchors) {
        final text = a.text.trim();
        final href = a.attributes['href'] ?? '';
        if (text.isEmpty || href.isEmpty) continue;

        if (ignoredPrefixes.any((p) => text.contains(p) || href.contains(Uri.encodeComponent(p)))) {
          continue;
        }

        // Link should contain story/chapter or author structure
        if (text == heading || text.length < 2) continue;

        final chapterUrl = href.startsWith('http') ? href : '$baseUrl$href';
        final cleanTitle = text.contains('/') ? text.split('/')[0].trim() : text;

        chapters.add(Chapter(
          id: '${id}_${chapterUrl.hashCode.abs()}',
          novelId: novelId,
          title: cleanTitle,
          url: chapterUrl,
          chapterNumber: (chapters.length + 1).toDouble(),
        ));
      }

      // If no subchapters were found, this page itself is a standalone short story / piece!
      if (chapters.isEmpty) {
        chapters.add(Chapter(
          id: '${id}_${novelUrl.hashCode.abs()}',
          novelId: novelId,
          title: heading.contains('/') ? heading.split('/')[0].trim() : heading,
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
    final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter content from $chapterUrl');
    }

    final doc = html_parser.parse(response.body);
    final heading = doc.querySelector('#firstHeading')?.text.trim() ?? 'Chapter';
    final contentElem = doc.querySelector('#mw-content-text');

    if (contentElem == null) {
      throw Exception('No readable content found at $chapterUrl');
    }

    // Remove navigation, toolbars, scripts, category links
    for (final bad in contentElem.querySelectorAll(
      'script, style, nav, table, .btn-group, .gkrachna, .catlinks, #toc, .printfooter, .mw-jump-link',
    )) {
      bad.remove();
    }

    final rawText = contentElem.text;
    final rawLines = rawText.split('\n');
    final List<String> paragraphs = [];

    const ignoredHeaders = {'हिन्दी', 'अंगिका', 'राजस्थानी', 'Script', 'Devanagari'};

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.length < 3) continue;
      if (ignoredHeaders.contains(trimmed)) continue;
      if (trimmed.startsWith('»') || trimmed.endsWith('»')) continue;

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
