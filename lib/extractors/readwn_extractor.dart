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

/// Generic Extractor for the ReadWN / WuxiaBox / EmpireCMS MTL novel network.
/// Powers WuxiaBox, FanMTL, WuxiaSpot, and sister high-speed webnovel portals.
class ReadWnExtractor implements NovelSource {
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

  ReadWnExtractor({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lang = 'en',
    this.iconUrl = '',
    this.estimatedNovelCount = 25000,
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
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
    final targetUrls = [
      '$baseUrl/search.html?keyword=$cleanQuery',
      '$baseUrl/search?keyword=$cleanQuery',
    ];

    for (final targetUrl in targetUrls) {
      try {
        final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
        if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
          final list = parseNovelList(response.body);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    // EmpireCMS POST Search Fallback (used by FanMTL and EmpireCMS networks)
    final postSearchUrl = '$baseUrl/e/search/index.php';
    try {
      final postResp = await _client.post(
        Uri.parse(postSearchUrl),
        headers: {
          ..._headers,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'show': 'title',
          'tempid': '1',
          'tbname': 'news',
          'keyboard': query,
        },
      );

      if (postResp.statusCode == 200 && postResp.body.isNotEmpty) {
        final list = parseNovelList(postResp.body);
        if (list.isNotEmpty) return list;
      } else if (postResp.statusCode == 302 && postResp.headers['location'] != null) {
        final loc = postResp.headers['location']!;
        final resolvedUrl = Uri.parse(postSearchUrl).resolve(loc);
        final locResp = await _client.get(resolvedUrl, headers: _headers);
        if (locResp.statusCode == 200) {
          final list = parseNovelList(locResp.body);
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}

    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(targetUrls.first);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    return [];
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final pageIndex = (page - 1) < 0 ? 0 : page - 1;
    final candidates = [
      '$baseUrl/list/all/all-onclick-$pageIndex.html',
      '$baseUrl/all-novels/?page=$page',
      '$baseUrl/novel-list/?page=$page',
      '$baseUrl/list/all/all-all-$pageIndex.html',
      '$baseUrl/',
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

    final primaryUrl = '$baseUrl/list/all/all-onclick-$pageIndex.html';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load popular novels from $name.');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final pageIndex = (page - 1) < 0 ? 0 : page - 1;
    final candidates = [
      '$baseUrl/list/all/all-lastupdate-$pageIndex.html',
      '$baseUrl/all-novels/?page=$page',
      '$baseUrl/novel-list/?page=$page',
      '$baseUrl/',
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

    final primaryUrl = '$baseUrl/list/all/all-lastupdate-$pageIndex.html';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load latest novels from $name.');
  }

  List<Novel> parseNovelList(String html) {
    final doc = html_parser.parse(html);
    final List<Novel> list = [];

    final items = doc.querySelectorAll('.content-list li, .item, li.list-item, div.media, .novel-item');
    for (final item in items) {
      final linkEl = item.querySelector('a.name, h4.media-heading a, .title a, a[title]');
      if (linkEl == null) continue;

      final href = linkEl.attributes['href'] ?? '';
      if (href.isEmpty || !href.contains('/novel/')) continue;

      String title = linkEl.text.trim();
      if (title.contains('\n')) {
        title = title.split('\n').first.trim();
      }
      if (title.isEmpty) continue;
      if (!TextCleaner.isValidNovelTitle(title, href)) continue;

      final imgEl = item.querySelector('img');
      String coverUrl = '';
      if (imgEl != null) {
        coverUrl = imgEl.attributes['data-src'] ??
            imgEl.attributes['data-original'] ??
            imgEl.attributes['src'] ??
            '';
        if (coverUrl.contains('placeholder') || coverUrl.contains('blank')) {
          coverUrl = imgEl.attributes['data-src'] ?? imgEl.attributes['data-original'] ?? '';
        }
        coverUrl = _cleanUrl(coverUrl);
        if (coverUrl.contains('placeholder') || coverUrl.startsWith('data:')) {
          coverUrl = '';
        }
      }

      final uri = Uri.tryParse(href);
      final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      final slug = segments.isNotEmpty ? segments.last.replaceAll('.html', '') : href.hashCode.toString();
      final novelId = '${id}_$slug';

      list.add(Novel(
        id: novelId,
        sourceId: id,
        sourceUrl: _cleanUrl(href),
        title: title,
        coverUrl: coverUrl,
      ));
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
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load details on $name');
    }
    return parseNovelDetails(novelUrl, body);
  }

  Novel parseNovelDetails(String novelUrl, String html) {
    final doc = html_parser.parse(html);
    final title = doc.querySelector('h1, .novel-title, .title')?.text.trim() ?? 'Unknown Novel';

    final authorEl = doc.querySelector('.author, span[itemprop="author"]');
    var author = authorEl?.text.replaceAll('Author:', '').replaceAll('\n', '').trim() ?? 'Unknown Author';

    final descEl = doc.querySelector('.desc, .description, .summary');
    final desc = descEl?.text.trim() ?? '';

    final imgEl = doc.querySelector('.cover img, .novel-cover img, .thumb img, img[itemprop="image"], img');
    String coverUrl = '';
    if (imgEl != null) {
      coverUrl = imgEl.attributes['data-src'] ??
          imgEl.attributes['data-original'] ??
          imgEl.attributes['src'] ??
          '';
      if (coverUrl.contains('placeholder') || coverUrl.contains('blank')) {
        coverUrl = imgEl.attributes['data-src'] ?? imgEl.attributes['data-original'] ?? '';
      }
      coverUrl = _cleanUrl(coverUrl);
      if (coverUrl.contains('placeholder') || coverUrl.startsWith('data:')) {
        coverUrl = '';
      }
    }

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final slug = segments.isNotEmpty ? segments.last.replaceAll('.html', '') : novelUrl.hashCode.toString();

    return Novel(
      id: '${id}_$slug',
      sourceId: id,
      sourceUrl: novelUrl,
      title: title,
      author: author,
      description: desc,
      coverUrl: coverUrl,
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
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load chapter list on $name');
    }

    var chapters = parseChapterList(novelUrl, body);
    final seenUrls = chapters.map((c) => c.url).toSet();

    // Check for pagination on ReadWn (e.g. .pagination a, #chpagedlist a, fy.php pages)
    final doc = html_parser.parse(body);
    final pageLinks = doc.querySelectorAll(
      '.pagination a, ul.pagination li a, .pages-container a, .page-item a, #chpagedlist a, .paging a, a[href*="fy.php"], a[href*="page="]',
    );
    final pageUrls = <String>[];

    for (final a in pageLinks) {
      final href = a.attributes['href'] ?? '';
      if (href.isNotEmpty) {
        final clean = _cleanUrl(href);
        if (clean != novelUrl && !pageUrls.contains(clean)) {
          pageUrls.add(clean);
        }
      }
    }

    // Follow discovered page URLs up to 60 pages
    for (final pUrl in pageUrls.take(60)) {
      try {
        final resp = await _client.get(Uri.parse(pUrl), headers: _headers);
        if (resp.statusCode == 200) {
          final pageChs = parseChapterList(novelUrl, resp.body);
          if (pageChs.isEmpty) continue;
          for (final ch in pageChs) {
            if (!seenUrls.contains(ch.url)) {
              seenUrls.add(ch.url);
              chapters.add(ch);
            }
          }
        }
      } catch (_) {
        break;
      }
    }

    for (int i = 0; i < chapters.length; i++) {
      if ((chapters[i].chapterNumber ?? 0) <= 0) {
        chapters[i] = chapters[i].copyWith(chapterNumber: (i + 1).toDouble());
      }
    }

    return chapters;
  }

  List<Chapter> parseChapterList(String novelUrl, String html) {
    final doc = html_parser.parse(html);
    final List<Chapter> chapters = [];

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final novelSlug = segments.isNotEmpty ? segments.last.replaceAll('.html', '') : novelUrl.hashCode.toString();
    final novelId = '${id}_$novelSlug';

    final links = doc.querySelectorAll(
      '.chapter-list a, .chapters a, ul.list a, a.chapter, ul.chapter-list li a, .novel-chapters a, ul li a[href*="/novel/"]',
    );
    int order = 0;
    for (final l in links) {
      final href = l.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      // Skip pagination links
      if (href.contains('fy.php') || href.contains('page=') || href == novelUrl || href.endsWith('/novel/')) {
        continue;
      }

      String title = l.text.trim();
      // Remove trailing relative timestamps like "1985 days ago", "12 hours ago"
      title = title.replaceAll(
        RegExp(r'\s*\d+\s*(?:days?|hours?|mins?|minutes?|months?|years?|secs?|seconds?)\s*ago.*$', caseSensitive: false),
        '',
      );
      if (title.contains('\n')) {
        title = title.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty && !s.contains('ago')).join(' - ');
      }
      title = title.trim();
      if (title.isEmpty) continue;

      final chSlug = Uri.tryParse(href)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull?.replaceAll('.html', '') ??
          '${chapters.length + 1}';

      double? chapterNum;
      final numMatch = RegExp(r'chapter\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(title);
      if (numMatch != null) {
        chapterNum = double.tryParse(numMatch.group(1)!);
      }

      chapters.add(Chapter(
        id: '${novelId}_$chSlug',
        novelId: novelId,
        title: title,
        url: _cleanUrl(href),
        chapterNumber: chapterNum ?? (order + 1.0),
      ));
      order++;
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
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load chapter content on $name');
    }
    return parseChapterContent(chapterUrl, body);
  }

  ChapterContent parseChapterContent(String chapterUrl, String html) {
    final doc = html_parser.parse(html);
    final container = doc.querySelector('.chapter-content, #content, .content, .reading-content');

    final title = doc.querySelector('h1, h2.chapter-title')?.text.trim() ?? 'Chapter';

    final List<String> rawParagraphs = [];
    if (container != null) {
      for (final p in container.querySelectorAll('p')) {
        final text = p.text.trim();
        if (text.isNotEmpty) {
          rawParagraphs.add(text);
        }
      }
    }
    final paragraphs = TextCleaner.cleanParagraphs(rawParagraphs);

    final raw = TextCleaner.toCleanRawText(paragraphs);
    return ChapterContent(
      chapterId: chapterUrl.hashCode.toString(),
      novelId: '',
      title: title,
      rawText: raw,
      paragraphs: paragraphs,
    );
  }
}

