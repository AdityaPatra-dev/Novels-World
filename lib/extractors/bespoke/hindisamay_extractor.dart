import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for Hindi Samay (http://www.hindisamay.com).
/// Flagship portal by Mahatma Gandhi Antarrashtriya Hindi Vishwavidyalaya
/// featuring thousands of classic and modern Hindi novels, stories, memoirs, and essays.
class HindiSamayExtractor implements NovelSource {
  @override
  final String id = 'hindisamay';

  @override
  final String name = 'Hindi Samay (हिंदी समय)';

  @override
  final String baseUrl = 'http://www.hindisamay.com';

  @override
  final String lang = 'hi';

  @override
  final String iconUrl = 'http://www.hindisamay.com/favicon.ico';

  @override
  final int estimatedNovelCount = 10000;

  late final http.Client _client;

  HindiSamayExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'hi,en-US,en;q=0.9',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    const authorIds = [1152, 1275, 1182, 1355, 1157, 1262];
    final authorId = authorIds[(page - 1) % authorIds.length];

    final results = <Novel>[];
    if (page == 1) {
      final homeWorks = await _fetchWorksFromUrl('$baseUrl/default.aspx');
      results.addAll(homeWorks);
    }

    final authorWorks = await _fetchWorksFromUrl('$baseUrl/writer/writer_details_n.aspx?id=$authorId');
    results.addAll(authorWorks);

    final seen = <String>{};
    return results.where((n) => seen.add(n.sourceUrl)).toList();
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    const authorIds = [1182, 1355, 1157, 1262, 1539, 1246];
    final authorId = authorIds[(page - 1) % authorIds.length];

    final authorWorks = await _fetchWorksFromUrl('$baseUrl/writer/writer_details_n.aspx?id=$authorId');
    if (authorWorks.isNotEmpty) return authorWorks;

    return _fetchWorksFromUrl('$baseUrl/default.aspx');
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final popular = await getPopular(page: 1);
    final latest = await getLatest(page: 1);

    final combined = <String, Novel>{};
    for (final n in [...popular, ...latest]) {
      combined[n.sourceUrl] = n;
    }

    return combined.values.where((n) {
      return n.title.toLowerCase().contains(cleanQuery) ||
          n.author.toLowerCase().contains(cleanQuery) ||
          n.description.toLowerCase().contains(cleanQuery);
    }).toList();
  }

  Future<List<Novel>> _fetchWorksFromUrl(String url) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final List<Novel> novels = [];
      final seenUrls = <String>{};

      final anchors = doc.querySelectorAll('a[href*=".cspx"], a[href*="/content/"]');
      for (final a in anchors) {
        final href = a.attributes['href'] ?? '';
        final text = a.text.trim();
        if (text.isEmpty || href.isEmpty || text.length < 2) continue;
        if (text.contains('क्लिक करें') || text.contains('मुखपृष्ठ') || text.contains('आगे')) continue;

        final fullUrl = href.startsWith('http') ? href : '$baseUrl/${href.replaceFirst(RegExp(r'^/+'), '')}';
        if (!seenUrls.add(fullUrl)) continue;

        var title = text.replaceAll('(ई-पुस्तक)', '').trim();
        var author = 'Unknown Author';

        if (title.contains('-')) {
          final parts = title.split('-').map((s) => s.trim()).toList();
          if (parts.length >= 3) {
            author = parts[0];
            title = parts.sublist(2).join(' - ');
          } else if (parts.length == 2) {
            author = parts[0];
            title = parts[1];
          }
        }

        novels.add(Novel(
          id: '${id}_${fullUrl.hashCode.abs()}',
          sourceId: id,
          title: title,
          author: author,
          description: 'Hindi literary classic on Hindi Samay.',
          coverUrl: 'https://www.hindisamay.com/images/logo.png',
          genres: const ['Hindi', 'Literature', 'Upanyas'],
          status: 'COMPLETED',
          sourceUrl: fullUrl,
        ));
      }

      return novels;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to load novel details');
      }

      final doc = html_parser.parse(response.body);
      final rawTitle = doc.querySelector('title')?.text.trim() ?? 'Hindi Samay';

      var title = rawTitle;
      var author = 'Unknown Author';
      if (rawTitle.contains('-')) {
        final parts = rawTitle.split('-').map((s) => s.trim()).toList();
        author = parts[0];
        title = parts.sublist(1).join(' - ');
      }

      final firstP = doc.querySelector('p')?.text.trim() ?? '';
      final snippet = firstP.length > 200 ? '${firstP.substring(0, 200)}...' : firstP;

      return Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: snippet,
        coverUrl: 'https://www.hindisamay.com/images/logo.png',
        genres: const ['Hindi', 'Literature'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      );
    } catch (_) {
      return Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: 'Hindi Novel',
        author: 'Unknown Author',
        coverUrl: 'https://www.hindisamay.com/images/logo.png',
        sourceUrl: novelUrl,
      );
    }
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final List<Chapter> chapters = [];
      final seenUrls = <String>{};
      final novelId = '${id}_${novelUrl.hashCode.abs()}';

      final idMatch = RegExp(r'/content/(\d+)/').firstMatch(novelUrl);
      final contentId = idMatch?.group(1);

      final anchors = doc.querySelectorAll('a[href*="/content/"], a[href*=".cspx"]');
      for (final a in anchors) {
        final href = a.attributes['href'] ?? '';
        final text = a.text.trim();
        if (text.isEmpty || href.isEmpty) continue;

        if (contentId != null && !href.contains('/content/$contentId/')) {
          continue;
        }

        if (text.contains('आगे') || text.contains('पीछे') || text.contains('क्लिक करें')) {
          continue;
        }

        final fullUrl = href.startsWith('http') ? href : '$baseUrl/${href.replaceFirst(RegExp(r'^/+'), '')}';
        if (!seenUrls.add(fullUrl)) continue;

        final numMatch = RegExp(r'(\d+)').firstMatch(text);
        final chapNum = numMatch != null ? double.tryParse(numMatch.group(1)!) : (chapters.length + 1).toDouble();

        chapters.add(Chapter(
          id: '${id}_${fullUrl.hashCode.abs()}',
          novelId: novelId,
          title: text,
          url: fullUrl,
          chapterNumber: chapNum,
        ));
      }

      if (chapters.isEmpty) {
        chapters.add(Chapter(
          id: '${id}_${novelUrl.hashCode.abs()}',
          novelId: novelId,
          title: 'पूर्ण रचना (Full Work)',
          url: novelUrl,
          chapterNumber: 1.0,
        ));
      }

      onBatchLoaded?.call(chapters);
      return chapters;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter content from $chapterUrl');
    }

    final doc = html_parser.parse(response.body);
    final title = doc.querySelector('title')?.text.trim() ?? 'Hindi Samay Chapter';

    final paragraphs = <String>[];
    final allP = doc.querySelectorAll('p');

    for (final p in allP) {
      final text = p.text.trim();
      if (text.length > 50 && !text.startsWith('अनुक्रम')) {
        final lines = text.split('\n');
        for (final l in lines) {
          final t = l.trim();
          if (t.length > 10) {
            paragraphs.add(t);
          }
        }
      }
    }

    if (paragraphs.isEmpty) {
      paragraphs.add(doc.body?.text.trim() ?? 'No text available');
    }

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: '${id}_${chapterUrl.hashCode.abs()}',
      title: title,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
