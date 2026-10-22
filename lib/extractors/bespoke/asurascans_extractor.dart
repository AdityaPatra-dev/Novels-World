import 'dart:convert';
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

/// Extractor for Asura Scans (https://asurascans.com).
/// Supports Asura's newly launched high-quality webnovel translations via their direct REST API
/// and SSR reader pages.
class AsuraScansExtractor implements NovelSource {
  @override
  final String id = 'asurascans';

  @override
  final String name = 'Asura Scans';

  @override
  final String baseUrl = 'https://asurascans.com';

  final String apiUrl = 'https://api.asurascans.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 100;

  late final http.Client _client;

  AsuraScansExtractor({http.Client? client}) {
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (cert, host, port) => true;
      nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
      _client = IOClient(nativeHttpClient);
    }
  }

  Map<String, String> get _apiHeaders => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': baseUrl,
    'Referer': '$baseUrl/',
  };

  Map<String, String> get _htmlHeaders {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': '$baseUrl/',
    };
    final cookie = WebViewSessionManager.instance.getCookieHeader(baseUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return _fetchCatalog(page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return _fetchCatalog(page: page, order: 'last_chapter_at', orderDirection: 'desc');
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    return _fetchCatalog(page: page, search: query.trim());
  }

  Future<List<Novel>> _fetchCatalog({
    required int page,
    String? search,
    String? order,
    String? orderDirection,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': '50',
    };
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (order != null) {
      queryParams['order'] = order;
    }
    if (orderDirection != null) {
      queryParams['order_direction'] = orderDirection;
    }

    final uri = Uri.parse('$apiUrl/api/novel-series').replace(queryParameters: queryParams);

    try {
      final response = await _client.get(uri, headers: _apiHeaders);
      if (response.statusCode != 200) {
        return [];
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final items = decoded['data'];
      if (items is! List) {
        return [];
      }

      final novels = <Novel>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final slug = item['slug']?.toString() ?? '';
        final title = item['title']?.toString().trim() ?? '';
        if (slug.isEmpty || title.isEmpty) continue;

        final rawCover = item['cover_url']?.toString() ?? '';
        final status = (item['status']?.toString().toUpperCase() == 'COMPLETED') ? 'COMPLETED' : 'ONGOING';
        final author = item['author']?.toString() ?? 'Unknown Author';
        final descHtml = item['description']?.toString() ?? '';
        final description = html_parser.parse(descHtml).body?.text.trim() ?? '';

        final rawGenres = item['genres'];
        final genres = <String>[];
        if (rawGenres is List) {
          for (final g in rawGenres) {
            if (g != null && g.toString().isNotEmpty) {
              genres.add(g.toString());
            }
          }
        }

        novels.add(Novel(
          id: '${id}_$slug',
          title: title,
          sourceUrl: '$baseUrl/novels/$slug',
          coverUrl: rawCover,
          author: author,
          status: status,
          description: description,
          genres: genres,
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
    final slug = _extractSlug(novelUrl);
    if (slug.isEmpty) {
      throw HttpException('Invalid novel URL for Asura Scans: $novelUrl');
    }

    final uri = Uri.parse('$apiUrl/api/novel-series/$slug');
    final response = await _client.get(uri, headers: _apiHeaders);
    if (response.statusCode != 200) {
      throw HttpException('Failed to load novel details from Asura Scans ($novelUrl)');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw HttpException('Invalid JSON response from Asura Scans');
    }

    final series = decoded['series'];
    if (series is! Map<String, dynamic>) {
      throw HttpException('Missing series object from Asura Scans');
    }

    final title = series['title']?.toString().trim() ?? 'Untitled';
    final rawCover = series['cover_url']?.toString() ?? '';
    final author = series['author']?.toString() ?? 'Unknown Author';
    final status = (series['status']?.toString().toUpperCase() == 'COMPLETED') ? 'COMPLETED' : 'ONGOING';

    final descHtml = series['description']?.toString() ?? '';
    final description = descHtml.isNotEmpty
        ? (html_parser.parse(descHtml).body?.text.trim() ?? '')
        : '';

    final rawGenres = series['genres'];
    final genres = <String>[];
    if (rawGenres is List && rawGenres.isNotEmpty) {
      for (final g in rawGenres) {
        if (g != null && g.toString().isNotEmpty) {
          genres.add(g.toString());
        }
      }
    }

    return Novel(
      id: '${id}_$slug',
      title: title,
      sourceUrl: '$baseUrl/novels/$slug',
      coverUrl: rawCover,
      author: author,
      description: description,
      status: status,
      genres: genres,
      sourceId: id,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    final slug = _extractSlug(novelUrl);
    if (slug.isEmpty) return [];

    final novelId = '${id}_$slug';
    final uri = Uri.parse('$apiUrl/api/novel-series/$slug');

    try {
      final response = await _client.get(uri, headers: _apiHeaders);
      if (response.statusCode != 200) {
        return [];
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final rawChapters = decoded['chapters'];
      if (rawChapters is! List) {
        return [];
      }

      final chapters = <Chapter>[];
      for (final ch in rawChapters) {
        if (ch is! Map<String, dynamic>) continue;
        final numVal = ch['number'];
        final chNum = (numVal as num?)?.toDouble();
        final rawTitle = ch['title']?.toString().trim() ?? '';
        final isLocked = ch['is_locked'] == true;

        String title;
        if (rawTitle.isNotEmpty && rawTitle.toLowerCase() != 'n/a') {
          title = chNum != null ? 'Chapter ${chNum.toInt() == chNum ? chNum.toInt() : chNum} - $rawTitle' : rawTitle;
        } else {
          title = chNum != null ? 'Chapter ${chNum.toInt() == chNum ? chNum.toInt() : chNum}' : 'Chapter';
        }

        if (isLocked) {
          title = '🔒 $title';
        }

        final chUrl = '$baseUrl/novels/$slug/chapter/$numVal';
        final chId = ch['id']?.toString() ?? '${id}_${slug}_$numVal';

        chapters.add(Chapter(
          id: chId,
          novelId: novelId,
          title: title,
          url: chUrl,
          chapterNumber: chNum,
          releaseDate: ch['published_at']?.toString(),
        ));
      }
      return chapters;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final response = await _client.get(Uri.parse(chapterUrl), headers: _htmlHeaders);
    if (response.statusCode != 200) {
      throw HttpException('Failed to load chapter content: HTTP ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final rawParas = <String>[];
    final paraElements = doc.querySelectorAll('p[data-para]');

    if (paraElements.isNotEmpty) {
      for (final p in paraElements) {
        final text = p.text.trim();
        if (text.isNotEmpty) {
          rawParas.add(text);
        }
      }
    } else {
      final mainContainer = doc.querySelector('main') ?? doc.body;
      if (mainContainer != null) {
        mainContainer.querySelectorAll('script, style, nav, header, footer, button, svg').forEach((el) => el.remove());
        final pTags = mainContainer.querySelectorAll('p');
        for (final p in pTags) {
          final text = p.text.trim();
          if (text.isNotEmpty && text.length > 5) {
            rawParas.add(text);
          }
        }
      }
    }

    if (rawParas.isEmpty) {
      throw HttpException('No readable paragraphs found in chapter content');
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

  String _extractSlug(String urlOrSlug) {
    if (!urlOrSlug.startsWith('http://') && !urlOrSlug.startsWith('https://')) {
      return urlOrSlug.replaceFirst(RegExp('^${id}_'), '');
    }
    final uri = Uri.tryParse(urlOrSlug);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final idx = uri.pathSegments.indexOf('novels');
      if (idx != -1 && uri.pathSegments.length > idx + 1) {
        return uri.pathSegments[idx + 1];
      }
      return uri.pathSegments.last;
    }
    return '';
  }
}
