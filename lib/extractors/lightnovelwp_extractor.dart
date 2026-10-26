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
    final primaryUrl = page == 1 ? '$baseUrl/series/?order=popular' : '$baseUrl/series/page/$page/?order=popular';

    // 1. Try primary URL via standard client
    try {
      final resp = await _client.get(Uri.parse(primaryUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        final list = parseNovelList(resp.body);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 2. Try primary URL via curl
    try {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
      if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
        final list = parseNovelList(wvHtml);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 3. Try RSS Feed (universally accessible and bypasses Cloudflare challenge pages)
    try {
      String xml = '';
      try {
        final feedResp = await _client.get(Uri.parse('$baseUrl/feed/'), headers: {
          'Accept': 'application/rss+xml, application/xml, text/xml',
          ..._headers,
        });
        if (feedResp.statusCode == 200 && feedResp.body.contains('<rss')) {
          xml = feedResp.body;
        }
      } catch (_) {}

      if (xml.isEmpty || !xml.contains('<rss')) {
        final wvXml = await WebViewSessionManager.instance.fetchHtmlViaWebView('$baseUrl/feed/');
        if (wvXml != null && wvXml.contains('<rss')) {
          xml = wvXml;
        }
      }

      if (xml.contains('<rss')) {
        final list = _parseRssFeed(xml);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 4. Try WP REST API fallback
    try {
      final wpApiStr = '$baseUrl/wp-json/wp/v2/categories?per_page=20&page=$page&orderby=count&order=desc';
      String jsonStr = '';
      try {
        final resp = await _client.get(Uri.parse(wpApiStr), headers: {
          'Accept': 'application/json',
          ..._headers,
        });
        if (resp.statusCode == 200 && !resp.body.contains('<!DOCTYPE html>')) {
          jsonStr = resp.body;
        }
      } catch (_) {}

      if (jsonStr.isEmpty) {
        final wvJson = await WebViewSessionManager.instance.fetchHtmlViaWebView(wpApiStr);
        if (wvJson != null && !wvJson.contains('<!DOCTYPE html>')) {
          jsonStr = wvJson;
        }
      }

      if (jsonStr.isNotEmpty) {
        final list = _parseWpCategories(jsonStr);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 5. Try alternative candidate URLs
    final otherCandidates = [
      page == 1 ? '$baseUrl/novels/?order=popular' : '$baseUrl/novels/page/$page/?order=popular',
      page == 1 ? '$baseUrl/novel/?order=popular' : '$baseUrl/novel/page/$page/?order=popular',
      page == 1 ? '$baseUrl/series/' : '$baseUrl/series/page/$page/',
      page == 1 ? '$baseUrl/novels/' : '$baseUrl/novels/page/$page/',
      page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/',
    ];

    for (final url in otherCandidates) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _headers);
        if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
          final list = parseNovelList(resp.body);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    throw HttpException('Could not load popular novels from $name. Please try another source or tap Open in WebView.');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final primaryUrl = page == 1 ? '$baseUrl/series/?order=latest' : '$baseUrl/series/page/$page/?order=latest';

    // 1. Try primary URL via standard client
    try {
      final resp = await _client.get(Uri.parse(primaryUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        final list = parseNovelList(resp.body);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 2. Try primary URL via curl
    try {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
      if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
        final list = parseNovelList(wvHtml);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 3. Try RSS Feed (universally accessible and bypasses Cloudflare challenge pages)
    try {
      String xml = '';
      try {
        final feedResp = await _client.get(Uri.parse('$baseUrl/feed/'), headers: {
          'Accept': 'application/rss+xml, application/xml, text/xml',
          ..._headers,
        });
        if (feedResp.statusCode == 200 && feedResp.body.contains('<rss')) {
          xml = feedResp.body;
        }
      } catch (_) {}

      if (xml.isEmpty || !xml.contains('<rss')) {
        final wvXml = await WebViewSessionManager.instance.fetchHtmlViaWebView('$baseUrl/feed/');
        if (wvXml != null && wvXml.contains('<rss')) {
          xml = wvXml;
        }
      }

      if (xml.contains('<rss')) {
        final list = _parseRssFeed(xml);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 4. Try WP REST API fallback
    try {
      final wpPostsStr = '$baseUrl/wp-json/wp/v2/posts?per_page=20&page=$page&_embed=true';
      String jsonStr = '';
      try {
        final resp = await _client.get(Uri.parse(wpPostsStr), headers: {
          'Accept': 'application/json',
          ..._headers,
        });
        if (resp.statusCode == 200 && !resp.body.contains('<!DOCTYPE html>')) {
          jsonStr = resp.body;
        }
      } catch (_) {}

      if (jsonStr.isEmpty) {
        final wvJson = await WebViewSessionManager.instance.fetchHtmlViaWebView(wpPostsStr);
        if (wvJson != null && !wvJson.contains('<!DOCTYPE html>')) {
          jsonStr = wvJson;
        }
      }

      if (jsonStr.isNotEmpty) {
        final list = _parseWpPosts(jsonStr);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    try {
      final wpCatStr = '$baseUrl/wp-json/wp/v2/categories?per_page=20&page=$page&orderby=id&order=desc';
      String jsonStr = '';
      try {
        final resp = await _client.get(Uri.parse(wpCatStr), headers: {
          'Accept': 'application/json',
          ..._headers,
        });
        if (resp.statusCode == 200 && !resp.body.contains('<!DOCTYPE html>')) {
          jsonStr = resp.body;
        }
      } catch (_) {}

      if (jsonStr.isEmpty) {
        final wvJson = await WebViewSessionManager.instance.fetchHtmlViaWebView(wpCatStr);
        if (wvJson != null && !wvJson.contains('<!DOCTYPE html>')) {
          jsonStr = wvJson;
        }
      }

      if (jsonStr.isNotEmpty) {
        final list = _parseWpCategories(jsonStr);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 5. Try alternative candidate URLs
    final otherCandidates = [
      page == 1 ? '$baseUrl/novels/?order=latest' : '$baseUrl/novels/page/$page/?order=latest',
      page == 1 ? '$baseUrl/series/' : '$baseUrl/series/page/$page/',
      page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/',
    ];

    for (final url in otherCandidates) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _headers);
        if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
          final list = parseNovelList(resp.body);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
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

  List<Novel> _parseWpCategories(String jsonStr) {
    try {
      final list = <Novel>[];
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final rawName = item['name']?.toString() ?? '';
            final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
            if (rawName.trim().isEmpty || count == 0) continue;

            final title = html_parser.parseFragment(rawName).text?.trim() ?? rawName.trim();
            final slug = item['slug']?.toString() ?? '';
            final link = item['link']?.toString() ?? '';

            // Clean series URL: e.g. https://knoxt.space/category/hero-saves-beauty/ -> https://knoxt.space/hero-saves-beauty/
            String sourceUrl = link.replaceAll('/category/', '/');
            if (!sourceUrl.endsWith('/')) sourceUrl = '$sourceUrl/';

            final novelSlug = slug.isNotEmpty
                ? slug
                : Uri.tryParse(sourceUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? title.hashCode.toString();

            list.add(Novel(
              id: '${id}_$novelSlug',
              sourceId: id,
              title: title,
              sourceUrl: sourceUrl,
            ));
          }
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  List<Novel> _parseWpPosts(String jsonStr) {
    try {
      final list = <Novel>[];
      final seen = <String>{};
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final embedded = item['_embedded'];
            if (embedded is Map) {
              final terms = embedded['wp:term'];
              if (terms is List) {
                for (final termList in terms) {
                  if (termList is List) {
                    for (final term in termList) {
                      if (term is Map && term['taxonomy'] == 'category') {
                        final rawName = term['name']?.toString() ?? '';
                        final link = term['link']?.toString() ?? '';
                        if (rawName.trim().isEmpty || link.isEmpty) continue;

                        final title = html_parser.parseFragment(rawName).text?.trim() ?? rawName.trim();
                        if (seen.contains(title)) continue;
                        seen.add(title);

                        String sourceUrl = link.replaceAll('/category/', '/');
                        if (!sourceUrl.endsWith('/')) sourceUrl = '$sourceUrl/';
                        final novelSlug = Uri.tryParse(sourceUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
                            title.hashCode.toString();

                        list.add(Novel(
                          id: '${id}_$novelSlug',
                          sourceId: id,
                          title: title,
                          sourceUrl: sourceUrl,
                        ));
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  List<Novel> _parseRssFeed(String xmlContent) {
    final items = RegExp(r'<item>([\s\S]*?)</item>').allMatches(xmlContent);
    final list = <Novel>[];
    final seen = <String>{};

    for (final it in items) {
      final block = it.group(1) ?? '';
      final catMatch = RegExp(r'<category[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</category>').firstMatch(block);
      final titleMatch = RegExp(r'<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>').firstMatch(block);
      final linkMatch = RegExp(r'<link>(https?://[^<]+)</link>').firstMatch(block);

      final title = catMatch?.group(1)?.trim() ?? titleMatch?.group(1)?.trim() ?? '';
      final link = linkMatch?.group(1)?.trim() ?? '';

      if (title.isEmpty || link.isEmpty) continue;
      if (seen.contains(title)) continue;
      seen.add(title);

      // If the link points to a chapter (e.g. ...-chapter-34/), normalize to series root
      String seriesLink = _cleanUrl(link);
      seriesLink = seriesLink.replaceAll(RegExp(r'-chapter-\d+.*', caseSensitive: false), '/');
      if (!seriesLink.endsWith('/')) seriesLink = '$seriesLink/';

      final slug = Uri.tryParse(seriesLink)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? seriesLink.hashCode.toString();
      list.add(Novel(
        id: '${id}_$slug',
        sourceId: id,
        title: title,
        sourceUrl: seriesLink,
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
      final slug = Uri.tryParse(novelUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      if (slug.isNotEmpty) {
        try {
          final catApiStr = '$baseUrl/wp-json/wp/v2/categories?slug=$slug';
          String catJson = '';
          try {
            final catResp = await _client.get(Uri.parse(catApiStr), headers: {
              'Accept': 'application/json',
              ..._headers,
            });
            if (catResp.statusCode == 200) catJson = catResp.body;
          } catch (_) {}

          if (catJson.isEmpty) {
            final wvCat = await WebViewSessionManager.instance.fetchHtmlViaWebView(catApiStr);
            if (wvCat != null) catJson = wvCat;
          }

          if (catJson.isNotEmpty) {
            final decoded = jsonDecode(catJson);
            if (decoded is List && decoded.isNotEmpty) {
              final cat = decoded.first as Map;
              final rawTitle = cat['name']?.toString() ?? '';
              final title = html_parser.parseFragment(rawTitle).text?.trim() ?? rawTitle.trim();
              final desc = html_parser.parseFragment(cat['description']?.toString() ?? '').text?.trim() ?? '';
              return Novel(
                id: '${id}_$slug',
                sourceId: id,
                sourceUrl: novelUrl,
                title: title.isNotEmpty ? title : 'Unknown Novel',
                description: desc,
                genres: [],
                status: 'UNKNOWN',
              );
            }
          }
        } catch (_) {}
      }
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

    var chapters = <Chapter>[];
    if (body.isNotEmpty) {
      chapters = parseChapterList(novelUrl, body);
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
    }

    // WP REST API fallback if HTML parsing yielded no chapters
    if (chapters.isEmpty) {
      final slug = Uri.tryParse(novelUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      if (slug.isNotEmpty) {
        try {
          final catApiStr = '$baseUrl/wp-json/wp/v2/categories?slug=$slug';
          String catJson = '';
          try {
            final catResp = await _client.get(Uri.parse(catApiStr), headers: {
              'Accept': 'application/json',
              ..._headers,
            });
            if (catResp.statusCode == 200) catJson = catResp.body;
          } catch (_) {}

          if (catJson.isEmpty) {
            final wvCat = await WebViewSessionManager.instance.fetchHtmlViaWebView(catApiStr);
            if (wvCat != null) catJson = wvCat;
          }

          if (catJson.isNotEmpty) {
            final decoded = jsonDecode(catJson);
            if (decoded is List && decoded.isNotEmpty) {
              final catId = decoded.first['id'];
              final postsApiStr = '$baseUrl/wp-json/wp/v2/posts?categories=$catId&per_page=100';
              String postsJson = '';
              try {
                final postsResp = await _client.get(Uri.parse(postsApiStr), headers: {
                  'Accept': 'application/json',
                  ..._headers,
                });
                if (postsResp.statusCode == 200) postsJson = postsResp.body;
              } catch (_) {}

              if (postsJson.isEmpty) {
                final wvPosts = await WebViewSessionManager.instance.fetchHtmlViaWebView(postsApiStr);
                if (wvPosts != null) postsJson = wvPosts;
              }

              if (postsJson.isNotEmpty) {
                final postsDecoded = jsonDecode(postsJson);
                if (postsDecoded is List) {
                  final novelSlug = slug;
                  final novelId = '${id}_$novelSlug';
                  int orderIndex = 0;
                  for (final p in postsDecoded.reversed) {
                    if (p is Map) {
                      final rawTitle = p['title']?['rendered']?.toString() ?? '';
                      final chTitle = html_parser.parseFragment(rawTitle).text?.trim() ?? rawTitle.trim();
                      final chLink = p['link']?.toString() ?? '';
                      if (chLink.isNotEmpty && chTitle.isNotEmpty) {
                        chapters.add(Chapter(
                          id: '${novelId}_ch_$orderIndex',
                          novelId: novelId,
                          title: chTitle,
                          chapterNumber: (++orderIndex).toDouble(),
                          url: _cleanUrl(chLink),
                          releaseDate: p['date']?.toString(),
                        ));
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    if (chapters.isEmpty && body.isEmpty) {
      throw Exception('Failed to load chapter list: $novelUrl');
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
      final slug = Uri.tryParse(chapterUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      if (slug.isNotEmpty) {
        try {
          final postResp = await _client.get(Uri.parse('$baseUrl/wp-json/wp/v2/posts?slug=$slug'), headers: {
            'Accept': 'application/json',
            ..._headers,
          });
          if (postResp.statusCode == 200) {
            final decoded = jsonDecode(postResp.body);
            if (decoded is List && decoded.isNotEmpty) {
              final post = decoded.first as Map;
              final rawTitle = post['title']?['rendered']?.toString() ?? '';
              final title = html_parser.parseFragment(rawTitle).text?.trim() ?? 'Chapter';
              final contentHtml = post['content']?['rendered']?.toString() ?? '';
              final doc = html_parser.parse(contentHtml);
              final pList = doc.querySelectorAll('p').map((p) => p.text).toList();
              final paragraphs = TextCleaner.cleanParagraphs(pList.isNotEmpty ? pList : [doc.body?.text ?? '']);
              final rawText = TextCleaner.toCleanRawText(paragraphs);
              return ChapterContent(
                chapterId: '${id}_$slug',
                novelId: '',
                title: title,
                rawText: rawText,
                paragraphs: paragraphs,
              );
            }
          }
        } catch (_) {}
      }
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
