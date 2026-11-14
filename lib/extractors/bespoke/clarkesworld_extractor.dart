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

/// Bespoke Extractor for Clarkesworld Magazine (https://clarkesworldmagazine.com).
/// Multi-Hugo & World Fantasy Award-winning monthly science fiction and fantasy
/// digest publishing world-class hard sci-fi, space opera, and speculative novellas.
class ClarkesworldExtractor implements NovelSource {
  @override
  final String id = 'clarkesworld';

  @override
  final String name = 'Clarkesworld';

  @override
  final String baseUrl = 'https://clarkesworldmagazine.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 2000;

  late final http.Client _client;

  ClarkesworldExtractor({http.Client? client}) {
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
        'Cloudflare challenge encountered on Clarkesworld. Open in WebView to solve.',
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
    return parseNovelList(html);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = page > 1
        ? '$baseUrl/category/text/page/$page/'
        : '$baseUrl/category/text/';
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

    final headers = document.querySelectorAll('h2 a');
    for (final a in headers) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final storyUrl = _cleanUrl(href);
      if (seenUrls.contains(storyUrl)) continue;

      // Ensure it is a story link e.g. /author_month_year/
      final path = Uri.parse(storyUrl).path;
      if (path == '/' || path.startsWith('/category/') || path.startsWith('/tag/') || path.startsWith('/author/')) {
        continue;
      }

      seenUrls.add(storyUrl);

      final title = a.text.trim();
      if (title.isEmpty) continue;

      // Extract author if available nearby
      var author = 'Unknown Author';
      final parent = a.parent?.parent;
      final authorEl = parent?.querySelector('.story-author, .author, .byline');
      if (authorEl != null) {
        author = authorEl.text.replaceAll('by ', '').trim();
      }

      novels.add(
        Novel(
          id: storyUrl,
          sourceId: id,
          title: title,
          author: author,
          sourceUrl: storyUrl,
          coverUrl: '$baseUrl/images/robot-head.png',
          genres: const ['Science Fiction', 'Speculative Fiction'],
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
    var title = '';
    final titleEl = document.querySelector('h1.story-title, h1.entry-title');
    if (titleEl != null && titleEl.text.trim().isNotEmpty && titleEl.text.trim() != 'ClarkesworlD') {
      title = titleEl.text.trim();
    } else {
      final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'];
      if (ogTitle != null && ogTitle.contains(' by ')) {
        title = ogTitle.split(' by ')[0].trim();
      } else {
        // Fallback from document title
        final docTitle = document.querySelector('title')?.text ?? '';
        if (docTitle.contains(' by ')) {
          title = docTitle.split(' by ')[0].trim();
        } else {
          title = docTitle.replaceAll(': Clarkesworld Magazine', '').trim();
        }
      }
    }
    if (title.isEmpty) title = 'Untitled Sci-Fi Story';

    // Author
    var author = 'Unknown Author';
    final authorEl = document.querySelector('p.story-author, .author, .byline');
    if (authorEl != null) {
      author = authorEl.text.replaceAll(RegExp(r'^by\s+', caseSensitive: false), '').trim();
    }

    // Description
    var description = '';
    final descEl = document.querySelector('p.story-description');
    if (descEl != null) {
      description = descEl.text.trim();
    } else {
      final firstP = document.querySelector('div.story-text p, div.entry-content p');
      if (firstP != null) {
        description = firstP.text.trim();
      }
    }

    // Cover
    final metaCover = document.querySelector('meta[property="og:image"]')?.attributes['content'];
    final coverUrl = metaCover != null && metaCover.isNotEmpty
        ? _cleanUrl(metaCover)
        : '$baseUrl/images/robot-head.png';

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      author: author,
      sourceUrl: novelUrl,
      coverUrl: coverUrl,
      description: description,
      genres: const ['Science Fiction', 'Speculative Fiction'],
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

    // Title
    final details = parseNovelDetails(chapterUrl, htmlContent);
    final chapterTitle = details.title;

    final container = document.querySelector('div.story-text') ??
        document.querySelector('div.entry-content') ??
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

    // Remove author bio, podcast links, advertisements, issue navigation
    for (final el in container.querySelectorAll(
      'script, style, iframe, ins, .author-bio, .author-profile, table, .audio-text, .story-description, .issue-heading, .story-author, header, nav, button',
    )) {
      el.remove();
    }

    final pElements = container.querySelectorAll('p');
    final rawParagraphs = <String>[];

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      // Skip Clarkesworld metadata paragraphs
      if (text.startsWith('AUDIO VERSION') ||
          text.contains('Purchase This Issue') ||
          text.contains('Wyrm Publishing')) {
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
