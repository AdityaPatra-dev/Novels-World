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

/// Generic Extractor for WordPress sites using the LightNovelWP theme (Themesia).
/// Powers 36+ popular webnovel sites such as Kol Novel, KnoxT, Light Novel FR,
/// AllNovelRead, Novels Paradise, Sakura Novel, etc.
class LightNovelWpExtractor implements NovelSource {
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

  LightNovelWpExtractor({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lang = 'en',
    this.iconUrl = '',
    this.estimatedNovelCount = 1000,
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
      page == 1 ? '$baseUrl/series/?order=popular' : '$baseUrl/series/page/$page/?order=popular',
      page == 1 ? '$baseUrl/novels/?order=popular' : '$baseUrl/novels/page/$page/?order=popular',
      page == 1 ? '$baseUrl/novel/?order=popular' : '$baseUrl/novel/page/$page/?order=popular',
      page == 1 ? '$baseUrl/series/' : '$baseUrl/series/page/$page/',
      page == 1 ? '$baseUrl/novels/' : '$baseUrl/novels/page/$page/',
      page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/',
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

    final primaryUrl = page == 1 ? '$baseUrl/series/?order=popular' : '$baseUrl/series/page/$page/?order=popular';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load popular novels from $name. Please try another source or tap Open in WebView.');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final candidates = [
      page == 1 ? '$baseUrl/series/?order=latest' : '$baseUrl/series/page/$page/?order=latest',
      page == 1 ? '$baseUrl/novels/?order=latest' : '$baseUrl/novels/page/$page/?order=latest',
      page == 1 ? '$baseUrl/series/' : '$baseUrl/series/page/$page/',
      page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/',
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

    final primaryUrl = page == 1 ? '$baseUrl/series/?order=latest' : '$baseUrl/series/page/$page/?order=latest';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load latest novels from $name. Please try another source or tap Open in WebView.');
  }

  List<Novel> parseNovelList(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final List<Novel> list = [];

    final elements = document.querySelectorAll(
      '.listupd .bsx, .listupdate .bsx, .listupd .bs, .bsx, article.bs, article.maindet, article.kol-series-archive__item, article[class*="archive__item"], article[class*="series"]',
    );

    for (final el in elements) {
      final linkEl = el.querySelector('h2 a, h3 a, h4 a, .tt a, .mdthumb a, .inmain a, a');
      if (linkEl == null) continue;

      final href = linkEl.attributes['href'] ?? '';
      if (href.isEmpty || TextCleaner.isGenreOrCategoryUrl(href)) continue;

      String title = el.querySelector('h2 a, h3 a, h4 a, h2, h3, h4, .tt, .bigor .tt, .title')?.text.trim() ?? '';
      final imgEl = el.querySelector('.mdthumb img, img');
      if (title.isEmpty) {
        title = linkEl.attributes['title']?.trim() ?? '';
      }
      if (title.isEmpty && imgEl != null) {
        title = imgEl.attributes['alt']?.trim() ?? '';
      }
      if (title.isEmpty) continue;
      if (!TextCleaner.isValidNovelTitle(title, href)) continue;
      String coverUrl = '';
      if (imgEl != null) {
        coverUrl = imgEl.attributes['data-src'] ??
            imgEl.attributes['data-lazy-src'] ??
            imgEl.attributes['data-original'] ??
            imgEl.attributes['srcset']?.split(' ').first ??
            imgEl.attributes['src'] ??
            '';
        coverUrl = _cleanUrl(coverUrl);
        if (coverUrl.startsWith('data:') || coverUrl.contains('blank.gif')) {
          coverUrl = '';
        }
      }

      final uri = Uri.tryParse(href);
      final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      final slug = segments.isNotEmpty ? segments.last : href.hashCode.toString();
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
      throw Exception('Failed to load novel details for $novelUrl');
    }
    return parseNovelDetails(novelUrl, body);
  }

  Novel parseNovelDetails(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final title = document.querySelector('h1.entry-title, .entry-title, .infox h1')?.text.trim() ?? 'Unknown Novel';

    final imgEl = document.querySelector('.thumbook .thumb img, .thumb img, .entry-details img');
    String coverUrl = '';
    if (imgEl != null) {
      coverUrl = imgEl.attributes['src'] ??
          imgEl.attributes['data-src'] ??
          imgEl.attributes['data-lazy-src'] ??
          '';
      coverUrl = _cleanUrl(coverUrl);
    }

    String author = 'Unknown Author';
    var speSpans = document.querySelectorAll('.infox .spe span, .spe span');
    if (speSpans.isEmpty) {
      speSpans = document.querySelectorAll('.infox .spe, .spe');
    }
    for (final el in speSpans) {
      if (el.text.toLowerCase().contains('author')) {
        final aTag = el.querySelector('a');
        if (aTag != null && aTag.text.trim().isNotEmpty) {
          author = aTag.text.trim();
        } else {
          // If this element contains b or strong tags for "Author:", extract remaining text
          final clone = el.clone(true);
          clone.querySelectorAll('b, strong').forEach((b) {
            if (b.text.toLowerCase().contains('author')) b.remove();
          });
          author = clone.text.replaceAll(RegExp(r'Author\s*:?', caseSensitive: false), '').trim();
        }
        break;
      }
    }

    String status = 'ONGOING';
    for (final el in speSpans) {
      if (el.text.toLowerCase().contains('status')) {
        final statusText = el.text.toUpperCase();
        if (statusText.contains('COMPLETE')) {
          status = 'COMPLETED';
        }
        break;
      }
    }
    final statusEl = document.querySelector('.ts-status, .status');
    if (statusEl != null && statusEl.text.toUpperCase().contains('COMPLETE')) {
      status = 'COMPLETED';
    }

    final genreEls = document.querySelectorAll('.genretags a, .mgen a, .genres a');
    final genres = genreEls.map((g) => g.text.trim()).where((g) => g.isNotEmpty).toList();

    final synopsisEl = document.querySelector(
      '.entry-content[itemprop="description"], .synopsis, .wd-full .entry-content, .entry-content',
    );
    String synopsis = '';
    if (synopsisEl != null) {
      synopsisEl.querySelectorAll('script, style, ins, .sharedaddy').forEach((e) => e.remove());
      synopsis = synopsisEl.text.trim();
    }

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
      description: synopsis,
      coverUrl: coverUrl,
      genres: genres,
      status: status,
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
      throw Exception('Failed to load chapter list: $novelUrl');
    }

    var chapters = parseChapterList(novelUrl, body);
    final seenUrls = chapters.map((c) => c.url).toSet();

    // Check for pagination links on LightNovelWP
    final doc = html_parser.parse(body);
    final pageLinks = doc.querySelectorAll('.pagination a, .page-numbers a, ul.pagination li a');
    for (final a in pageLinks) {
      final href = a.attributes['href'] ?? '';
      if (href.isNotEmpty) {
        final clean = _cleanUrl(href);
        if (clean != novelUrl) {
          try {
            final pResp = await _client.get(Uri.parse(clean), headers: _headers);
            if (pResp.statusCode == 200) {
              final pageChs = parseChapterList(novelUrl, pResp.body);
              for (final ch in pageChs) {
                if (!seenUrls.contains(ch.url)) {
                  seenUrls.add(ch.url);
                  chapters.add(ch);
                }
              }
            }
          } catch (_) {}
        }
      }
    }

    return chapters;
  }

  List<Chapter> parseChapterList(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final List<Chapter> chapters = [];

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final novelSlug = segments.isNotEmpty ? segments.last : novelUrl.hashCode.toString();
    final novelId = '${id}_$novelSlug';

    final chapterItems = document.querySelectorAll(
      '.eplister ul li, #chapterlist ul li, .bxcl ul li, ul.clstyle li',
    );

    int orderIndex = 0;
    for (final item in chapterItems) {
      final link = item.querySelector('a');
      if (link == null) continue;

      final href = link.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final numSpan = item.querySelector('.epl-num')?.text.trim() ?? '';
      final titleSpan = item.querySelector('.epl-title')?.text.trim() ?? '';
      final dateSpan = item.querySelector('.epl-date')?.text.trim() ?? '';

      String chapterTitle = '';
      if (numSpan.isNotEmpty && titleSpan.isNotEmpty) {
        chapterTitle = '$numSpan: $titleSpan';
      } else if (titleSpan.isNotEmpty) {
        chapterTitle = titleSpan;
      } else if (numSpan.isNotEmpty) {
        chapterTitle = numSpan;
      } else {
        chapterTitle = link.text.trim();
      }

      if (chapterTitle.isEmpty) {
        chapterTitle = 'Chapter ${chapters.length + 1}';
      }

      final chapterSlug = Uri.tryParse(href)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
          '${chapters.length + 1}';
      final chapterId = '${novelId}_$chapterSlug';

      double? chapterNumber;
      final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(numSpan.isNotEmpty ? numSpan : chapterTitle);
      if (numMatch != null) {
        chapterNumber = double.tryParse(numMatch.group(1)!);
      }

      chapters.add(Chapter(
        id: chapterId,
        novelId: novelId,
        url: _cleanUrl(href),
        title: chapterTitle,
        chapterNumber: chapterNumber ?? (orderIndex + 1.0),
        releaseDate: dateSpan.isNotEmpty ? dateSpan : null,
      ));
      orderIndex++;
    }

    if (chapters.length > 1) {
      final firstNum = chapters.first.chapterNumber ?? 0;
      final lastNum = chapters.last.chapterNumber ?? 0;
      if (firstNum > lastNum) {
        return chapters.reversed.toList();
      }
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
      throw Exception('Failed to load chapter content: $chapterUrl');
    }
    return parseChapterContent(chapterUrl, body);
  }

  ChapterContent parseChapterContent(String chapterUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final titleEl = document.querySelector('h1.entry-title, .entry-title, .epcontent h1');
    final title = titleEl?.text.trim() ?? 'Chapter';

    final container = document.querySelector('.epcontent.entry-content, .epcontent, .entry-content');
    if (container == null) {
      throw Exception('Chapter reading container (.epcontent) not found on $chapterUrl');
    }

    container
        .querySelectorAll(
          'script, style, ins, .sharedaddy, .adsbygoogle, .code-block, .ep-tags, .navigation, .nav-links, .social-share',
        )
        .forEach((e) => e.remove());

    final pElements = container.querySelectorAll('p');
    List<String> rawParagraphs = [];

    if (pElements.isNotEmpty) {
      rawParagraphs = pElements.map((p) => p.text).toList();
    } else {
      final innerHtml = container.innerHtml;
      rawParagraphs = innerHtml.split(RegExp(r'<br\s*/?>', caseSensitive: false));
    }

    final cleanedParagraphs = TextCleaner.cleanParagraphs(rawParagraphs);
    final rawText = TextCleaner.toCleanRawText(cleanedParagraphs);

    final chapterSlug = Uri.tryParse(chapterUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
        chapterUrl.hashCode.toString();

    return ChapterContent(
      chapterId: '${id}_$chapterSlug',
      novelId: '',
      title: title,
      rawText: rawText,
      paragraphs: cleanedParagraphs,
    );
  }
}
