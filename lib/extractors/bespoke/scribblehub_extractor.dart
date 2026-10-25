import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke extractor for Scribble Hub (https://www.scribblehub.com)
/// Sister platform to NovelUpdates hosting original web fiction and light novels.
class ScribbleHubExtractor implements NovelSource {
  @override
  final String id = 'scribblehub';
  @override
  final String name = 'Scribble Hub';
  @override
  final String baseUrl = 'https://www.scribblehub.com';
  @override
  final String lang = 'en';
  @override
  final String iconUrl = 'https://www.scribblehub.com/favicon.ico';
  @override
  final int estimatedNovelCount = 18000;

  late final http.Client _client;

  ScribbleHubExtractor({http.Client? client}) {
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
        ? '$baseUrl/?s=$cleanQuery&post_type=fictionposts'
        : '$baseUrl/page/$page/?s=$cleanQuery&post_type=fictionposts';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} on ScribbleHub');
    }
    if (response.body.contains('Just a moment...')) {
      throw const HttpException('Cloudflare bot protection active on ScribbleHub. Please try another source.');
    }
    return parseNovelList(response.body);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = page == 1
        ? '$baseUrl/series-ranking/'
        : '$baseUrl/series-ranking/?paged=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} on ScribbleHub');
    }
    if (response.body.contains('Just a moment...')) {
      throw const HttpException('Cloudflare bot protection active on ScribbleHub. Please try another source.');
    }
    return parseNovelList(response.body);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final targetUrl = page == 1
        ? '$baseUrl/latest-series/'
        : '$baseUrl/latest-series/?paged=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} on ScribbleHub');
    }
    if (response.body.contains('Just a moment...')) {
      throw const HttpException('Cloudflare bot protection active on ScribbleHub. Please try another source.');
    }
    return parseNovelList(response.body);
  }

  List<Novel> parseNovelList(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final List<Novel> list = [];

    final items = document.querySelectorAll('.search_main_box');

    for (final item in items) {
      final titleEl = item.querySelector('.search_title a');
      if (titleEl == null) continue;

      final href = titleEl.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final title = titleEl.text.trim();
      if (title.isEmpty) continue;

      final imgEl = item.querySelector('.search_img img');
      String coverUrl = '';
      if (imgEl != null) {
        coverUrl = imgEl.attributes['src'] ?? imgEl.attributes['data-src'] ?? '';
        coverUrl = _cleanUrl(coverUrl);
      }

      final authorEl = item.querySelector('.search_author a, .search_author');
      final author = authorEl?.text.trim() ?? 'Unknown Author';

      final genres = item.querySelectorAll('.search_genre a').map((g) => g.text.trim()).toList();

      final uri = Uri.tryParse(href);
      final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      final seriesId = segments.length >= 2 ? segments[1] : href.hashCode.toString();
      final novelId = 'scribblehub_$seriesId';

      list.add(Novel(
        id: novelId,
        sourceId: id,
        sourceUrl: _cleanUrl(href),
        title: title,
        author: author,
        coverUrl: coverUrl,
        genres: genres,
      ));
    }

    return list;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (TextCleaner.isGenreOrCategoryUrl(novelUrl)) {
      throw Exception('Invalid novel URL: $novelUrl is a genre or category link.');
    }

    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Scribble Hub novel details: HTTP ${response.statusCode}');
    }
    return parseNovelDetails(novelUrl, response.body);
  }

  Novel parseNovelDetails(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final title = document.querySelector('.fic_title')?.text.trim() ?? 'Unknown Fiction';
    final author = document.querySelector('.auth_name_fic a, .auth_name_fic')?.text.trim() ?? 'Unknown Author';

    final imgEl = document.querySelector('.fic_image img');
    String coverUrl = '';
    if (imgEl != null) {
      coverUrl = imgEl.attributes['src'] ?? imgEl.attributes['data-src'] ?? '';
      coverUrl = _cleanUrl(coverUrl);
    }

    String status = 'ONGOING';
    final infoTable = document.querySelector('.table_author_info');
    if (infoTable != null) {
      final infoText = infoTable.text.toUpperCase();
      if (infoText.contains('COMPLETED')) {
        status = 'COMPLETED';
      }
    }

    final genreEls = document.querySelectorAll('.fic_genre a, .wi_fic_genre a');
    final genres = genreEls.map((g) => g.text.trim()).where((g) => g.isNotEmpty).toSet().toList();

    final descEl = document.querySelector('.wi_fic_desc');
    String synopsis = '';
    if (descEl != null) {
      synopsis = descEl.text.trim();
    }

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final seriesId = segments.length >= 2 ? segments[1] : novelUrl.hashCode.toString();
    final novelId = 'scribblehub_$seriesId';

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
      throw Exception('Invalid novel URL: $novelUrl is a genre or category link.');
    }

    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Scribble Hub chapter list: HTTP ${response.statusCode}');
    }

    final document = html_parser.parse(response.body);
    var chapters = parseChapterList(novelUrl, response.body);

    final mypostIdEl = document.querySelector('#mypostid');
    final postId = mypostIdEl?.attributes['value'];
    if (postId != null && postId.isNotEmpty) {
      final seenUrls = <String>{};
      final allAjaxChapters = <Chapter>[];
      int pageNum = 1;
      while (pageNum <= 50) {
        try {
          final ajaxResp = await _client.post(
            Uri.parse('$baseUrl/wp-admin/admin-ajax.php'),
            headers: {
              ..._headers,
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'X-Requested-With': 'XMLHttpRequest',
            },
            body: {
              'action': 'wi_getreleases_pagination',
              'pagenum': '$pageNum',
              'mypid': postId,
            },
          );
          if (ajaxResp.statusCode == 200 && ajaxResp.body.isNotEmpty) {
            final pageChs = parseChapterList(novelUrl, ajaxResp.body);
            if (pageChs.isEmpty) break;
            bool addedNew = false;
            for (final ch in pageChs) {
              if (!seenUrls.contains(ch.url)) {
                seenUrls.add(ch.url);
                allAjaxChapters.add(ch);
                addedNew = true;
              }
            }
            if (!addedNew) break;
            pageNum++;
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
      if (allAjaxChapters.length > chapters.length) {
        chapters = allAjaxChapters;
      }
    }

    // Ensure sequential reading order (Chapter 1 first)
    if (chapters.length > 1) {
      final firstNum = chapters.first.chapterNumber;
      final lastNum = chapters.last.chapterNumber;
      if (firstNum != null && lastNum != null) {
        if (firstNum > lastNum) {
          chapters = chapters.reversed.toList();
        }
      } else {
        final lastTitle = chapters.last.title.toLowerCase();
        if (lastTitle.contains('chapter 1') || lastTitle.contains('ch. 1') || lastTitle.contains('ch.1')) {
          chapters = chapters.reversed.toList();
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
    final seriesId = segments.length >= 2 ? segments[1] : novelUrl.hashCode.toString();
    final novelId = 'scribblehub_$seriesId';

    final links = document.querySelectorAll(
      'ol.toc_ol li a, #chapter_list li a, .toc_ol a, ul.toc_ol li a',
    );

    int orderIndex = 0;
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final title = link.text.trim();
      if (title.isEmpty) continue;

      final chapterSlug = Uri.tryParse(href)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
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
    final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Scribble Hub chapter content: HTTP ${response.statusCode}');
    }
    return parseChapterContent(chapterUrl, response.body);
  }

  ChapterContent parseChapterContent(String chapterUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final titleEl = document.querySelector('.chapter-title, h1');
    final title = titleEl?.text.trim() ?? 'Chapter';

    final container = document.querySelector('div.chp_raw, div.chp_content');
    if (container == null) {
      throw Exception('Chapter reading content (.chp_raw) not found on $chapterUrl');
    }

    container
        .querySelectorAll(
          'script, style, ins, .wi_authornotes, .author-notes, .sp-head',
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
      chapterId: 'scribblehub_$chapterSlug',
      novelId: '',
      title: title,
      rawText: rawText,
      paragraphs: cleanedParagraphs,
    );
  }
}

