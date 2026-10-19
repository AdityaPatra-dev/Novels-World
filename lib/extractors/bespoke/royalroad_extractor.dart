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

/// Bespoke extractor for Royal Road (https://www.royalroad.com)
/// The premier western original web fiction platform.
class RoyalRoadExtractor implements NovelSource {
  @override
  final String id = 'royalroad';
  @override
  final String name = 'Royal Road';
  @override
  final String baseUrl = 'https://www.royalroad.com';
  @override
  final String lang = 'en';
  @override
  final String iconUrl = 'https://www.royalroad.com/icons/favicon-32x32.png';
  @override
  final int estimatedNovelCount = 65000;

  late final http.Client _client;

  RoyalRoadExtractor({http.Client? client}) {
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
    final targetUrl = '$baseUrl/fictions/search?title=$cleanQuery&page=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} on Royal Road.');
    }
    if (response.body.contains('Just a moment...')) {
      throw const HttpException('Royal Road Cloudflare protection is active. Please select another source.');
    }
    return parseNovelList(response.body);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = '$baseUrl/fictions/weekly-popular?page=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} on Royal Road.');
    }
    if (response.body.contains('Just a moment...')) {
      throw const HttpException('Royal Road Cloudflare protection is active. Please select another source.');
    }
    return parseNovelList(response.body);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final targetUrl = '$baseUrl/fictions/latest-updates?page=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} on Royal Road.');
    }
    if (response.body.contains('Just a moment...')) {
      throw const HttpException('Royal Road Cloudflare protection is active. Please select another source.');
    }
    return parseNovelList(response.body);
  }

  List<Novel> parseNovelList(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final List<Novel> list = [];

    final items = document.querySelectorAll('.fiction-list-item');

    for (final item in items) {
      final titleEl = item.querySelector('h2.fiction-title a');
      if (titleEl == null) continue;

      final href = titleEl.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final title = titleEl.text.trim();
      if (title.isEmpty) continue;

      final imgEl = item.querySelector('img');
      String coverUrl = '';
      if (imgEl != null) {
        coverUrl = imgEl.attributes['src'] ?? '';
        coverUrl = _cleanUrl(coverUrl);
      }

      final authorEl = item.querySelector('.author a');
      final author = authorEl?.text.trim() ?? 'Unknown Author';

      final tags = item.querySelectorAll('.tags a, .fiction-tag').map((t) => t.text.trim()).toList();

      final uri = Uri.tryParse(href);
      final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      final fictionId = segments.length >= 2 ? segments[1] : href.hashCode.toString();
      final novelId = 'royalroad_$fictionId';

      list.add(Novel(
        id: novelId,
        sourceId: id,
        sourceUrl: _cleanUrl(href),
        title: title,
        author: author,
        coverUrl: coverUrl,
        genres: tags,
      ));
    }

    return list;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Royal Road fiction details: HTTP ${response.statusCode}');
    }
    return parseNovelDetails(novelUrl, response.body);
  }

  Novel parseNovelDetails(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final title = document.querySelector('h1.font-white, .fic-title h1, h1')?.text.trim() ?? 'Unknown Fiction';
    final author = document.querySelector('h4.font-white span a, h4 span a, .fic-header a')?.text.trim() ?? 'Unknown Author';

    final imgEl = document.querySelector('.cover-art-container img, .fic-header img');
    String coverUrl = '';
    if (imgEl != null) {
      coverUrl = imgEl.attributes['src'] ?? '';
      coverUrl = _cleanUrl(coverUrl);
    }

    String status = 'ONGOING';
    final statusEl = document.querySelector('.fiction-info .label, .label-success, .label-default');
    if (statusEl != null) {
      final st = statusEl.text.toUpperCase();
      if (st.contains('COMPLETED')) {
        status = 'COMPLETED';
      }
    }

    final tagEls = document.querySelectorAll('.fiction-tag, .tags a');
    final genres = tagEls.map((g) => g.text.trim()).where((g) => g.isNotEmpty).toSet().toList();

    final descEl = document.querySelector('.description .font-white, .description, div.description');
    String synopsis = '';
    if (descEl != null) {
      synopsis = descEl.text.trim();
    }

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final fictionId = segments.length >= 2 ? segments[1] : novelUrl.hashCode.toString();
    final novelId = 'royalroad_$fictionId';

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
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Royal Road chapter list: HTTP ${response.statusCode}');
    }
    return parseChapterList(novelUrl, response.body);
  }

  List<Chapter> parseChapterList(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final List<Chapter> chapters = [];

    final uri = Uri.tryParse(novelUrl);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final fictionId = segments.length >= 2 ? segments[1] : novelUrl.hashCode.toString();
    final novelId = 'royalroad_$fictionId';

    final rows = document.querySelectorAll('#chapters tbody tr, tr.chapter-row');

    int orderIndex = 0;
    for (final row in rows) {
      final link = row.querySelector('td:first-child a, a[href*="/chapter/"]');
      if (link == null) continue;

      final href = link.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final title = link.text.trim();
      if (title.isEmpty) continue;

      final dateEl = row.querySelector('time');
      final date = dateEl?.attributes['title'] ?? dateEl?.text.trim();

      final chapterUri = Uri.tryParse(href);
      final cSegments = chapterUri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      String chapterSlug = '${orderIndex + 1}';
      final chapIdx = cSegments.indexOf('chapter');
      if (chapIdx != -1 && chapIdx + 1 < cSegments.length) {
        chapterSlug = cSegments[chapIdx + 1];
      } else if (cSegments.isNotEmpty) {
        chapterSlug = cSegments.last;
      }
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
        releaseDate: date,
      ));
      orderIndex++;
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Royal Road chapter content: HTTP ${response.statusCode}');
    }
    return parseChapterContent(chapterUrl, response.body);
  }

  ChapterContent parseChapterContent(String chapterUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    final titleEl = document.querySelector('h1.font-white, h1');
    final title = titleEl?.text.trim() ?? 'Chapter';

    final container = document.querySelector('.chapter-inner.chapter-content, .chapter-content');
    if (container == null) {
      throw Exception('Chapter reading content (.chapter-content) not found on $chapterUrl');
    }

    container
        .querySelectorAll(
          'script, style, ins, .portlet-body, .author-note-portlet, .author-note, .bold.italic',
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

    final chapterUri = Uri.tryParse(chapterUrl);
    final cSegments = chapterUri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    final chapIdx = cSegments.indexOf('chapter');
    final slug = (chapIdx != -1 && chapIdx + 1 < cSegments.length)
        ? cSegments[chapIdx + 1]
        : chapterUrl.hashCode.toString();

    return ChapterContent(
      chapterId: 'royalroad_$slug',
      novelId: '',
      title: title,
      rawText: rawText,
      paragraphs: cleanedParagraphs,
    );
  }
}

