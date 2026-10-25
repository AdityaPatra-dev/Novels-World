import 'dart:convert';
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

/// Generic Extractor for the NovelFull / NovelBin CMS family.
/// Powers high-traffic aggregator clones including NovelFull, NovelBin,
/// ReadNovelFull, LibRead, AllNovelFull, and NovelPing.
class NovelFullExtractor implements NovelSource {
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
  final String popularPath;
  final String latestPath;

  NovelFullExtractor({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lang = 'en',
    this.iconUrl = '',
    this.estimatedNovelCount = 20000,
    this.popularPath = '/most-popular',
    this.latestPath = '/latest-release-novel',
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
        ? '$baseUrl/search?keyword=$cleanQuery'
        : '$baseUrl/search?keyword=$cleanQuery&page=$page';

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
    final separator = popularPath.contains('?') ? '&' : '?';
    final candidates = [
      page == 1 ? '$baseUrl$popularPath' : '$baseUrl$popularPath${separator}page=$page',
      page == 1 ? '$baseUrl/sort/most-popular' : '$baseUrl/sort/most-popular?page=$page',
      page == 1 ? '$baseUrl/novel-list/most-popular-novel' : '$baseUrl/novel-list/most-popular-novel?page=$page',
      page == 1 ? '$baseUrl/most-popular' : '$baseUrl/most-popular?page=$page',
      page == 1 ? '$baseUrl/sort/popular' : '$baseUrl/sort/popular?page=$page',
      page == 1 ? '$baseUrl/hot-novel' : '$baseUrl/hot-novel?page=$page',
      page == 1 ? '$baseUrl/' : '$baseUrl/?page=$page',
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

    // Cloudflare / Headless WebView Fallback
    final primaryUrl = page == 1 ? '$baseUrl$popularPath' : '$baseUrl$popularPath${separator}page=$page';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load popular novels from $name. Please try another source or tap Open in WebView.');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final separator = latestPath.contains('?') ? '&' : '?';
    final candidates = [
      page == 1 ? '$baseUrl$latestPath' : '$baseUrl$latestPath${separator}page=$page',
      page == 1 ? '$baseUrl/sort/latest-release' : '$baseUrl/sort/latest-release?page=$page',
      page == 1 ? '$baseUrl/sort/latest' : '$baseUrl/sort/latest?page=$page',
      page == 1 ? '$baseUrl/novel-list/latest-release-novel' : '$baseUrl/novel-list/latest-release-novel?page=$page',
      page == 1 ? '$baseUrl/latest-release-novel' : '$baseUrl/latest-release-novel?page=$page',
      page == 1 ? '$baseUrl/sort/updates' : '$baseUrl/sort/updates?page=$page',
      page == 1 ? '$baseUrl/' : '$baseUrl/?page=$page',
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

    // Cloudflare / Headless WebView Fallback
    final primaryUrl = page == 1 ? '$baseUrl$latestPath' : '$baseUrl$latestPath${separator}page=$page';
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
    final seenUrls = <String>{};

    final rows = document.querySelectorAll(
      '.list-novel .row, .col-novel-main .row, .list-truyen .row, .list .row, .li-row, .ul-list1 .li-row, .novel-item, .novel-list li, .col-novel, .ul-list1 li, .item, .col-xs-4',
    );

    for (final row in rows) {
      var titleEl = row.querySelector(
        'h3.novel-title a, h4.novel-title a, h3.truyen-title a, h3.tit a, h3 a, h4 a, a.tit, .novel-title a',
      );
      titleEl ??= row.querySelector('a[href*="/novel/"], a[href*="/book/"], a[title]');
      if (titleEl == null) continue;

      final href = titleEl.attributes['href'] ?? '';
      if (href.isEmpty || TextCleaner.isGenreOrCategoryUrl(href)) continue;

      final cleanHref = _cleanUrl(href);
      if (seenUrls.contains(cleanHref)) continue;

      final title = (titleEl.attributes['title']?.isNotEmpty == true
              ? titleEl.attributes['title']!
              : titleEl.text)
          .trim();
      if (title.isEmpty) continue;
      if (!TextCleaner.isValidNovelTitle(title, cleanHref)) continue;

      final imgEl = row.querySelector('.cover, .pic img, figure img, .cover-badge-wrap img, .cover-wrap img, img');
      String coverUrl = '';
      if (imgEl != null) {
        coverUrl = imgEl.attributes['data-src'] ??
            imgEl.attributes['data-original'] ??
            imgEl.attributes['data-lazy-src'] ??
            imgEl.attributes['srcset']?.split(' ').first ??
            imgEl.attributes['src'] ??
            '';
        coverUrl = _cleanUrl(coverUrl);
        if (coverUrl.startsWith('data:') ||
            coverUrl.contains('blank.gif') ||
            coverUrl.contains('placeholder')) {
          coverUrl = '';
        }
      }

      final authorEl = row.querySelector('.author, span.author, .novel-author, a.novel');
      final author = authorEl?.text.trim() ?? 'Unknown Author';

      final uri = Uri.tryParse(cleanHref);
      final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      final slug = segments.isNotEmpty ? segments.last.replaceAll('.html', '') : cleanHref.hashCode.toString();
      final novelId = '${id}_$slug';

      seenUrls.add(cleanHref);
      list.add(Novel(
        id: novelId,
        sourceId: id,
        sourceUrl: cleanHref,
        title: title,
        author: author,
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
      if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
        body = wvHtml;
      }
    }

    if (body.isEmpty) {
      throw Exception('Failed to load novel details for $novelUrl');
    }

    return parseNovelDetails(novelUrl, body);
  }

  Novel parseNovelDetails(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    var title = document
            .querySelector('h1.novel-title, h3.title, h3.novel-title, .title, h1, .breadcrumb li.active')
            ?.text
            .trim() ??
        '';
    if (title.isEmpty || title.toLowerCase() == 'novel info' || title.toLowerCase() == 'novel') {
      title = document.querySelector('title')?.text.trim() ?? 'Unknown Novel';
    }

    final imgEl = document.querySelector(
      '.book img, .desc img, .col-info-desc img, .pic img, .novel-cover img, figure img',
    );
    String coverUrl = '';
    if (imgEl != null) {
      coverUrl = imgEl.attributes['data-src'] ??
          imgEl.attributes['data-original'] ??
          imgEl.attributes['src'] ??
          '';
      coverUrl = _cleanUrl(coverUrl);
    }

    String author = 'Unknown Author';
    final authorLink = document.querySelector('.info a[href*="author"], .info a[href*="tac-gia"], .author a');
    if (authorLink != null) {
      author = authorLink.text.trim();
    } else {
      final infoDivs = document.querySelectorAll('.info > div, .meta-item, .item');
      for (final div in infoDivs) {
        if (div.text.toLowerCase().contains('author')) {
          author = div.text.replaceAll(RegExp(r'Author\s*:?', caseSensitive: false), '').trim();
          break;
        }
      }
    }

    String status = 'ONGOING';
    final statusLink = document.querySelector('.info a[href*="status"], .info a[href*="the-loai"]');
    if (statusLink != null) {
      final st = statusLink.text.toUpperCase();
      if (st.contains('COMPLETE')) {
        status = 'COMPLETED';
      }
    }

    final genreLinks = document.querySelectorAll('.info a[href*="genre"], .info a[href*="the-loai"]');
    final genres = genreLinks.map((g) => g.text.trim()).where((g) => g.isNotEmpty).toSet().toList();

    final descEl = document.querySelector(
      '.desc-text, div[itemprop="description"], .desc, .inner, .summary, #tab-description',
    );
    String description = '';
    if (descEl != null) {
      descEl.querySelectorAll('script, style, ins, .adsbygoogle').forEach((e) => e.remove());
      description = descEl.text.trim();
    }

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final slug = segments.isNotEmpty ? segments.last.replaceAll('.html', '') : novelUrl.hashCode.toString();
    final novelId = '${id}_$slug';

    return Novel(
      id: novelId,
      sourceId: id,
      sourceUrl: novelUrl,
      title: title,
      author: author,
      description: description,
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

    final document = html_parser.parse(body);

    final ratingEl = document.querySelector('#rating, div[data-novel-id], input#novelId, #novel_id, input[name="novel_id"]');
    final ajaxNovelId = ratingEl?.attributes['data-novel-id'] ?? ratingEl?.attributes['value'];

    var chapters = parseChapterList(novelUrl, body);
    final seenUrls = chapters.map((c) => c.url).toSet();

    // 1. If ajaxNovelId is present, ALWAYS query /ajax/chapter-archive?novelId=$ajaxNovelId
    // Because static page only has 50 chapters, while ajax contains ALL chapters!
    if (ajaxNovelId != null && ajaxNovelId.isNotEmpty) {
      final ajaxUrl = '$baseUrl/ajax/chapter-archive?novelId=$ajaxNovelId';
      try {
        final ajaxResp = await _client.get(Uri.parse(ajaxUrl), headers: _headers);
        if (ajaxResp.statusCode == 200 && ajaxResp.body.isNotEmpty) {
          final ajaxChapters = parseChapterList(novelUrl, ajaxResp.body);
          if (ajaxChapters.length > chapters.length) {
            chapters = ajaxChapters;
            seenUrls.addAll(chapters.map((c) => c.url));
          }
        }
      } catch (_) {}
    }

    // 2. Support /book/<slug>/chapters dedicated chapter list page (e.g. NovelFire)
    // AND multi-page chapter pagination across NovelFire (?page=2, ?page=3, etc.)!
    final chaptersUrl = novelUrl.endsWith('/chapters')
        ? novelUrl
        : (novelUrl.endsWith('/') ? '${novelUrl}chapters' : '$novelUrl/chapters');
    try {
      final resp = await _client.get(Uri.parse(chaptersUrl), headers: _headers);
      if (resp.statusCode == 200) {
        final page1Chs = parseChapterList(novelUrl, resp.body);
        if (page1Chs.isNotEmpty) {
          for (final c in page1Chs) {
            if (!seenUrls.contains(c.url)) {
              seenUrls.add(c.url);
              chapters.add(c);
            }
          }

          // Check pagination on the dedicated chapters page
          final chaptersDoc = html_parser.parse(resp.body);
          int maxChapterPage = 1;
          final pagLinks = chaptersDoc.querySelectorAll(
            '.pagenav a, .pagination-container a, .pagination a, ul.pagination li a, a[href*="page="]',
          );
          for (final a in pagLinks) {
            final href = a.attributes['href'] ?? '';
            final m = RegExp(r'page=(\d+)').firstMatch(href);
            if (m != null) {
              final p = int.tryParse(m.group(1)!);
              if (p != null && p > maxChapterPage) maxChapterPage = p;
            }
            final text = a.text.trim();
            final pText = int.tryParse(text);
            if (pText != null && pText > maxChapterPage) maxChapterPage = pText;
          }

          // Fetch subsequent pages up to maxChapterPage (or up to 60 pages / 6,000 chapters)
          for (int p = 2; p <= maxChapterPage && p <= 60; p++) {
            final pageUrl = '$chaptersUrl?page=$p';
            try {
              final pResp = await _client.get(Uri.parse(pageUrl), headers: _headers);
              if (pResp.statusCode == 200) {
                final pChs = parseChapterList(novelUrl, pResp.body);
                if (pChs.isEmpty) break;
                for (final c in pChs) {
                  if (!seenUrls.contains(c.url)) {
                    seenUrls.add(c.url);
                    chapters.add(c);
                  }
                }
              } else {
                break;
              }
            } catch (_) {
              break;
            }
          }
        }
      }
    } catch (_) {}

    // 3. Support FreeWebNovel & LibRead AJAX pagination (?ajax=chapters&page=N&pageSize=100)
    final indexListPage = document.querySelector('#indexListPage, [data-total-page]');
    final totalPages = int.tryParse(indexListPage?.attributes['data-total-page'] ?? '');
    if (totalPages != null && totalPages > 1) {
      for (int p = 2; p <= totalPages && p <= 60; p++) {
        final ajaxUrl = novelUrl.contains('?')
            ? '$novelUrl&ajax=chapters&page=$p&pageSize=100'
            : '$novelUrl?ajax=chapters&page=$p&pageSize=100';
        try {
          final ajaxResp = await _client.get(Uri.parse(ajaxUrl), headers: _headers);
          if (ajaxResp.statusCode == 200) {
            try {
              final data = json.decode(ajaxResp.body);
              if (data is Map && data['html'] != null) {
                final pChs = parseChapterList(novelUrl, data['html'].toString());
                for (final c in pChs) {
                  if (!seenUrls.contains(c.url)) {
                    seenUrls.add(c.url);
                    chapters.add(c);
                  }
                }
              }
            } catch (_) {
              final pChs = parseChapterList(novelUrl, ajaxResp.body);
              for (final c in pChs) {
                if (!seenUrls.contains(c.url)) {
                  seenUrls.add(c.url);
                  chapters.add(c);
                }
              }
            }
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
    }

    // 4. Follow pagination if present on NovelFull / NovelBin clones
    final paginationLinks = document.querySelectorAll(
      '.pagination a, ul.pagination li a, #pagination a, .pagenav a, .page-item a',
    );
    if (paginationLinks.isNotEmpty) {
      int maxPage = 1;
      for (final a in paginationLinks) {
        final text = a.text.trim();
        final p = int.tryParse(text);
        if (p != null && p > maxPage) maxPage = p;
        final href = a.attributes['href'] ?? '';
        final pageMatch = RegExp(r'page=(\d+)').firstMatch(href);
        if (pageMatch != null) {
          final pMatch = int.tryParse(pageMatch.group(1)!);
          if (pMatch != null && pMatch > maxPage) maxPage = pMatch;
        }
      }

      if (maxPage > 1) {
        // Fetch remaining pages (up to 60 pages / 6,000 chapters)
        for (int p = 2; p <= maxPage && p <= 60; p++) {
          final sep = novelUrl.contains('?') ? '&' : '?';
          final pUrl = '$novelUrl${sep}page=$p';
          try {
            final pResp = await _client.get(Uri.parse(pUrl), headers: _headers);
            if (pResp.statusCode == 200) {
              final pageChs = parseChapterList(novelUrl, pResp.body);
              if (pageChs.isEmpty) break;
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
      }
    }

    // Ensure chapter numbering is contiguous if missing or defaulting
    for (int i = 0; i < chapters.length; i++) {
      if ((chapters[i].chapterNumber ?? 0) <= 0) {
        chapters[i] = chapters[i].copyWith(chapterNumber: (i + 1).toDouble());
      }
    }

    return chapters;
  }

  List<Chapter> parseChapterList(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final List<Chapter> chapters = [];

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final novelSlug = segments.isNotEmpty ? segments.last.replaceAll('.html', '') : novelUrl.hashCode.toString();
    final novelId = '${id}_$novelSlug';

    final links = document.querySelectorAll(
      'ul.list-chapter li a, #list-chapter li a, .panel-body ul li a, .list-chapter a, ul.ul-list5 li a, .ul-list5 li a, .ul-list3 li a, ul.chapter-list li a, .chapter-list a',
    );

    int orderIndex = 0;
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final title = link.attributes['title']?.trim() ?? link.text.trim();
      if (title.isEmpty) continue;

      final chapterSlug = Uri.tryParse(href)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull?.replaceAll('.html', '') ??
          '${chapters.length + 1}';
      final chapterId = '${novelId}_$chapterSlug';

      double? chapterNumber;
      final numMatch = RegExp(r'chapter\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(title);
      if (numMatch != null) {
        chapterNumber = double.tryParse(numMatch.group(1)!);
      }

      chapters.add(Chapter(
        id: chapterId,
        novelId: novelId,
        url: _cleanUrl(href),
        title: title,
        chapterNumber: chapterNumber ?? (orderIndex + 1.0),
      ));
      orderIndex++;
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

    final titleEl = document.querySelector('.chr-title, .chapter-title, h2.chapter-title, h1');
    final title = titleEl?.text.trim() ?? 'Chapter';

    final container = document.querySelector(
      '#chr-content, #chapter-content, .chr-content, .chapter-c, #article, .txt, #content, .content, .reading-content',
    );
    if (container == null) {
      throw Exception('Chapter reading container not found on $chapterUrl');
    }

    container
        .querySelectorAll(
          'script, style, ins, .ads, .ads-holder, div[align="center"], .watermark, .alert',
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

    final chapterSlug = Uri.tryParse(chapterUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull?.replaceAll('.html', '') ??
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


