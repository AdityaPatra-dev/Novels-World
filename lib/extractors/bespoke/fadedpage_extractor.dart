import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import 'local_epub_extractor.dart';
import '../novel_source.dart';

/// Bespoke extractor for Faded Page (https://www.fadedpage.com).
/// Premier Canadian public domain book archive covering post-1928 masterworks
/// (Sylvia Plath, Ernest Hemingway, George Orwell, Olaf Stapledon, classic mystery/sci-fi).
/// Catalog is accessible via high-speed JSON API; full EPUB downloads are supported
/// via the in-app WebView session.
class FadedPageExtractor implements NovelSource {
  @override
  final String id = 'fadedpage';

  @override
  final String name = 'Faded Page';

  @override
  final String baseUrl = 'https://www.fadedpage.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://www.fadedpage.com/images/fpicn.ico';

  @override
  final int estimatedNovelCount = 9200;

  late final http.Client _client;

  FadedPageExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'en-US,en;q=0.9',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Referer': '$baseUrl/',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return _queryCatalog(query: '', page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return _queryCatalog(query: '', page: page);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    return _queryCatalog(query: query.trim(), page: page);
  }

  Future<List<Novel>> _queryCatalog({required String query, int page = 1}) async {
    final bodyData = 'action=search&title=${Uri.encodeComponent(query)}&author=&tags=';
    final searchUri = Uri.parse('$baseUrl/csearc2.php');

    try {
      final response = await _client.post(
        searchUri,
        headers: _headers,
        body: bodyData,
      );

      if (response.statusCode != 200) {
        return [];
      }

      final data = json.decode(response.body);
      if (data is! Map || data['rows'] == null) {
        return [];
      }

      final rawRows = data['rows'] as List;
      final results = <Novel>[];

      // Pagination: 25 items per page
      const pageSize = 25;
      final startIndex = (page - 1) * pageSize;
      if (startIndex >= rawRows.length) return [];

      final pageRows = rawRows.skip(startIndex).take(pageSize);

      for (final item in pageRows) {
        if (item is! Map) continue;

        final pid = item['pid']?.toString() ?? '';
        if (pid.isEmpty) continue;

        final title = (item['title']?.toString() ?? 'Untitled').trim();
        final desc = (item['description']?.toString() ?? '').trim();

        // Authors
        var author = 'Unknown Author';
        if (item['authors'] is List && (item['authors'] as List).isNotEmpty) {
          final authorList = <String>[];
          for (final a in (item['authors'] as List)) {
            if (a is Map && a['realname'] != null) {
              authorList.add(a['realname'].toString().trim());
            }
          }
          if (authorList.isNotEmpty) {
            author = authorList.join(', ');
          }
        }

        // Cover
        String coverUrl = '';
        if (item['cover'] != null && item['cover'].toString().isNotEmpty) {
          coverUrl = '$baseUrl/${item['cover']}';
        } else {
          coverUrl = '$baseUrl/books/$pid/cover.jpg';
        }

        final sourceUrl = '$baseUrl/showbook.php?pid=$pid';
        final downloadUrl = '$baseUrl/link.php?file=$pid.epub';

        results.add(Novel(
          id: '${id}_$pid',
          sourceId: id,
          title: title,
          author: author,
          coverUrl: coverUrl,
          sourceUrl: sourceUrl,
          description: desc,
          status: 'COMPLETED',
          isFullBook: true,
          bookFormat: 'epub',
          bookDownloadUrl: downloadUrl,
        ));
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getNovelDetails(novelUrl);
    }

    final uri = Uri.parse(novelUrl);
    final pid = uri.queryParameters['pid'] ?? uri.pathSegments.lastOrNull ?? '';

    final response = await _client.get(Uri.parse(novelUrl), headers: {
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    });

    if (response.statusCode != 200) {
      throw Exception('Failed to load Faded Page novel details from $novelUrl');
    }

    final doc = html_parser.parse(response.body);
    final title = doc.querySelector('h1, title')?.text.trim() ?? 'Novel';
    final desc = doc.querySelector('div.description, p.desc, meta[name="description"]')?.text.trim() ?? '';
    final coverUrl = '$baseUrl/books/$pid/cover.jpg';
    final downloadUrl = '$baseUrl/link.php?file=$pid.epub';

    return Novel(
      id: '${id}_$pid',
      sourceId: id,
      title: title,
      author: 'Public Domain',
      description: desc,
      coverUrl: coverUrl,
      sourceUrl: novelUrl,
      status: 'COMPLETED',
      isFullBook: true,
      bookFormat: 'epub',
      bookDownloadUrl: downloadUrl,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getChapterList(novelUrl, onBatchLoaded: onBatchLoaded);
    }

    final uri = Uri.parse(novelUrl);
    final pid = uri.queryParameters['pid'] ?? 'book';
    final chapters = [
      Chapter(
        id: '${id}_${pid}_1',
        novelId: '${id}_$pid',
        title: 'Full Book (Download EPUB)',
        url: '$baseUrl/link.php?file=$pid.epub',
        chapterNumber: 1.0,
      ),
    ];
    onBatchLoaded?.call(chapters);
    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    if (chapterUrl.startsWith('file:') || chapterUrl.startsWith('/')) {
      return LocalEpubExtractor().getChapterContent(chapterUrl);
    }

    return ChapterContent(
      chapterId: chapterUrl,
      novelId: '',
      title: 'Full Book Download',
      rawText: 'This is a complete full-length book from Faded Page. Tap Download to save the complete EPUB book to your library.',
      paragraphs: const [
        'This is a complete full-length book from Faded Page.',
        'Tap Download Book to verify and save the complete EPUB edition to your offline library.',
      ],
    );
  }
}
