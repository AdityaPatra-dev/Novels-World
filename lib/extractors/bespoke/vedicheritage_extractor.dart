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

/// Bespoke Extractor for Vedic Heritage Portal (https://vedicheritage.gov.in).
/// Extracts digitized flipbook volumes (JPEG page scans) across Brahmanas, Aranyakas, and Upanishads.
class VedicHeritageExtractor implements NovelSource {
  @override
  final String id = 'vedicheritage';

  @override
  final String name = 'Vedic Heritage Portal';

  @override
  final String baseUrl = 'https://vedicheritage.gov.in';

  @override
  final String lang = 'hi';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 200;

  late final http.Client _client;
  List<Novel>? _cachedCatalog;
  final Map<String, List<String>> _flipbookPagesCache = {};

  VedicHeritageExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
        'User-Agent': WebViewSessionManager.defaultUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'hi-IN,hi;q=0.9,en-US;q=0.8,en;q=0.7',
        'Referer': '$baseUrl/',
      };

  Future<String> _fetchHtml(String url) async {
    String htmlBody = '';
    try {
      final resp = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) htmlBody = resp.body;
    } catch (_) {}

    if (htmlBody.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null) htmlBody = wvHtml;
    }
    if (htmlBody.isEmpty) {
      throw HttpException('Failed to load $url from Vedic Heritage.');
    }
    return htmlBody;
  }

  String _normalizeFlipbookUrl(String rawUrl) {
    var clean = rawUrl.split('#').first.trim();
    if (clean.startsWith('http://')) {
      clean = clean.replaceFirst('http://', 'https://');
    }
    if (!clean.startsWith('http')) {
      clean = '$baseUrl${clean.startsWith('/') ? '' : '/'}$clean';
    }
    if (!clean.endsWith('/')) clean = '$clean/';
    return clean;
  }

  Future<List<Novel>> _loadCatalog() async {
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      return _cachedCatalog!;
    }

    final homeHtml = await _fetchHtml('$baseUrl/');
    final homeDoc = html_parser.parse(homeHtml);

    final sectionUrls = <String>{};
    for (final a in homeDoc.querySelectorAll('a[href*="/brahmanas/"], a[href*="/aranyakas/"], a[href*="/upanishads/"]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final full = href.startsWith('http') ? href : '$baseUrl$href';
      final segs = Uri.tryParse(full)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
      if (segs.length >= 2) {
        sectionUrls.add(full);
      }
    }

    final novels = <Novel>[];
    final seenFlipbooks = <String>{};

    final targetSections = sectionUrls.take(15).toList();
    final bodies = await Future.wait(
      targetSections.map((u) => _fetchHtml(u).then<String?>((v) => v).catchError((_) => null)),
    );

    for (final body in bodies) {
      if (body == null || body.isEmpty) continue;
      final doc = html_parser.parse(body);
      final pageTitle = doc.querySelector('h1')?.text.trim() ?? '';

      for (final a in doc.querySelectorAll('a[href*="/flipbook/"]')) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final fbUrl = _normalizeFlipbookUrl(href);
        if (seenFlipbooks.contains(fbUrl)) continue;
        seenFlipbooks.add(fbUrl);

        final slug = Uri.tryParse(fbUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'book';
        var title = a.text.trim();
        if (title.isEmpty || title.toLowerCase().contains('view') || title.toLowerCase().contains('read')) {
          title = pageTitle.isNotEmpty ? '$pageTitle ($slug)' : slug.replaceAll('_', ' ');
        }

        novels.add(Novel(
          id: '${id}_$slug',
          sourceId: id,
          title: TextCleaner.cleanNovelTitle(title.replaceAll('_', ' ')),
          author: 'IGNCA / Vedic Heritage',
          coverUrl: '${fbUrl}img/1.jpg',
          sourceUrl: fbUrl,
          genres: const ['Vedic Literature', 'Scanned Book'],
          status: 'Completed',
        ));
      }
    }

    // Resolve exact first page image (img/0001.jpg vs img/1.jpg) for catalog previews
    await Future.wait(novels.map((n) async {
      try {
        await _loadFlipbookPages(n.sourceUrl);
      } catch (_) {}
    }));

    final resolved = novels.map((n) {
      final pages = _flipbookPagesCache[n.sourceUrl];
      if (pages != null && pages.isNotEmpty) {
        return Novel(
          id: n.id,
          sourceId: n.sourceId,
          title: n.title,
          author: n.author,
          coverUrl: '${n.sourceUrl}${pages.first}',
          sourceUrl: n.sourceUrl,
          genres: n.genres,
          status: n.status,
        );
      }
      return n;
    }).toList();

    _cachedCatalog = resolved;
    return resolved;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final all = await _loadCatalog();
    const pageSize = 25;
    final start = (page - 1) * pageSize;
    if (start >= all.length) return [];
    return all.skip(start).take(pageSize).toList();
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final all = await _loadCatalog();
    final qLower = query.toLowerCase();
    return all.where((n) => n.title.toLowerCase().contains(qLower)).toList();
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final fbUrl = _normalizeFlipbookUrl(novelUrl);
    final slug = Uri.tryParse(fbUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'book';
    final html = await _fetchHtml(fbUrl);
    final doc = html_parser.parse(html);
    final rawTitle = doc.querySelector('title')?.text.trim() ?? '';
    final cleanSlugTitle = slug.replaceAll('_', ' ');
    final title = (rawTitle.isNotEmpty && rawTitle.toLowerCase() != 'flipbook') ? rawTitle : cleanSlugTitle;

    return Novel(
      id: '${id}_$slug',
      sourceId: id,
      title: TextCleaner.cleanNovelTitle(title),
      author: 'IGNCA / Vedic Heritage',
      coverUrl: '${fbUrl}img/1.jpg',
      sourceUrl: fbUrl,
      genres: const ['Vedic Literature', 'Scanned Book'],
      status: 'Completed',
    );
  }

  Future<List<String>> _loadFlipbookPages(String fbUrl) async {
    if (_flipbookPagesCache.containsKey(fbUrl)) {
      return _flipbookPagesCache[fbUrl]!;
    }
    final html = await _fetchHtml(fbUrl);
    final seen = <String>{};
    final pages = <String>[];
    for (final m in RegExp(r'img/(\d+\.(?:jpg|jpeg|png|webp))', caseSensitive: false).allMatches(html)) {
      final p = 'img/${m.group(1)!}';
      if (seen.add(p)) {
        pages.add(p);
      }
    }
    if (pages.isNotEmpty) {
      _flipbookPagesCache[fbUrl] = pages;
    }
    return pages;
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final fbUrl = _normalizeFlipbookUrl(novelUrl);
    final pages = await _loadFlipbookPages(fbUrl);
    if (pages.isEmpty) return [];

    const int pagesPerChapter = 20;
    final chapters = <Chapter>[];
    final slug = Uri.tryParse(fbUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'book';
    final novelId = '${id}_$slug';

    for (int start = 0; start < pages.length; start += pagesPerChapter) {
      final end = (start + pagesPerChapter) > pages.length ? pages.length : (start + pagesPerChapter);
      final chNum = chapters.length + 1;
      chapters.add(Chapter(
        id: '${novelId}_p${start + 1}_$end',
        novelId: novelId,
        title: 'Pages ${start + 1}–$end',
        chapterNumber: chNum.toDouble(),
        url: '$fbUrl#p=${start + 1}-$end',
      ));
    }

    onBatchLoaded?.call(chapters);
    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final fbUrl = _normalizeFlipbookUrl(chapterUrl.split('#').first);
    final pages = await _loadFlipbookPages(fbUrl);
    if (pages.isEmpty) {
      throw Exception('Flipbook pages not found on $chapterUrl');
    }

    int startIdx = 0;
    int endIdx = pages.length;
    final fragMatch = RegExp(r'#p=(\d+)-(\d+)').firstMatch(chapterUrl);
    if (fragMatch != null) {
      startIdx = (int.parse(fragMatch.group(1)!) - 1).clamp(0, pages.length - 1);
      endIdx = int.parse(fragMatch.group(2)!).clamp(startIdx + 1, pages.length);
    }

    final slice = pages.sublist(startIdx, endIdx);
    final paragraphs = slice.map((p) => '[IMAGE:$fbUrl$p]').toList();

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: id,
      title: 'Pages ${startIdx + 1}–$endIdx',
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
