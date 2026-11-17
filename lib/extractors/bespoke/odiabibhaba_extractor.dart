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

    try {
      final resp = await _client.get(Uri.parse('$baseUrl/api/books/$slug'), headers: _headers);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final b = (data['book'] ?? (data['books'] as List?)?.firstOrNull) as Map<String, dynamic>?;
        if (b != null) {
          final titleOr = b['title_or']?.toString() ?? '';
          final titleEn = b['title_en']?.toString() ?? slug;
          final title = titleOr.isNotEmpty ? titleOr : titleEn;

          final authorOr = b['author_or']?.toString() ?? '';
          final authorEn = b['author_en']?.toString() ?? 'ଓଡ଼ିଆ ଲେଖକ';
          final author = authorOr.isNotEmpty ? authorOr : authorEn;

          final cover = b['cover_url']?.toString() ?? '';
          final pdfPath = b['pdf_url']?.toString() ?? '/api/books/$slug/stream';
          final pdfUrl = pdfPath.startsWith('http') ? pdfPath : '$baseUrl$pdfPath';

          final category = b['category_or']?.toString() ?? b['category_en']?.toString() ?? 'ଇତିହାସ ଓ ସାହିତ୍ୟ';
          final year = b['year_or']?.toString() ?? b['year_en']?.toString() ?? '';
          final desc = year.isNotEmpty ? '$category ($year)' : category;

          return Novel(
            id: '${id}_$slug',
            sourceId: id,
            title: title,
            author: author,
            description: desc,
            coverUrl: cover,
            genres: const ['Odia', 'History', 'Heritage', 'Literature'],
            status: 'COMPLETED',
            sourceUrl: novelUrl,
            isFullBook: true,
            bookDownloadUrl: pdfUrl,
            bookFormat: 'pdf',
          );
        }
      }
    } catch (_) {}

    return Novel(
      id: '${id}_$slug',
      sourceId: id,
      title: slug.replaceAll('-', ' '),
      author: 'ଓଡ଼ିଆ ଲେଖକ',
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
    final slug = chapterUrl.split('/').last.trim();
    final paragraphs = [
      novel.title,
      'ରଚୟିତା: ${novel.author}',
      'ବିଭାଗ ଓ ବିବରଣୀ: ${novel.description}',
      'ଓଡ଼ିଆ ବିଭବ (Odia Bibhaba) ଏବଂ ସୃଜନିକା ପ୍ରକଳ୍ପ ଦ୍ୱାରା ଏହି ଅମୂଲ୍ୟ ଓଡ଼ିଆ ଗ୍ରନ୍ଥଟି ଡିଜିଟାଲ୍ ସଂସ୍କରଣ ଭାବରେ ସଂରକ୍ଷିତ ହୋଇଛି।',
      'ଏହି ପୁସ୍ତକଟି ମୂଳ ମୁଦ୍ରିତ ତଥା ପାଣ୍ଡୁଲିପି ପୃଷ୍ଠାଗୁଡ଼ିକ ସହିତ ସମ୍ପୂର୍ଣ୍ଣ ଡିଜିଟାଇଜ୍ ହୋଇ ପାଠକମାନଙ୍କ ଅଧ୍ୟୟନ ପାଇଁ ଉପଲବ୍ଧ।',
      'ମୂଳ ଡିଜିଟାଲ୍ PDF ର ସମସ୍ତ ପୃଷ୍ଠାଗୁଡ଼ିକୁ ସିଧାସଳଖ ଇନ୍-ଆପ୍ ବ୍ରାଉଜର୍ରେ ପୃଷ୍ଠା ଓଲଟାଇ ପଢ଼ିବା ପାଇଁ "Preview Online" ବଟନ୍ ବ୍ୟବହାର କରନ୍ତୁ କିମ୍ବା ସମ୍ପୂର୍ଣ୍ଣ ବହିଟିକୁ ଅଫଲାଇନ୍ ସଂରକ୍ଷଣ କରିବା ପାଇଁ "Download Entire Book" ବଟନ୍ ଚୟନ କରନ୍ତୁ।',
      'ଡିଜିଟାଲ୍ ଆର୍କାଇଭ୍ ଷ୍ଟ୍ରିମ୍ ଲିଙ୍କ୍: ${novel.bookDownloadUrl ?? "$baseUrl/api/books/$slug/stream"}',
    ];
    return ChapterContent(
      chapterId: '${id}_${novel.id}',
      novelId: novel.id,
      title: novel.title,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
