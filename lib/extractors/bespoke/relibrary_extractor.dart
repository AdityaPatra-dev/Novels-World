import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke Extractor for Re:Library (https://re-library.com).
/// High quality translation collective specializing in Japanese Light Novels,
/// Gender Bender, Yuri, and Fantasy with pristine typography.
class ReLibraryExtractor implements NovelSource {
  @override
  final String id = 'relibrary';

  @override
  final String name = 'Re:Library';

  @override
  final String baseUrl = 'https://re-library.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 12000;

  late final http.Client _client;

  ReLibraryExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': '$baseUrl/',
    };
    final cookie = WebViewSessionManager.instance.getCookieHeader(baseUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  String _cleanUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    } else if (url.startsWith('/')) {
      return '$baseUrl$url';
    }
    return url;
  }

  Future<String> _fetchHtml(String url) async {
    String htmlBody = '';
    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200 &&
          !response.body.contains('Just a moment...') &&
          !response.body.contains('challenge-running') &&
          !response.body.contains('cf-chl-')) {
        htmlBody = response.body;
      }
    } catch (_) {}

    if (htmlBody.isEmpty) {
      final wvHtml =
          await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null && wvHtml.isNotEmpty) {
        htmlBody = wvHtml;
      }
    }

    if (htmlBody.isEmpty ||
        htmlBody.contains('Just a moment...') ||
        htmlBody.contains('challenge-running') ||
        htmlBody.contains('cf-chl-')) {
      throw const HttpException(
        'Cloudflare challenge encountered on Re:Library. Open in WebView to solve.',
      );
    }

    return htmlBody;
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = Uri.encodeComponent(query);
    final targetUrl = page > 1
        ? '$baseUrl/page/$page/?s=$cleanQuery'
        : '$baseUrl/?s=$cleanQuery';
    final html = await _fetchHtml(targetUrl);
    return parseSearchResults(html);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = '$baseUrl/translations/';
    final html = await _fetchHtml(targetUrl);
    return parseNovelList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final targetUrl = '$baseUrl/translations/';
    final html = await _fetchHtml(targetUrl);
    return parseNovelList(html);
  }

  List<Novel> parseNovelList(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final novels = <Novel>[];
    final seenUrls = <String>{};

    final items = document.querySelectorAll('article.repi-item, .repi-item');
    for (final item in items) {
      final a = item.querySelector('a[href*="/translations/"]');
      if (a == null) continue;

      final href = a.attributes['href'];
      if (href == null || href.isEmpty || href == '$baseUrl/translations/' || href.endsWith('/translations/')) {
        continue;
      }

      final novelUrl = _cleanUrl(href);
      if (seenUrls.contains(novelUrl)) continue;
      seenUrls.add(novelUrl);

      final title = a.text.trim();
      if (title.isEmpty) continue;

      final img = item.querySelector('img');
      final coverUrl = _cleanUrl(img?.attributes['src'] ?? img?.attributes['data-src'] ?? '');

      novels.add(
        Novel(
          id: novelUrl,
          sourceId: id,
          title: title,
          sourceUrl: novelUrl,
          coverUrl: coverUrl,
        ),
      );
    }

    // Fallback: If no repi-item found, parse all series links inside .entry-content
    if (novels.isEmpty) {
      final links = document.querySelectorAll('.entry-content a[href*="/translations/"]');
      for (final a in links) {
        final href = a.attributes['href'] ?? '';
        final segments = Uri.parse(href).pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.length == 2 && segments[0] == 'translations') {
          final novelUrl = _cleanUrl(href);
          if (seenUrls.contains(novelUrl)) continue;
          seenUrls.add(novelUrl);
          final title = a.text.trim();
          if (title.isNotEmpty) {
            novels.add(
              Novel(
                id: novelUrl,
                sourceId: id,
                title: title,
                sourceUrl: novelUrl,
              ),
            );
          }
        }
      }
    }

    return novels;
  }

  List<Novel> parseSearchResults(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final novels = <Novel>[];
    final seenUrls = <String>{};

    final articles = document.querySelectorAll('article, .post, .entry');
    for (final article in articles) {
      final a = article.querySelector('h2 a, .entry-title a, a[rel="bookmark"]');
      if (a == null) continue;

      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final novelUrl = _cleanUrl(href);
      if (seenUrls.contains(novelUrl)) continue;
      seenUrls.add(novelUrl);

      final title = a.text.trim();
      if (title.isEmpty) continue;

      final img = article.querySelector('img');
      final coverUrl = _cleanUrl(img?.attributes['src'] ?? img?.attributes['data-src'] ?? '');

      novels.add(
        Novel(
          id: novelUrl,
          sourceId: id,
          title: title,
          sourceUrl: novelUrl,
          coverUrl: coverUrl,
        ),
      );
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    return parseNovelDetails(novelUrl, html);
  }

  Novel parseNovelDetails(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    // Title
    final h1 = document.querySelector('h1.entry-title, h1');
    var title = h1?.text.trim() ?? '';
    if (title.isEmpty || title == 'Re:Library') {
      final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'];
      title = ogTitle?.replaceAll('- Re:Library', '').trim() ?? 'Unknown Light Novel';
    }

    // Cover
    final metaCover = document.querySelector('meta[property="og:image"]')?.attributes['content'];
    final imgEl = document.querySelector('.entry-content img, .post-thumbnail img, .featured-image img');
    final rawCover = metaCover ?? imgEl?.attributes['src'] ?? '';
    final coverUrl = _cleanUrl(rawCover);

    // Description & Genres
    var description = '';
    final genres = <String>[];

    final descP = document.querySelectorAll('.entry-content p');
    final descLines = <String>[];
    for (final p in descP) {
      final text = p.text.trim();
      if (text.startsWith('Author:') || text.startsWith('Translator:') || text.startsWith('Editor:')) {
        continue;
      }
      if (text.contains('Project GB') || text.contains('Unlock Early Access') || text.contains('Support Us')) {
        continue;
      }
      if (p.querySelector('a[href*="/chapter"]') != null) {
        break; // Reached chapter list
      }
      if (text.isNotEmpty) {
        descLines.add(text);
      }
    }
    description = descLines.join('\n\n');

    // Author
    var author = 'Unknown Author';
    for (final p in descP) {
      final t = p.text.trim();
      if (t.toLowerCase().startsWith('author:')) {
        author = t.substring(7).trim();
        break;
      }
    }

    // Tags & categories
    for (final tag in document.querySelectorAll('a[rel="tag"], a[href*="/tag/"], a[href*="/category/"]')) {
      final g = tag.text.trim();
      if (g.isNotEmpty && !genres.contains(g) && !g.toLowerCase().contains('translation')) {
        genres.add(g);
      }
    }

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      sourceUrl: novelUrl,
      coverUrl: coverUrl,
      author: author,
      description: description,
      genres: genres,
      status: 'Ongoing',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final html = await _fetchHtml(novelUrl);
    final chapters = parseChapterList(novelUrl, html);
    if (chapters.isNotEmpty) onBatchLoaded?.call(chapters);
    return chapters;
  }

  List<Chapter> parseChapterList(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final chapters = <Chapter>[];
    final seenUrls = <String>{};

    final cleanNovelUrl = _cleanUrl(novelUrl);
    final novelPath = Uri.parse(cleanNovelUrl).path;

    final links = document.querySelectorAll('.entry-content a[href]');
    for (final a in links) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final chUrl = _cleanUrl(href);
      if (chUrl == cleanNovelUrl || seenUrls.contains(chUrl)) continue;

      // Ensure it's a chapter under this novel
      if (!chUrl.startsWith(cleanNovelUrl) && !chUrl.contains(novelPath)) {
        continue;
      }

      // Filter out share/social/anchor links
      if (chUrl.contains('share=') || chUrl.contains('#') || chUrl.contains('novelupdates')) {
        continue;
      }

      var title = a.text.trim();
      if (title.isEmpty) continue;

      // Filter out non-chapter links like Index, Support Us
      if (title.toLowerCase().contains('index') ||
          title.toLowerCase().contains('support') ||
          title.toLowerCase().contains('share')) {
        continue;
      }

      seenUrls.add(chUrl);

      final chNumMatch = RegExp(r'chapter\s+(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(title);
      final chNumber = chNumMatch != null ? double.tryParse(chNumMatch.group(1)!) : null;

      chapters.add(
        Chapter(
          id: chUrl,
          novelId: novelUrl,
          title: title,
          chapterNumber: chNumber,
          url: chUrl,
        ),
      );
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final html = await _fetchHtml(chapterUrl);
    return parseChapterContent(chapterUrl, html);
  }

  ChapterContent parseChapterContent(String chapterUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    // Title
    final h1 = document.querySelector('h1.entry-title, h1');
    var chapterTitle = h1?.text.trim() ?? 'Chapter';

    // Content container
    final container = document.querySelector('.entry-content') ??
        document.querySelector('article') ??
        document.body;

    if (container == null) {
      return ChapterContent(
        chapterId: chapterUrl,
        novelId: chapterUrl,
        title: chapterTitle,
        rawText: '',
        paragraphs: const [],
      );
    }

    // Clean scripts, ads, share widgets
    for (final el in container.querySelectorAll('script, style, iframe, ins, .sharedaddy, .sd-sharing-enabled, .wpcnt, header, nav, button')) {
      el.remove();
    }

    final pElements = container.querySelectorAll('p');
    final rawParagraphs = <String>[];

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;

      // Skip nav / author meta / comment markers
      if (text.contains('Leave a comment') ||
          text.contains('Next ⇒') ||
          text.contains('⌈ Index ⌋') ||
          text.contains('Support Us') ||
          text.contains('Unlock Early Access') ||
          text.contains('Share this:') ||
          text.toLowerCase().startsWith('translator:') ||
          text.toLowerCase().startsWith('editor:')) {
        continue;
      }

      rawParagraphs.add(text);
    }

    final cleanedParagraphs = TextCleaner.cleanParagraphs(rawParagraphs);

    return ChapterContent(
      chapterId: chapterUrl,
      novelId: chapterUrl,
      title: chapterTitle,
      rawText: cleanedParagraphs.join('\n\n'),
      paragraphs: cleanedParagraphs,
    );
  }
}
