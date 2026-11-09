import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke extractor for Internet Archive (https://archive.org).
/// World's largest digital library with millions of public domain texts,
/// community uploads, and complete books with direct DRM-free EPUB streams.
class InternetArchiveExtractor implements NovelSource {
  @override
  final String id = 'internet_archive';

  @override
  final String name = 'Internet Archive';

  @override
  final String baseUrl = 'https://archive.org';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://archive.org/favicon.ico';

  @override
  final int estimatedNovelCount = 500000;

  late final http.Client _client;

  InternetArchiveExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'application/json,text/html,*/*;q=0.8',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return search('classic fiction', page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return search('novel', page: page);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQuery);
    // Target open access texts with EPUB format, excluding controlled digital lending (inlibrary)
    // and excluding encrypted LCP / ACS DRM formats that require lending borrow credentials (401)
    final url = '$baseUrl/advancedsearch.php?q=($encoded)+AND+mediatype:(texts)+AND+format:(EPUB)+AND+-format:(%22LCP+Encrypted+EPUB%22)+AND+-format:(%22ACS+Encrypted+PDF%22)+AND+-format:(%22ACS+Encrypted+EPUB%22)+AND+-collection:(inlibrary)&fl[]=identifier,title,creator,description,downloads,format&sort[]=downloads+desc&rows=25&page=$page&output=json';

    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['response']?['docs'] as List<dynamic>? ?? [];
      return parseDocs(docs);
    } catch (_) {
      return [];
    }
  }

  /// Parses Archive.org search docs into full book Novel models
  List<Novel> parseDocs(List<dynamic> docs) {
    final List<Novel> results = [];
    for (final doc in docs) {
      final identifier = doc['identifier']?.toString() ?? '';
      if (identifier.isEmpty) continue;

      final rawTitle = doc['title']?.toString() ?? identifier;
      final title = TextCleaner.cleanNovelTitle(rawTitle);

      var author = 'Unknown Author';
      final creator = doc['creator'];
      if (creator is List && creator.isNotEmpty) {
        author = creator.first.toString().trim();
      } else if (creator is String && creator.trim().isNotEmpty) {
        author = creator.trim();
      }

      final desc = doc['description']?.toString() ?? '';
      final coverUrl = '$baseUrl/services/img/$identifier';
      final novelUrl = '$baseUrl/details/$identifier';
      final downloadUrl = '$baseUrl/download/$identifier/$identifier.epub';

      results.add(Novel(
        id: '${id}_$identifier',
        sourceId: id,
        title: title,
        author: author,
        description: desc,
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

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final uri = Uri.parse(novelUrl);
    final identifier = uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    if (identifier.isEmpty) {
      throw Exception('Invalid Internet Archive URL: $novelUrl');
    }

    final metaUrl = '$baseUrl/metadata/$identifier';
    final response = await _client.get(Uri.parse(metaUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Internet Archive metadata for $identifier');
    }

    final meta = jsonDecode(response.body) as Map<String, dynamic>;
    final metadata = meta['metadata'] as Map<String, dynamic>? ?? {};
    final files = meta['files'] as List<dynamic>? ?? [];

    final title = metadata['title']?.toString() ?? identifier;
    final author = metadata['creator']?.toString() ?? 'Unknown Author';
    final description = metadata['description']?.toString() ?? '';
    final coverUrl = '$baseUrl/services/img/$identifier';

    // Find actual unencrypted EPUB filename
    String? epubName;
    for (final f in files) {
      if (f is! Map<String, dynamic>) continue;
      final name = f['name']?.toString() ?? '';
      final format = f['format']?.toString() ?? '';
      final isPrivate = f['private']?.toString().toLowerCase() == 'true';
      if (isPrivate) continue;

      if (format.toUpperCase() == 'EPUB' ||
          (name.toLowerCase().endsWith('.epub') && !name.toLowerCase().contains('_lcp'))) {
        epubName = name;
        break;
      }
    }

    final downloadUrl = epubName != null
        ? '$baseUrl/download/$identifier/${Uri.encodeComponent(epubName)}'
        : '$baseUrl/download/$identifier/$identifier.epub';

    return Novel(
      id: '${id}_$identifier',
      sourceId: id,
      title: TextCleaner.cleanNovelTitle(title),
      author: author,
      description: description,
      coverUrl: coverUrl,
      sourceUrl: novelUrl,
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: downloadUrl,
      bookFormat: 'epub',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    // For whole-book sources, the book will be unpacked upon 1-tap download
    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    throw UnsupportedError('Internet Archive chapters are unpacked locally via whole-book EPUB download.');
  }
}
