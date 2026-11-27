import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke Extractor for Bharat Discovery / Bharatkosh (https://bharatdiscovery.org).
/// MediaWiki-powered Hindi literature and cultural archive.
class BharatDiscoveryExtractor implements NovelSource {
  @override
  final String id = 'bharatdiscovery';

  @override
  final String name = 'Bharat Discovery (भारतकोश)';

  @override
  final String baseUrl = 'https://bharatdiscovery.org';

  @override
  final String lang = 'hi';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 10000;

  late final http.Client _client;

  BharatDiscoveryExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
        'User-Agent': WebViewSessionManager.defaultUserAgent,
        'Accept': 'application/json, text/html, */*',
        'Accept-Language': 'hi-IN,hi;q=0.9,en-US;q=0.8,en;q=0.7',
        'Referer': '$baseUrl/',
      };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final categories = [
      'Category:हिन्दी_साहित्य',
      'Category:भारतीय_साहित्य',
      'Category:हिन्दी_कविता',
    ];
    final cat = categories[(page - 1) % categories.length];
    final apiUrl =
        '$baseUrl/w/api.php?action=query&generator=categorymembers&gcmtitle=${Uri.encodeComponent(cat)}&gcmlimit=25&gcmnamespace=0&prop=pageimages|extracts&piprop=thumbnail&pithumbsize=400&exintro=1&explaintext=1&exsentences=2&format=json';

    final resp = await _client.get(Uri.parse(apiUrl), headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw HttpException('Failed to load Bharat Discovery catalog: HTTP ${resp.statusCode}');
    }
    return _parsePagesJson(resp.body);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final q = Uri.encodeComponent(query.trim());
    final apiUrl =
        '$baseUrl/w/api.php?action=query&generator=search&gsrsearch=$q&gsrlimit=25&gsrnamespace=0&prop=pageimages|extracts&piprop=thumbnail&pithumbsize=400&exintro=1&explaintext=1&exsentences=2&format=json';
    final resp = await _client.get(Uri.parse(apiUrl), headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];
    return _parsePagesJson(resp.body);
  }

  List<Novel> _parsePagesJson(String body) {
    final data = jsonDecode(body);
    final pages = data['query']?['pages'];
    if (pages is! Map) return [];

    final novels = <Novel>[];
    for (final entry in pages.values) {
      if (entry is! Map) continue;
      final title = (entry['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final pageId = entry['pageid']?.toString() ?? title.hashCode.abs().toString();
      final slug = Uri.encodeComponent(title.replaceAll(' ', '_'));
      final sourceUrl = '$baseUrl/india/$slug';
      final thumb = entry['thumbnail']?['source']?.toString() ?? '';
      final extract = entry['extract']?.toString().trim() ?? '';

      novels.add(Novel(
        id: '${id}_$pageId',
        sourceId: id,
        title: TextCleaner.cleanNovelTitle(title),
        author: 'भारतकोश (Bharatkosh)',
        coverUrl: thumb,
        sourceUrl: sourceUrl,
        description: extract,
        genres: const ['Hindi Literature', 'Archive'],
        status: 'Completed',
      ));
    }
    return novels;
  }

  String _extractPageTitle(String novelUrl) {
    final uri = Uri.tryParse(novelUrl);
    final segs = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    if (segs.isNotEmpty) {
      return segs.last.replaceAll('_', ' ');
    }
    return '';
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final pageTitle = _extractPageTitle(novelUrl);
    final apiUrl =
        '$baseUrl/w/api.php?action=query&titles=${Uri.encodeComponent(pageTitle)}&prop=pageimages|extracts&piprop=thumbnail&pithumbsize=500&exintro=1&explaintext=1&format=json';
    final resp = await _client.get(Uri.parse(apiUrl), headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      final list = _parsePagesJson(resp.body);
      if (list.isNotEmpty) return list.first;
    }
    return Novel(
      id: '${id}_${novelUrl.hashCode.abs()}',
      sourceId: id,
      title: pageTitle.isNotEmpty ? pageTitle : 'भारतकोश',
      author: 'भारतकोश (Bharatkosh)',
      coverUrl: '',
      sourceUrl: novelUrl,
      genres: const ['Hindi Literature', 'Archive'],
      status: 'Completed',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final ch = [
      Chapter(
        id: '${id}_${novelUrl.hashCode.abs()}_1',
        novelId: '${id}_${novelUrl.hashCode.abs()}',
        title: 'संपूर्ण लेख / रचना (Full Text)',
        chapterNumber: 1.0,
        url: novelUrl,
      ),
    ];
    onBatchLoaded?.call(ch);
    return ch;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final pageTitle = _extractPageTitle(chapterUrl);
    final apiUrl =
        '$baseUrl/w/api.php?action=parse&page=${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}&format=json&prop=text';
    final resp = await _client.get(Uri.parse(apiUrl), headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw HttpException('Failed to load article from Bharat Discovery');
    }
    final decoded = jsonDecode(resp.body);
    final html = decoded['parse']?['text']?['*']?.toString() ?? '';
    final doc = html_parser.parse(html);

    doc
        .querySelectorAll('.infobox, .navbox, #toc, .toc, .catlinks, .printfooter, table, script, style')
        .forEach((e) => e.remove());

    final paragraphs = doc
        .querySelectorAll('p')
        .map((p) => p.text.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) {
      throw Exception('Empty content on $chapterUrl');
    }

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}_1',
      novelId: id,
      title: pageTitle.isNotEmpty ? pageTitle : 'भारतकोश',
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
