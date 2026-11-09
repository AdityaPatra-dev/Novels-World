import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../../core/services/epub_service.dart';
import 'local_epub_extractor.dart';
import '../novel_source.dart';

/// Bespoke extractor for Open Library (https://openlibrary.org).
/// Open catalog of 20+ million book records and public full text editions
/// with Internet Archive integration.
class OpenLibraryExtractor implements NovelSource {
  @override
  final String id = 'openlibrary';

  @override
  final String name = 'Open Library';

  @override
  final String baseUrl = 'https://openlibrary.org';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://openlibrary.org/favicon.ico';

  @override
  final int estimatedNovelCount = 20000000;

  late final http.Client _client;

  OpenLibraryExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'application/json,*/*;q=0.8',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return search('fantasy fiction', page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return search('science fiction', page: page);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQuery);
    final url = '$baseUrl/search.json?q=$encoded&page=$page&limit=25&has_fulltext=true';

    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];
      return parseDocs(docs);
    } catch (_) {
      return [];
    }
  }

  /// Parses Open Library JSON search documents into Novel models
  List<Novel> parseDocs(List<dynamic> docs) {
    final List<Novel> results = [];

    for (final doc in docs) {
      if (doc is! Map<String, dynamic>) continue;

      final key = doc['key']?.toString() ?? '';
      if (key.isEmpty) continue;

      final rawTitle = doc['title']?.toString() ?? 'Novel';
      final title = TextCleaner.cleanNovelTitle(rawTitle);

      var author = 'Unknown Author';
      final authors = doc['author_name'];
      if (authors is List && authors.isNotEmpty) {
        author = authors.first.toString().trim();
      } else if (authors is String && authors.trim().isNotEmpty) {
        author = authors.trim();
      }

      final coverI = doc['cover_i'];
      final coverUrl = coverI != null
          ? 'https://covers.openlibrary.org/b/id/$coverI-M.jpg'
          : '';

      final iaList = doc['ia'] as List<dynamic>? ?? [];
      String? iaId;
      for (final candidate in iaList) {
        final idStr = candidate.toString();
        if (idStr.isNotEmpty && !idStr.startsWith('isbn_') && !idStr.contains('_lcp')) {
          iaId = idStr;
          break;
        }
      }
      iaId ??= iaList.isNotEmpty ? iaList.first.toString() : null;

      final novelUrl = '$baseUrl$key';
      final downloadUrl = iaId != null ? 'https://archive.org/download/$iaId' : null;

      results.add(Novel(
        id: '${id}_${key.replaceAll('/', '_')}',
        sourceId: id,
        title: title,
        author: author,
        coverUrl: coverUrl,
        sourceUrl: novelUrl,
        status: 'COMPLETED',
        isFullBook: true,
        bookDownloadUrl: downloadUrl,
        bookFormat: 'epub',
      ));
    }

    return results;
  }

  /// Resolves the direct, unencrypted public EPUB download URL from Internet Archive metadata
  static Future<String?> resolveArchiveOrgEpub(String iaId, {http.Client? client}) async {
    final c = client ?? createPlatformHttpClient();
    try {
      final metaUrl = 'https://archive.org/metadata/$iaId/files';
      final response = await c.get(
        Uri.parse(metaUrl),
        headers: {'User-Agent': WebViewSessionManager.defaultUserAgent},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final files = data['result'] as List<dynamic>? ?? [];
        for (final f in files) {
          if (f is! Map<String, dynamic>) continue;
          final name = f['name']?.toString() ?? '';
          final format = f['format']?.toString() ?? '';
          final isPrivate = f['private']?.toString().toLowerCase() == 'true';
          if (isPrivate) continue;

          if (format.toUpperCase() == 'EPUB' ||
              (name.toLowerCase().endsWith('.epub') &&
                  !name.toLowerCase().contains('_lcp') &&
                  !format.toLowerCase().contains('encrypted'))) {
            return 'https://archive.org/download/$iaId/${Uri.encodeComponent(name)}';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getNovelDetails(novelUrl);
    }
    final cleanUrl = novelUrl.endsWith('.json') ? novelUrl : '$novelUrl.json';
    final response = await _client.get(Uri.parse(cleanUrl), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load Open Library details from $novelUrl');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawTitle = data['title']?.toString() ?? 'Novel';
    final title = TextCleaner.cleanNovelTitle(rawTitle);

    var description = '';
    final descData = data['description'];
    if (descData is String) {
      description = descData;
    } else if (descData is Map && descData['value'] != null) {
      description = descData['value'].toString();
    }

    final covers = data['covers'] as List<dynamic>? ?? [];
    final coverUrl = covers.isNotEmpty
        ? 'https://covers.openlibrary.org/b/id/${covers.first}-M.jpg'
        : '';

    final key = data['key']?.toString() ?? novelUrl;

    // Resolve unencrypted EPUB download URL from editions or OCAID
    String? resolvedDownloadUrl;
    final ocaid = data['ocaid']?.toString();
    if (ocaid != null && ocaid.isNotEmpty && !ocaid.startsWith('isbn_')) {
      resolvedDownloadUrl = await resolveArchiveOrgEpub(ocaid, client: _client);
    }

    if (resolvedDownloadUrl == null && cleanUrl.contains('/works/')) {
      try {
        final editionsUrl = '${cleanUrl.replaceAll('.json', '')}/editions.json?limit=10';
        final edRes = await _client.get(Uri.parse(editionsUrl), headers: _headers);
        if (edRes.statusCode == 200) {
          final edData = jsonDecode(edRes.body) as Map<String, dynamic>;
          final entries = edData['entries'] as List<dynamic>? ?? [];
          for (final entry in entries) {
            if (entry is! Map<String, dynamic>) continue;
            final edOcaid = entry['ocaid']?.toString();
            if (edOcaid != null && edOcaid.isNotEmpty && !edOcaid.startsWith('isbn_')) {
              final dl = await resolveArchiveOrgEpub(edOcaid, client: _client);
              if (dl != null) {
                resolvedDownloadUrl = dl;
                break;
              }
            }
          }
        }
      } catch (_) {}
    }

    return Novel(
      id: '${id}_${key.replaceAll('/', '_')}',
      sourceId: id,
      title: title,
      description: description,
      coverUrl: coverUrl,
      sourceUrl: novelUrl,
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: resolvedDownloadUrl,
      bookFormat: 'epub',
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
    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    return EpubService().loadChapterContent(chapterUrl);
  }
}
