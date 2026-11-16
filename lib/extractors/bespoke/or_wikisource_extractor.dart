import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for Odia Wikisource (https://or.wikisource.org).
/// The open digital library containing canonical classical Odia literature,
/// historical chronicles, and masterpieces (Fakir Mohan Senapati, Radhanath Ray,
/// Gangadhar Meher, Sarala Dasa, Upendra Bhanja).
class OdiaWikisourceExtractor implements NovelSource {
  @override
  final String id = 'or_wikisource';

  @override
  final String name = 'Odia Wikisource (ଓଡ଼ିଆ ଉଇକିପାଠାଗାର)';

  @override
  final String baseUrl = 'https://or.wikisource.org';

  @override
  final String lang = 'or';

  @override
  final String iconUrl = 'https://or.wikisource.org/favicon.ico';

  @override
  final int estimatedNovelCount = 5000;

  late final http.Client _client;

  OdiaWikisourceExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'or,en-US,en;q=0.9',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    const popularQueries = [
      'ଛମାଣ ଆଠଗୁଣ୍ଠ',
      'ଫକୀର ମୋହନ ସେନାପତି',
      'ରାଧାନାଥ ରାୟ',
      'ଗଙ୍ଗାଧର ମେହେର',
      'ସାରଳା ଦାସ',
      'ଉପେନ୍ଦ୍ର ଭଞ୍ଜ',
    ];
    final query = popularQueries[(page - 1) % popularQueries.length];
    return search(query, page: 1);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    const latestQueries = [
      'ଉପନ୍ୟାସ',
      'ଗଳ୍ପ',
      'କଥାଲହରୀ',
      'କବିତା',
      'ପ୍ରବନ୍ଧ',
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
    final url = '$baseUrl/w/api.php?action=query&list=search&srsearch=$encodedQuery&srlimit=25&sroffset=$offset&format=json';

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

      // Ignore MediaWiki internal and user namespaces
      if (rawTitle.startsWith('ଶ୍ରେଣୀ:') ||
          rawTitle.startsWith('ବ୍ୟବହାରକାରୀ:') ||
          rawTitle.startsWith('ଉଇକିପାଠାଗାର:') ||
          rawTitle.startsWith('ମିଡ଼ିଆ:') ||
          rawTitle.startsWith('ମିଡ଼ିଆଉଇକି:') ||
          rawTitle.startsWith('Special:') ||
          rawTitle.startsWith('Help:')) {
        continue;
      }

      var title = rawTitle;
      var author = 'ଓଡ଼ିଆ କ୍ଲାସିକ (Odia Classic)';

      if (rawTitle.startsWith('ଲେଖକ:')) {
        title = rawTitle.replaceFirst('ଲେଖକ:', '').trim();
        author = title;
      } else if (rawTitle.contains('/')) {
        final parts = rawTitle.split('/');
        title = parts[0].trim();
      }

      final snippetRaw = item['snippet']?.toString() ?? '';
      final snippet = snippetRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

      final pageId = item['pageid']?.toString() ?? '';
      final novelUrl = pageId.isNotEmpty
          ? '$baseUrl/?curid=$pageId'
          : '$baseUrl/wiki/${Uri.encodeComponent(rawTitle.replaceAll(' ', '_'))}';

      novels.add(Novel(
        id: '${id}_${pageId.isNotEmpty ? pageId : rawTitle.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: snippet.isNotEmpty ? snippet : 'ଓଡ଼ିଆ ଉଇକିପାଠାଗାର ସାହିତ୍ୟ କୃତି।',
        coverUrl: 'https://or.wikisource.org/static/images/project-logos/orwikisource.png',
        genres: const ['Odia', 'Classics', 'Sahitya'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      ));
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    try {
      final pageId = _extractPageIdFromUrl(novelUrl);
      final pageTitle = _extractPageTitleFromUrl(novelUrl);

      final apiUrl = pageId.isNotEmpty
          ? '$baseUrl/w/api.php?action=parse&pageid=$pageId&format=json&prop=text|properties'
          : '$baseUrl/w/api.php?action=parse&page=${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}&format=json&prop=text|properties';

      final response = await _client.get(Uri.parse(apiUrl), headers: _headers);

      String title = pageTitle;
      String author = 'ଓଡ଼ିଆ କ୍ଲାସିକ (Odia Classic)';
      String description = '';
      String coverUrl = 'https://or.wikisource.org/static/images/project-logos/orwikisource.png';

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parseData = data['parse'];
        if (parseData != null) {
          title = parseData['title']?.toString() ?? pageTitle;
          final htmlText = parseData['text']?['*']?.toString() ?? '';
          final doc = html_parser.parse(htmlText);

          final headerTitle = doc.querySelector('#header_title_text')?.text.trim();
          final headerAuthor = doc.querySelector('#header_author_text')?.text.trim();
          final authorLink = doc.querySelector('a[href*="/wiki/ଲେଖକ:"]')?.text.trim();

          if (headerTitle != null && headerTitle.isNotEmpty) {
            title = headerTitle;
          }
          if (headerAuthor != null && headerAuthor.isNotEmpty) {
            author = headerAuthor;
          } else if (authorLink != null && authorLink.isNotEmpty) {
            author = authorLink;
          }

          // Look for cover image
          final img = doc.querySelector('.infobox img, #mw-content-text img, .thumbimage, img');
          if (img != null) {
            final src = img.attributes['src'] ?? '';
            if (src.isNotEmpty && !src.contains('wikimedia-button') && !src.contains('poweredby')) {
              coverUrl = src.startsWith('//') ? 'https:$src' : (src.startsWith('http') ? src : '$baseUrl$src');
            }
          }

          final firstP = doc.querySelector('p')?.text.trim() ?? '';
          if (firstP.isNotEmpty && firstP.length > 20) {
            description = firstP;
          } else {
            description = '$title - $author ଙ୍କ ଦ୍ୱାରା ରଚିତ ଓଡ଼ିଆ କ୍ଲାସିକ ସାହିତ୍ୟ କୃତି।';
          }
        }
      }

      return Novel(
        id: '${id}_${pageId.isNotEmpty ? pageId : pageTitle.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: description,
        coverUrl: coverUrl,
        genres: const ['Odia', 'Classics', 'Sahitya'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      );
    } catch (_) {
      final fallbackTitle = _extractPageTitleFromUrl(novelUrl);
      return Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: fallbackTitle.isNotEmpty ? fallbackTitle : 'Odia Literature',
        author: 'ଓଡ଼ିଆ ଲେଖକ',
        coverUrl: 'https://or.wikisource.org/static/images/project-logos/orwikisource.png',
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
      final pageId = _extractPageIdFromUrl(novelUrl);
      final pageTitle = _extractPageTitleFromUrl(novelUrl);

      final apiUrl = pageId.isNotEmpty
          ? '$baseUrl/w/api.php?action=parse&pageid=$pageId&format=json&prop=text'
          : '$baseUrl/w/api.php?action=parse&page=${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}&format=json&prop=text';

      final response = await _client.get(Uri.parse(apiUrl), headers: _headers);

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final html = data['parse']?['text']?['*']?.toString() ?? '';
      if (html.isEmpty) return [];

      final doc = html_parser.parse(html);
      final List<Chapter> chapters = [];
      final seenUrls = <String>{};
      final novelId = '${id}_${pageId.isNotEmpty ? pageId : pageTitle.hashCode.abs()}';

      final links = doc.querySelectorAll('a[href*="/wiki/"]');
      final ignoredPrefixes = [
        'ଶ୍ରେଣୀ:',
        'ବ୍ୟବହାରକାରୀ:',
        'ଉଇକିପାଠାଗାର:',
        'ଲେଖକ:',
        'Help:',
        'Special:',
        'MediaWiki:',
      ];

      for (final a in links) {
        final text = a.text.trim();
        final href = a.attributes['href'] ?? '';
        if (text.isEmpty || href.isEmpty) continue;

        if (ignoredPrefixes.any((p) => href.contains(Uri.encodeComponent(p)) || href.contains(p))) {
          continue;
        }

        if (text.startsWith('(') && text.endsWith(')')) continue;
        if (text.contains('ରଚନାଗୁଡ଼ିକ ମୋଟା ଅକ୍ଷରରେ') ||
            text.contains('ପ୍ରମୁଖ ରଚନା') ||
            text.contains('ସମ୍ପାଦନା')) {
          continue;
        }

        final chapterUrl = href.startsWith('http') ? href : '$baseUrl$href';
        if (chapterUrl == novelUrl || !seenUrls.add(chapterUrl)) continue;

        chapters.add(Chapter(
          id: '${id}_${chapterUrl.hashCode.abs()}',
          novelId: novelId,
          title: text,
          url: chapterUrl,
          chapterNumber: (chapters.length + 1).toDouble(),
        ));
      }

      // If no subchapters were found, the page itself is a full work or poem!
      if (chapters.isEmpty) {
        final mainTitle = doc.querySelector('#header_title_text')?.text.trim() ?? pageTitle;
        chapters.add(Chapter(
          id: '${id}_${novelUrl.hashCode.abs()}',
          novelId: novelId,
          title: mainTitle.isNotEmpty ? mainTitle : 'ସମ୍ପୂର୍ଣ୍ଣ ରଚନା (Full Work)',
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
    final pageId = _extractPageIdFromUrl(chapterUrl);
    final pageTitle = _extractPageTitleFromUrl(chapterUrl);

    final apiUrl = pageId.isNotEmpty
        ? '$baseUrl/w/api.php?action=parse&pageid=$pageId&format=json&prop=text'
        : '$baseUrl/w/api.php?action=parse&page=${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}&format=json&prop=text';

    final response = await _client.get(Uri.parse(apiUrl), headers: _headers);

    String html = '';
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      html = data['parse']?['text']?['*']?.toString() ?? '';
    }

    if (html.isEmpty) {
      final directResp = await _client.get(Uri.parse(chapterUrl), headers: _headers);
      if (directResp.statusCode == 200) {
        html = directResp.body;
      }
    }

    if (html.isEmpty) {
      throw Exception('Failed to load chapter content from $chapterUrl');
    }

    final doc = html_parser.parse(html);

    // Remove headers, navbars, category footers
    for (final bad in doc.querySelectorAll(
      'script, style, nav, table, .catlinks, #toc, .ws-header, .printfooter, .mw-jump-link',
    )) {
      bad.remove();
    }

    final List<String> paragraphs = [];
    final pElements = doc.querySelectorAll('p, div.poem');

    for (final p in pElements) {
      final t = p.text.trim();
      if (t.length >= 2) {
        paragraphs.add(t);
      }
    }

    if (paragraphs.isEmpty) {
      final container = doc.querySelector('#mw-content-text') ?? doc.body;
      if (container != null) {
        for (final line in container.text.split('\n')) {
          final t = line.trim();
          if (t.length >= 5) {
            paragraphs.add(t);
          }
        }
      }
    }

    final displayTitle = doc.querySelector('#header_title_text')?.text.trim() ?? pageTitle;

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: '${id}_${pageTitle.hashCode.abs()}',
      title: displayTitle,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }

  String _extractPageIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final curid = uri.queryParameters['curid'];
      if (curid != null && curid.isNotEmpty) {
        return curid;
      }
    } catch (_) {}
    return '';
  }

  String _extractPageTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.path.startsWith('/wiki/')) {
        return Uri.decodeComponent(uri.path.replaceFirst('/wiki/', '')).replaceAll('_', ' ');
      }
      final titleParam = uri.queryParameters['title'];
      if (titleParam != null && titleParam.isNotEmpty) {
        return Uri.decodeComponent(titleParam).replaceAll('_', ' ');
      }
    } catch (_) {}
    return url;
  }
}
