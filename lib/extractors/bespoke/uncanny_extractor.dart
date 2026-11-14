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

/// Bespoke Extractor for Uncanny Magazine (https://www.uncannymagazine.com).
/// Multiple Hugo Award-winning online science fiction and fantasy magazine
/// publishing stories, poems, and essays.
class UncannyExtractor implements NovelSource {
  @override
  final String id = 'uncannymagazine';

  @override
  final String name = 'Uncanny Magazine';

  @override
  final String baseUrl = 'https://www.uncannymagazine.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 1800;

  late final http.Client _client;

  UncannyExtractor({http.Client? client}) {
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
        'Cloudflare challenge encountered on Uncanny Magazine. Open in WebView to solve.',
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
        ? '$baseUrl/type/fiction/page/$page/'
        : '$baseUrl/type/fiction/';
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

    final links = document.querySelectorAll('h2.entry-title a, article a[href*="/article/"]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final storyUrl = _cleanUrl(href);
      if (seenUrls.contains(storyUrl)) continue;

      final path = Uri.parse(storyUrl).path;
      if (!path.startsWith('/article/')) {
        continue;
      }

      seenUrls.add(storyUrl);

      final title = a.text.trim();
      if (title.isEmpty) continue;

      novels.add(
        Novel(
          id: storyUrl,
          sourceId: id,
          title: title,
          sourceUrl: storyUrl,
          coverUrl: '$baseUrl/wp-content/themes/uncanny/images/logo.png',
          genres: const ['Science Fiction', 'Fantasy', 'Speculative Fiction'],
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
    final titleEl = document.querySelector('h2.entry-title, h1.entry-title, h1');
    var title = titleEl?.text.trim() ?? '';
    if (title.isEmpty) {
      final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'];
      title = ogTitle?.replaceAll('- Uncanny Magazine', '').trim() ?? 'Untitled Story';
    }

    // Cover
    final metaCover = document.querySelector('meta[property="og:image"]')?.attributes['content'];
    final coverUrl = metaCover != null && metaCover.isNotEmpty
        ? _cleanUrl(metaCover)
        : '$baseUrl/wp-content/themes/uncanny/images/logo.png';

    // Author
    var author = 'Unknown Author';
    final h2s = document.querySelectorAll('h2');
    for (final h2 in h2s) {
      if (h2.classes.contains('entry-title') || h2.classes.contains('site_description')) {
        continue;
      }
      final text = h2.text.trim();
      if (text.isNotEmpty && !text.toLowerCase().contains('podcast') && !text.toLowerCase().contains('issue')) {
        author = text;
        break;
      }
    }

    // Description
    var description = '';
    final metaDesc = document.querySelector('meta[property="og:description"]')?.attributes['content'] ??
        document.querySelector('meta[name="description"]')?.attributes['content'];
    if (metaDesc != null && metaDesc.trim().isNotEmpty) {
      description = metaDesc.trim();
    } else {
      final firstP = document.querySelector('.entry-content p');
      if (firstP != null) {
        description = firstP.text.trim();
      }
    }

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      author: author,
      sourceUrl: novelUrl,
      coverUrl: coverUrl,
      description: description,
      genres: const ['Science Fiction', 'Fantasy', 'Speculative Fiction'],
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

    final container = document.querySelector('div.entry-content') ??
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

    // Clean podcast links, buy links, comments, scripts
    for (final el in container.querySelectorAll(
      'script, style, iframe, ins, .sharedaddy, .sd-sharing-enabled, .author-bio, header, nav, button, .section_header',
    )) {
      el.remove();
    }

    final pElements = container.querySelectorAll('p');
    final rawParagraphs = <String>[];

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      if (text.toLowerCase().contains('listen to the podcast') ||
          text.toLowerCase().contains('buy this issue') ||
          text.toLowerCase().contains('support uncanny')) {
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
