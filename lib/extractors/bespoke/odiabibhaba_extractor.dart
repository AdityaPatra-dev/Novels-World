import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for Odia Bibhaba (https://odiabibhaba.in).
/// Odisha's largest and most comprehensive digital archive. Over 10,000+ digitized books
/// covering Indian & Odisha history, Mukunda Deva chronicles, Paika rebellion records,
/// rare dictionaries, classical literature, and historic periodicals.
class OdiaBibhabaExtractor implements NovelSource {
  @override
  final String id = 'odiabibhaba';

  @override
  final String name = 'Odia Bibhaba (ଓଡ଼ିଆ ବିଭବ)';

  @override
  final String baseUrl = 'https://odiabibhaba.in';

  @override
  final String lang = 'or';

  @override
  final String iconUrl = 'https://odiabibhaba.in/favicon.ico';

  @override
  final int estimatedNovelCount = 10000;

  late final http.Client _client;

  OdiaBibhabaExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'application/json,text/html,*/*;q=0.8',
    'Accept-Language': 'or,en-US,en;q=0.9',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return _fetchBooks('/api/books?page=$page');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final targetPage = page + 4;
    return _fetchBooks('/api/books?page=$targetPage');
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQuery);
    return _fetchBooks('/api/books?search=$encoded&page=$page');
  }

  Future<List<Novel>> _fetchBooks(String endpoint) async {
    try {
      final url = '$baseUrl$endpoint';
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final booksList = data['books'] as List<dynamic>? ?? [];

      return booksList.map((item) {
        final map = item as Map<String, dynamic>;
        final slug = map['slug']?.toString() ?? '';
        final titleOr = map['title_or']?.toString() ?? '';
        final titleEn = map['title_en']?.toString() ?? slug;
        final title = titleOr.isNotEmpty ? titleOr : titleEn;

        final authorOr = map['author_or']?.toString() ?? '';
        final authorEn = map['author_en']?.toString() ?? 'Unknown Author';
        final author = authorOr.isNotEmpty ? authorOr : authorEn;

        final coverUrl = map['cover_url']?.toString() ?? '';
        final pdfPath = map['pdf_url']?.toString() ?? '/api/books/$slug/stream';
        final pdfUrl = pdfPath.startsWith('http') ? pdfPath : '$baseUrl$pdfPath';

        final category = map['category_or']?.toString() ?? map['category_en']?.toString() ?? 'ଇତିହାସ ଓ ସାହିତ୍ୟ';
        final year = map['year_or']?.toString() ?? map['year_en']?.toString() ?? '';
        final desc = year.isNotEmpty ? '$category ($year)' : category;

        final novelUrl = '$baseUrl/or/books/$slug';

        return Novel(
          id: '${id}_$slug',
          sourceId: id,
          title: title,
          author: author,
          description: desc,
          coverUrl: coverUrl,
          genres: const ['Odia', 'History', 'Heritage', 'Literature'],
          status: 'COMPLETED',
          sourceUrl: novelUrl,
          isFullBook: true,
          bookDownloadUrl: pdfUrl,
          bookFormat: 'pdf',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final slug = novelUrl.split('/').last.trim();
    final directPdfUrl = '$baseUrl/api/books/$slug/stream';

    // Try finding in API
    try {
      final searchResp = await _client.get(Uri.parse('$baseUrl/api/books?search=$slug'), headers: _headers);
      if (searchResp.statusCode == 200) {
        final data = jsonDecode(searchResp.body) as Map<String, dynamic>;
        final books = data['books'] as List<dynamic>? ?? [];
        if (books.isNotEmpty) {
          final b = books.first as Map<String, dynamic>;
          final title = b['title_or']?.toString() ?? b['title_en']?.toString() ?? slug;
          final author = b['author_or']?.toString() ?? b['author_en']?.toString() ?? 'Unknown';
          final cover = b['cover_url']?.toString() ?? '';
          return Novel(
            id: '${id}_$slug',
            sourceId: id,
            title: title,
            author: author,
            description: 'ଓଡ଼ିଆ ବିଭବ ଡିଜିଟାଲ ପୁସ୍ତକ ସମ୍ଭାର (Odia Heritage Digital Collection)',
            coverUrl: cover,
            genres: const ['Odia', 'History', 'Literature'],
            status: 'COMPLETED',
            sourceUrl: novelUrl,
            isFullBook: true,
            bookDownloadUrl: directPdfUrl,
            bookFormat: 'pdf',
          );
        }
      }
    } catch (_) {}

    return Novel(
      id: '${id}_$slug',
      sourceId: id,
      title: slug.replaceAll('-', ' '),
      author: 'Unknown Author',
      description: 'ଓଡ଼ିଆ ବିଭବ ଡିଜିଟାଲ ପୁସ୍ତକ',
      sourceUrl: novelUrl,
      isFullBook: true,
      bookDownloadUrl: directPdfUrl,
      bookFormat: 'pdf',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final slug = novelUrl.split('/').last.trim();
    final single = [
      Chapter(
        id: '${id}_$slug',
        novelId: '${id}_$slug',
        title: 'ସମ୍ପୂର୍ଣ୍ଣ ପୁସ୍ତକ (Complete Book PDF)',
        url: novelUrl,
        chapterNumber: 1.0,
      ),
    ];
    onBatchLoaded?.call(single);
    return single;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final novel = await getNovelDetails(chapterUrl);
    final text = '${novel.title}\n\nଲେଖକ: ${novel.author}\n\nବିବରଣୀ: ${novel.description}\n\nଡାଉନଲୋଡ଼ ଲିଙ୍କ: ${novel.bookDownloadUrl ?? "Direct PDF Stream"}';
    return ChapterContent(
      chapterId: '${id}_${novel.id}',
      novelId: novel.id,
      title: novel.title,
      rawText: text,
      paragraphs: [
        novel.title,
        'ଲେଖକ: ${novel.author}',
        novel.description,
        'ଏହି ପୁସ୍ତକଟି ସମ୍ପୂର୍ଣ୍ଣ PDF ଆକାରରେ ପଢ଼ିବା ପାଇଁ ଉପଲବ୍ଧ।',
      ],
    );
  }
}
