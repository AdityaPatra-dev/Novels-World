import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Extractor for RoliaScan (https://roliascan.com).
/// Specializes in light novels and web novels with MangaPeak custom backend and dynamic chapter delivery.
class RoliaScanExtractor implements NovelSource {
  @override
  final String id = 'roliascan';

  @override
  final String name = 'RoliaScan';

  @override
  final String baseUrl = 'https://roliascan.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 2000;

  late final http.Client _client;

  RoliaScanExtractor({http.Client? client}) {
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (cert, host, port) => true;
      nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
      _client = IOClient(nativeHttpClient);
    }
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'application/json, text/html, */*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': '$baseUrl/',
      'Origin': baseUrl,
    };
    final cookie = WebViewSessionManager.instance.getCookieHeader(baseUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return _fetchCatalog(page: page, sort: 'views');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return _fetchCatalog(page: page, sort: 'update');
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    return _fetchCatalog(page: page, search: query.trim());
  }

  Future<List<Novel>> _fetchCatalog({
    required int page,
    String? sort,
    String? search,
  }) async {
    final url = Uri.parse('$baseUrl/wp-json/manga/v1/load');
    final payload = <String, dynamic>{
      'page': page,
      'types': '["Novel"]',
    };
    if (sort != null) {
      payload['sort'] = sort;
    }
    if (search != null && search.isNotEmpty) {
      payload['search'] = search;
    }

    final headers = Map<String, String>.from(_headers);
    headers['Content-Type'] = 'application/json';

    try {
      final response = await _client.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        return [];
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return [];
      }

      final novels = <Novel>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final itemUrl = item['url']?.toString() ?? '';
        final title = item['title']?.toString().trim() ?? '';
        if (itemUrl.isEmpty || title.isEmpty) continue;

        final rawCover = item['cover']?.toString() ?? '';
        final coverUrl = _resolveUrl(rawCover);
        final status = (item['status']?.toString().toUpperCase() == 'COMPLETED') ? 'COMPLETED' : 'ONGOING';
        final rawDesc = item['description']?.toString() ?? '';
        final descClean = rawDesc.replaceAll(RegExp(r'<[^>]*>'), '').trim();

        final itemId = item['id']?.toString() ?? '';
        final slug = Uri.parse(itemUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? itemId;

        novels.add(Novel(
          id: '${id}_$slug',
          title: title,
          sourceUrl: itemUrl,
          coverUrl: coverUrl,
          author: item['author']?.toString() ?? 'Unknown Author',
          status: status,
          description: descClean,
          sourceId: id,
        ));
      }
      return novels;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('Failed to load novel details from RoliaScan ($novelUrl)');
    }

    final doc = html_parser.parse(response.body);

    // 1. Title & cover
    var title = doc.querySelector('h1')?.text.trim() ??
        doc.querySelector('title')?.text.split('|').first.trim() ??
        'Untitled';

    String coverUrl = '';
    final coverEl = doc.querySelector('.poster img, .manga-poster img, img[src*="cover"]');
    if (coverEl != null) {
      final src = coverEl.attributes['data-src'] ?? coverEl.attributes['src'];
      if (src != null && src.isNotEmpty) {
        coverUrl = _resolveUrl(src);
      }
    }

    // 2. Synopsis / Description
    String description = '';
    final descEl = doc.querySelector('.synopsis, .description, [class*="description"]');
    if (descEl != null) {
      final text = descEl.text.trim();
      if (text.isNotEmpty) {
        description = text;
      }
    }

    // 3. Author & Status & Genres
    String author = 'Unknown Author';
    final authorMatch = RegExp(r'Author\s*(?:&amp;|&)\s*Artist[\s\S]*?<div[^>]*>([^<]+)</div>', caseSensitive: false)
        .firstMatch(response.body);
    if (authorMatch != null) {
      final rawAuthor = authorMatch.group(1)?.trim();
      if (rawAuthor != null && rawAuthor.isNotEmpty) {
        author = rawAuthor.replaceAll(r'\_', ' ');
      }
    }

    String status = 'ONGOING';
    final statusEl = doc.querySelector('[data-status]');
    if (statusEl != null) {
      final rawStatus = statusEl.attributes['data-status']?.toUpperCase();
      if (rawStatus == 'COMPLETED') {
        status = 'COMPLETED';
      }
    }

    final genres = <String>[];
    for (final g in doc.querySelectorAll('a[href*="/genre/"]')) {
      final name = g.text.trim();
      if (name.isNotEmpty && !genres.contains(name)) {
        genres.add(name);
      }
    }

    final slug = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
        novelUrl.hashCode.toString();

    return Novel(
      id: '${id}_$slug',
      title: title,
      sourceUrl: novelUrl,
      coverUrl: coverUrl,
      author: author,
      description: description,
      status: status,
      genres: genres,
      sourceId: id,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      return [];
    }

    String? mangaId;
    final match = RegExp(r'data-manga-id="(\d+)"').firstMatch(response.body);
    if (match != null) {
      mangaId = match.group(1);
    }

    if (mangaId == null || mangaId.isEmpty) {
      return [];
    }

    final slug = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
        novelUrl.hashCode.toString();
    final novelId = '${id}_$slug';

    final chapters = <Chapter>[];
    int offset = 0;
    const limit = 250;
    bool hasMore = true;

    while (hasMore) {
      final now = DateTime.now().toUtc();
      final timestamp = now.millisecondsSinceEpoch ~/ 1000;
      final hour = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}';
      final secret = 'mng_ch_$hour';
      final token = md5.convert(utf8.encode('$timestamp$secret')).toString().substring(0, 16);

      final url = Uri.parse(
        '$baseUrl/auth/manga-chapters?manga_id=$mangaId&offset=$offset&limit=$limit&order=ASC&_t=$token&_ts=$timestamp',
      );

      final headers = Map<String, String>.from(_headers);
      headers['Referer'] = novelUrl;
      headers['X-Requested-With'] = 'XMLHttpRequest';

      try {
        final res = await _client.get(url, headers: headers);
        if (res.statusCode != 200) {
          break;
        }

        final decoded = jsonDecode(res.body);
        if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
          break;
        }

        final items = decoded['chapters'];
        if (items is! List || items.isEmpty) {
          break;
        }

        for (final ch in items) {
          if (ch is! Map<String, dynamic>) continue;
          final chUrl = ch['url']?.toString() ?? '';
          if (chUrl.isEmpty) continue;

          final rawNum = ch['chapter']?.toString() ?? '';
          final chNum = double.tryParse(rawNum);
          final rawTitle = ch['title']?.toString().trim();
          String title;
          if (rawTitle != null && rawTitle.isNotEmpty && rawTitle.toLowerCase() != 'n/a') {
            title = 'Chapter $rawNum: $rawTitle';
          } else {
            title = 'Chapter $rawNum';
          }

          final chId = ch['id']?.toString() ?? '${id}_${slug}_$rawNum';

          chapters.add(Chapter(
            id: chId,
            novelId: novelId,
            title: title,
            url: chUrl,
            chapterNumber: chNum,
            releaseDate: ch['date']?.toString(),
          ));
        }

        hasMore = decoded['has_more'] == true;
        offset += items.length;

        if (items.length < limit || offset >= (decoded['total'] as num? ?? 999999)) {
          break;
        }
      } catch (_) {
        break;
      }
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('Failed to load chapter content: HTTP ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final reader = doc.querySelector('.reader-text') ?? doc.querySelector('.reader');
    if (reader == null) {
      throw HttpException('Could not locate reader container in chapter page');
    }

    // Remove ads and scripts
    reader.querySelectorAll('.rolia-ad-slot, script, style, ins, iframe, .ad-container').forEach((el) => el.remove());

    final rawParas = <String>[];
    final pElements = reader.querySelectorAll('p');

    if (pElements.isNotEmpty) {
      for (final p in pElements) {
        final text = p.text.trim();
        if (text.isNotEmpty) {
          rawParas.add(text);
        }
      }
    } else {
      final lines = reader.innerHtml.split(RegExp(r'<br\s*/?>'));
      for (final line in lines) {
        final text = html_parser.parse(line).body?.text.trim() ?? '';
        if (text.isNotEmpty) {
          rawParas.add(text);
        }
      }
    }

    if (rawParas.isEmpty) {
      final fallback = reader.text.trim();
      if (fallback.isNotEmpty) {
        rawParas.add(fallback);
      }
    }

    final paragraphs = TextCleaner.cleanParagraphs(rawParas);
    final rawText = TextCleaner.toCleanRawText(paragraphs);

    final segments = Uri.parse(chapterUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final chSlug = segments.isNotEmpty ? segments.last : chapterUrl.hashCode.toString();
    final novelSlug = segments.length > 1 ? segments[segments.length - 2] : 'novel';
    final novelId = '${id}_$novelSlug';
    final chapterId = '${id}_${novelSlug}_$chSlug';
    final title = doc.querySelector('h1, title')?.text.trim() ?? 'Chapter';

    return ChapterContent(
      chapterId: chapterId,
      novelId: novelId,
      title: title,
      rawText: rawText,
      paragraphs: paragraphs,
    );
  }

  String _resolveUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('//')) {
      return 'https:$path';
    }
    if (path.startsWith('/')) {
      return '$baseUrl$path';
    }
    return '$baseUrl/$path';
  }
}
