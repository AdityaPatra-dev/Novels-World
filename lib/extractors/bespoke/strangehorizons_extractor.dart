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

/// Bespoke extractor for Strange Horizons (https://strangehorizons.com).
/// Renowned Hugo-nominated weekly speculative fiction magazine publishing cutting-edge
/// sci-fi, cyberpunk, sociological space opera, and contemporary fantasy since 2000.
class StrangeHorizonsExtractor implements NovelSource {
  @override
  final String id = 'strangehorizons';

  @override
  final String name = 'Strange Horizons';

  @override
  final String baseUrl = 'https://strangehorizons.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://strangehorizons.com/favicon.ico';

  @override
  final int estimatedNovelCount = 1500;

  late final http.Client _client;

  StrangeHorizonsExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': baseUrl,
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
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null && wvHtml.isNotEmpty) {
        htmlBody = wvHtml;
      }
    }

    if (htmlBody.isEmpty ||
        htmlBody.contains('Just a moment...') ||
        htmlBody.contains('challenge-running') ||
        htmlBody.contains('cf-chl-')) {
      throw const HttpException(
        'Cloudflare challenge encountered on Strange Horizons. Open in WebView to solve.',
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
        ? '$baseUrl/wordpress/fiction/page/$page/'
        : '$baseUrl/wordpress/fiction/';
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

    final links = document.querySelectorAll('a[href*="/fiction/"]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final storyUrl = _cleanUrl(href);
      if (seenUrls.contains(storyUrl)) continue;

      final uri = Uri.tryParse(storyUrl);
      final path = uri?.path ?? '';
      // Filter category indices and anchor links
      if (path == '/fiction/' ||
          path == '/wordpress/fiction/' ||
          storyUrl.contains('#') ||
          storyUrl.contains('/reprint/') ||
          storyUrl.contains('/page/')) {
        continue;
      }

      final title = a.text.trim();
      if (title.isEmpty ||
          title.toLowerCase() == 'read more' ||
          title.toLowerCase() == 'fiction' ||
          title.length < 3) {
        continue;
      }

      seenUrls.add(storyUrl);

      novels.add(
        Novel(
          id: storyUrl,
          sourceId: id,
          title: TextCleaner.cleanNovelTitle(title),
          sourceUrl: storyUrl,
          coverUrl: '$baseUrl/images/shlogo.png',
          genres: const ['Science Fiction', 'Speculative Fiction', 'Fantasy'],
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
    final h1 = document.querySelector('h1, .entry-title, .title');
    if (h1 != null) {
      title = h1.text.trim();
    }
    if (title.isEmpty) {
      final docTitle = document.querySelector('title')?.text.trim() ?? '';
      if (docTitle.isNotEmpty) {
        title = docTitle.replaceAll(RegExp(r'Strange Horizons\s*-\s*', caseSensitive: false), '');
      }
    }
    if (title.contains(' By ')) {
      title = title.split(' By ').first.trim();
    }
    title = TextCleaner.cleanNovelTitle(title);

    // Author
    var author = 'Unknown Author';
    final authorEl = document.querySelector('.author, .byline, .story-author, a[rel="author"]');
    if (authorEl != null) {
      author = authorEl.text.replaceAll(RegExp(r'^by\s+', caseSensitive: false), '').trim();
    } else {
      final docTitle = document.querySelector('title')?.text.trim() ?? '';
      if (docTitle.contains(' By ')) {
        author = docTitle.split(' By ').last.trim();
      }
    }

    // Description
    var description = '';
    final metaDesc = document.querySelector('meta[property="og:description"]')?.attributes['content'] ??
        document.querySelector('meta[name="description"]')?.attributes['content'];
    if (metaDesc != null && metaDesc.trim().isNotEmpty) {
      description = metaDesc.trim();
    } else {
      final firstP = document.querySelector('div.sizeable-content p');
      if (firstP != null) {
        description = firstP.text.trim();
      }
    }

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title.isNotEmpty ? title : 'Strange Horizons Story',
      author: author,
      sourceUrl: novelUrl,
      coverUrl: '$baseUrl/images/shlogo.png',
      description: description,
      genres: const ['Science Fiction', 'Speculative Fiction', 'Fantasy'],
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

    final titleEl = document.querySelector('h1, .entry-title, .title');
    var title = titleEl?.text.trim() ?? 'Story';
    if (title.contains(' By ')) {
      title = title.split(' By ').first.trim();
    }

    final container = document.querySelector('div.sizeable-content, div.entry-content, article');
    if (container == null) {
      throw Exception('Story narrative container not found on $chapterUrl');
    }

    // Strip ads, social buttons, scripts
    container
        .querySelectorAll('script, style, .sharedaddy, .author-bio, nav, .comments')
        .forEach((e) => e.remove());

    final pElements = container.querySelectorAll('p');
    final rawParagraphs = <String>[];

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      if (text.startsWith('Content warning:') || text.startsWith('This page contains:')) {
        continue;
      }
      rawParagraphs.add(text);
    }

    final cleanedParagraphs = TextCleaner.cleanParagraphs(rawParagraphs);
    final rawText = TextCleaner.toCleanRawText(cleanedParagraphs);

    return ChapterContent(
      chapterId: chapterUrl,
      novelId: chapterUrl,
      title: title,
      paragraphs: cleanedParagraphs,
      rawText: rawText,
    );
  }
}
