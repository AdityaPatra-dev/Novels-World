import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/services/webview_session_manager.dart';
import '../core/utils/text_cleaner.dart';
import 'novel_source.dart';

/// Generic Extractor for WordPress sites using the Fictioneer theme.
/// Powers web fiction sites such as NovelLib (novelib.com), Daoist Quest,
/// Lily on the Valley, Penguin Squad, etc.
class FictioneerExtractor implements NovelSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final String baseUrl;
  @override
  final String lang;
  @override
  final String iconUrl;
  @override
  final int estimatedNovelCount;

  late final http.Client _client;

  FictioneerExtractor({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lang = 'en',
    this.iconUrl = '',
    this.estimatedNovelCount = 10000,
    http.Client? client,
  }) {
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
      _client = IOClient(nativeHttpClient);
    }
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

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = Uri.encodeComponent(query);
    final targetUrl = page == 1
        ? '$baseUrl/?s=$cleanQuery'
        : '$baseUrl/page/$page/?s=$cleanQuery';

    try {
      final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        final list = parseNovelList(response.body);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(targetUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    return [];
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final candidates = [
      page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/',
      page == 1 ? '$baseUrl/stories/' : '$baseUrl/stories/page/$page/',
      page == 1 ? '$baseUrl/fictions/' : '$baseUrl/fictions/page/$page/',
    ];

    for (final url in candidates) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _headers);
        if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
          final list = parseNovelList(resp.body);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    final primaryUrl = page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load popular novels from $name. Please try another source or tap Open in WebView.');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return getPopular(page: page);
  }

  List<Novel> parseNovelList(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final List<Novel> list = [];
    final seenUrls = <String>{};

    final cards = document.querySelectorAll(
      '.custom-vertical-card, .fictioneer-slide-item, .story-card, article.story, .story-item',
    );

    for (final card in cards) {
      final linkEl = card.querySelector('a.title-link, .custom-story-title a, a.custom-cover-wrapper, a[href*="/story/"]');
      if (linkEl == null) continue;

      final href = _cleanUrl(linkEl.attributes['href'] ?? '');
      if (href.isEmpty || seenUrls.contains(href)) continue;

      String title = card.querySelector('.custom-story-title, .story-title, h3, h2')?.text.trim() ?? '';
      if (title.isEmpty) {
        title = linkEl.attributes['title']?.trim() ?? linkEl.text.trim();
      }
      if (title.isEmpty) continue;
      if (!TextCleaner.isValidNovelTitle(title, href)) continue;

      final imgEl = card.querySelector('img.custom-cover-image, img.story-cover, img');
      String coverUrl = '';
      if (imgEl != null) {
        coverUrl = imgEl.attributes['data-src'] ??
            imgEl.attributes['data-lazy-src'] ??
            imgEl.attributes['srcset']?.split(' ').first ??
            imgEl.attributes['src'] ??
            '';
        coverUrl = _cleanUrl(coverUrl);
        if (coverUrl.startsWith('data:') || coverUrl.contains('blank.gif')) {
          coverUrl = '';
        }
      }

      seenUrls.add(href);
      final uri = Uri.tryParse(href);
      final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      final slug = segments.isNotEmpty ? segments.last : href.hashCode.toString();
      final novelId = '${id}_$slug';

      list.add(Novel(
        id: novelId,
        sourceId: id,
        sourceUrl: href,
        title: title,
        coverUrl: coverUrl,
      ));
    }

    // Fallback: search for any /story/ links with covers if cards didn't match
    if (list.isEmpty) {
      final storyLinks = document.querySelectorAll('a[href*="/story/"]');
      for (final a in storyLinks) {
        final href = _cleanUrl(a.attributes['href'] ?? '');
        if (href.isEmpty || seenUrls.contains(href) || href.contains('/c') || href.contains('-c')) continue;

        final title = a.attributes['title']?.trim() ?? a.text.trim();
        if (title.isEmpty || title.length < 3 || title.toLowerCase().contains('chapter')) continue;
        if (!TextCleaner.isValidNovelTitle(title, href)) continue;

        seenUrls.add(href);
        final uri = Uri.tryParse(href);
        final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
        final slug = segments.isNotEmpty ? segments.last : href.hashCode.toString();

        list.add(Novel(
          id: '${id}_$slug',
          sourceId: id,
          sourceUrl: href,
          title: title,
          coverUrl: '',
        ));
      }
    }

    return list;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (TextCleaner.isGenreOrCategoryUrl(novelUrl)) {
      throw HttpException('Invalid novel URL: $novelUrl is a genre or category link.');
    }

    String body = '';
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        body = response.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
        body = wvHtml;
      }
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load novel details from $name for $novelUrl');
    }

    return parseNovelDetails(novelUrl, body);
  }

  Novel parseNovelDetails(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final title = document
            .querySelector('h1.story-title, h1, .story-header-title')
            ?.text
            .trim() ??
        'Unknown Novel';

    final imgEl = document.querySelector('img.story-cover, img.wp-post-image, .story-cover img, img');
    String coverUrl = '';
    if (imgEl != null) {
      coverUrl = imgEl.attributes['data-src'] ??
          imgEl.attributes['data-lazy-src'] ??
          imgEl.attributes['srcset']?.split(' ').first ??
          imgEl.attributes['src'] ??
          '';
      coverUrl = _cleanUrl(coverUrl);
      if (coverUrl.startsWith('data:') || coverUrl.contains('blank.gif')) {
        coverUrl = '';
      }
    }

    final author = document
            .querySelector('.story-author a, .story-author, .author a, .author')
            ?.text
            .trim() ??
        'Unknown Author';

    final synopsis = document
            .querySelector('.story-tab-content.active, .story-tab-content, .story-description, .description')
            ?.text
            .trim() ??
        '';

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final slug = segments.isNotEmpty ? segments.last : novelUrl.hashCode.toString();
    final novelId = '${id}_$slug';

    return Novel(
      id: novelId,
      sourceId: id,
      sourceUrl: novelUrl,
      title: title,
      author: author,
      coverUrl: coverUrl,
      description: synopsis,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    if (TextCleaner.isGenreOrCategoryUrl(novelUrl)) {
      throw HttpException('Invalid novel URL: $novelUrl is a genre or category link.');
    }

    String body = '';
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        body = response.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
        body = wvHtml;
      }
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load chapter list for $novelUrl');
    }

    return parseChapterList(novelUrl, body);
  }

  List<Chapter> parseChapterList(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final slug = segments.isNotEmpty ? segments.last : novelUrl.hashCode.toString();
    final novelId = '${id}_$slug';

    final List<Chapter> chapters = [];
    final seenChapterUrls = <String>{};
    final chapterLinks = document.querySelectorAll('a[href*="/story/"], .custom-chapter-item a, .chapter-list a');

    int index = 1;
    for (final a in chapterLinks) {
      final href = _cleanUrl(a.attributes['href'] ?? '');
      if (href.isEmpty || seenChapterUrls.contains(href)) continue;
      if (!href.startsWith(novelUrl) && !href.contains('-c') && !href.contains('/c')) continue;
      if (href == novelUrl || href == '$novelUrl/') continue;

      final chapterTitle = a.querySelector('.chapter-text')?.text.trim() ??
          a.text.trim();
      if (chapterTitle.isEmpty) continue;

      seenChapterUrls.add(href);
      chapters.add(Chapter(
        id: '${novelId}_c$index',
        novelId: novelId,
        title: chapterTitle,
        chapterNumber: index.toDouble(),
        url: href,
      ));
      index++;
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    String body = '';
    try {
      final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        body = response.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(chapterUrl);
      if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
        body = wvHtml;
      }
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load chapter content for $chapterUrl');
    }

    final document = html_parser.parse(body);
    final title = document
            .querySelector('h1.chapter-title, h1, .entry-title')
            ?.text
            .trim() ??
        '';

    final contentEl = document.querySelector('#chapter-content, article, .chapter-content, .entry-content');
    if (contentEl == null) {
      throw HttpException('Could not locate chapter content container');
    }

    for (final bad in contentEl.querySelectorAll('script, style, noscript, .ads, .ad, .fictioneer-buttons, .chapter-nav')) {
      bad.remove();
    }

    final paragraphs = contentEl
        .querySelectorAll('p')
        .map((p) => p.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final text = paragraphs.isNotEmpty
        ? paragraphs.join('\n\n')
        : contentEl.text.trim();

    final uri = Uri.tryParse(chapterUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final slug = segments.length >= 2 ? segments[segments.length - 2] : chapterUrl.hashCode.toString();
    final novelId = '${id}_$slug';

    return ChapterContent(
      chapterId: chapterUrl,
      novelId: novelId,
      title: title,
      rawText: text,
      paragraphs: paragraphs.isNotEmpty ? paragraphs : [text],
    );
  }
}
