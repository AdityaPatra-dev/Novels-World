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

/// Bespoke Extractor for East of the Web (https://www.eastoftheweb.com).
/// Premier digital library of curated short stories and novellas spanning
/// literary fiction, romance, crime, science fiction, and fantasy.
class EastOfTheWebExtractor implements NovelSource {
  @override
  final String id = 'eastoftheweb';

  @override
  final String name = 'East of the Web';

  @override
  final String baseUrl = 'https://www.eastoftheweb.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 8000;

  late final http.Client _client;

  EastOfTheWebExtractor({http.Client? client}) {
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
        'Cloudflare challenge encountered on East of the Web. Open in WebView to solve.',
      );
    }

    return htmlBody;
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = Uri.encodeComponent(query);
    final targetUrl = '$baseUrl/short-stories/index.php?search=$cleanQuery&page=$page';
    final html = await _fetchHtml(targetUrl);
    return parseNovelList(html);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = page > 1
        ? '$baseUrl/short-stories/index.php?genre=all&page=$page'
        : '$baseUrl/short-stories/index.php?genre=all';
    final html = await _fetchHtml(targetUrl);
    return parseNovelList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return getPopular(page: page);
  }

  List<Novel> parseNovelList(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final novels = <Novel>[];
    final seenUrls = <String>{};

    final links = document.querySelectorAll('a[href*="UBooks"]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final storyUrl = _cleanUrl(href);
      if (seenUrls.contains(storyUrl)) continue;

      var title = a.text.trim();
      if (title.isEmpty) {
        // Maybe parent contains title
        title = a.parent?.text.trim() ?? '';
      }
      if (title.isEmpty) continue;

      seenUrls.add(storyUrl);

      novels.add(
        Novel(
          id: storyUrl,
          sourceId: id,
          title: title,
          sourceUrl: storyUrl,
          coverUrl: '$baseUrl/images/eotw-logo.png',
          genres: const ['Short Story', 'Literature'],
          status: 'Completed',
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
    final h1 = document.querySelector('h1');
    var title = h1?.text.trim() ?? '';
    if (title.isEmpty) {
      title = document.querySelector('title')?.text.split('|')[0].trim() ?? 'Untitled Story';
    }

    // Author
    var author = 'Unknown Author';
    final authorEl = document.querySelector('.field--name-field-author, .author, h2');
    if (authorEl != null && authorEl.text.trim().isNotEmpty && authorEl.text.trim() != 'Main navigation') {
      author = authorEl.text.trim();
    }

    // Description / excerpt
    var description = '';
    final firstP = document.querySelector('div.page-story-body p, article p');
    if (firstP != null) {
      description = firstP.text.trim();
    }

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      author: author,
      sourceUrl: novelUrl,
      coverUrl: '$baseUrl/images/eotw-logo.png',
      description: description,
      genres: const ['Short Story', 'Literature'],
      status: 'Completed',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final details = await getNovelDetails(novelUrl);
    final chapters = [
      Chapter(
        id: novelUrl,
        novelId: novelUrl,
        title: details.title,
        chapterNumber: 1.0,
        url: novelUrl,
      ),
    ];
    onBatchLoaded?.call(chapters);
    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final html = await _fetchHtml(chapterUrl);
    return parseChapterContent(chapterUrl, html);
  }

  ChapterContent parseChapterContent(String chapterUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final details = parseNovelDetails(chapterUrl, htmlContent);
    final chapterTitle = details.title;

    final container = document.querySelector('div.page-story-body') ??
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

    // Remove scripts, ads, navigation
    for (final el in container.querySelectorAll(
      'script, style, iframe, ins, header, nav, button, .block-story-left-links-block, .layout__region--second',
    )) {
      el.remove();
    }

    final pElements = container.querySelectorAll('p');
    final rawParagraphs = <String>[];

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      if (text.contains('View Comments') ||
          text.contains('Printable Version') ||
          text.contains('More Stories By This Author')) {
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
