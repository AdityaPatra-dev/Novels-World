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

/// Bespoke Extractor for Hindwi eBooks (https://www.hindwi.org/ebooks).
/// Parses page-wise scanned JPEG books via the Rekhta eBooks image CDN.
class HindwiExtractor implements NovelSource {
  @override
  final String id = 'hindwi';

  @override
  final String name = 'Hindwi (हिन्दवी eBooks)';

  @override
  final String baseUrl = 'https://www.hindwi.org';

  @override
  final String lang = 'hi';

  @override
  String get iconUrl => '$baseUrl/content/images/favico.png';

  @override
  final int estimatedNovelCount = 2000;

  late final http.Client _client;
  final Map<String, ({String bookId, List<String> pages})> _bookPagesCache = {};

  HindwiExtractor({http.Client? client}) {
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
      throw HttpException('Failed to load $url from Hindwi.');
    }
    return htmlBody;
  }

  String _cleanUrl(String url) {
    final t = url.trim();
    if (t.isEmpty) return '';
    try {
      return Uri.parse(baseUrl).resolve(t).removeFragment().toString();
    } catch (_) {
      return t;
    }
  }

  String _toReaderUrl(String novelUrl) {
    // Convert /ebooks/detail/<slug>/ -> /ebooks/<slug>
    final uri = Uri.tryParse(novelUrl);
    final segs = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    if (segs.isNotEmpty) {
      return '$baseUrl/ebooks/${segs.last}';
    }
    return novelUrl;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = page > 1 ? '$baseUrl/ebooks?page=$page' : '$baseUrl/ebooks';
    final html = await _fetchHtml(targetUrl);
    return _parseEbookList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final pop = await getPopular(page: 1);
    final qLower = query.toLowerCase();
    return pop
        .where((n) => n.title.toLowerCase().contains(qLower) || n.author.toLowerCase().contains(qLower))
        .toList();
  }

  List<Novel> _parseEbookList(String html) {
    final doc = html_parser.parse(html);
    final novels = <Novel>[];
    final seen = <String>{};

    for (final a in doc.querySelectorAll('a[href*="/ebooks/"]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty || href == '/ebooks' || href.endsWith('/ebooks/')) continue;
      final fullUrl = _cleanUrl(href);
      final readerUrl = _toReaderUrl(fullUrl);
      if (seen.contains(readerUrl)) continue;

      final slug = Uri.tryParse(readerUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      if (slug.isEmpty || slug == 'ebooks') continue;

      var title = a.text.trim();
      if (title.isEmpty) {
        title = a.querySelector('img')?.attributes['alt']?.trim() ??
            slug.replaceAll('-ebooks', '').replaceAll('-', ' ');
      }
      if (title.isEmpty) continue;
      seen.add(readerUrl);

      final card = a.parent?.parent;
      final img = a.querySelector('img') ?? card?.querySelector('img');
      var coverUrl = '';
      if (img != null) {
        final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('data:')) coverUrl = _cleanUrl(src);
      }
      if (coverUrl.isEmpty) {
        coverUrl = 'https://www.rekhta.org/Images/EBooks/small_$slug.jpg';
      }

      novels.add(Novel(
        id: '${id}_$slug',
        sourceId: id,
        title: TextCleaner.cleanNovelTitle(title),
        author: 'हिन्दवी (Hindwi)',
        coverUrl: coverUrl,
        sourceUrl: readerUrl,
        genres: const ['Hindi Literature', 'Scanned Book'],
        status: 'Completed',
      ));
    }
    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final readerUrl = _toReaderUrl(novelUrl);
    final html = await _fetchHtml(readerUrl);
    final doc = html_parser.parse(html);

    var rawTitle = doc.querySelector('meta[property="og:title"]')?.attributes['content']?.trim() ??
        doc.querySelector('title')?.text.split('|').first.trim() ??
        doc.querySelector('h1')?.text.trim() ??
        'पुस्तक';
    if (rawTitle.toLowerCase().contains('search this ebook')) {
      rawTitle = doc.querySelector('title')?.text.split('|').first.trim() ?? 'पुस्तक';
    }
    rawTitle = rawTitle.split('|').first.trim();
    final title = TextCleaner.cleanNovelTitle(rawTitle);
    final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
    final desc = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ?? '';
    final slug = Uri.tryParse(readerUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';

    return Novel(
      id: '${id}_$slug',
      sourceId: id,
      title: title,
      author: 'हिन्दवी (Hindwi)',
      coverUrl: cover.isNotEmpty ? _cleanUrl(cover) : '',
      sourceUrl: readerUrl,
      description: desc,
      genres: const ['Hindi Literature', 'Scanned Book'],
      status: 'Completed',
    );
  }

  Future<({String bookId, List<String> pages})> _loadBookPages(String readerUrl) async {
    if (_bookPagesCache.containsKey(readerUrl)) {
      return _bookPagesCache[readerUrl]!;
    }
    final html = await _fetchHtml(readerUrl);
    final bookIdMatch = RegExp(r'bookId\s*=\s*"([^"]+)"').firstMatch(html);
    final pagesMatch = RegExp(r'var\s+pages\s*=\s*\[(.*?)\]', dotAll: true).firstMatch(html);

    final bookId = bookIdMatch?.group(1) ?? '';
    final pagesRaw = pagesMatch?.group(1) ?? '';
    final pages = RegExp(r'"([^"]+\.(?:jpg|jpeg|png|webp))"', caseSensitive: false)
        .allMatches(pagesRaw)
        .map((m) => m.group(1)!)
        .toList();

    final result = (bookId: bookId, pages: pages);
    if (bookId.isNotEmpty && pages.isNotEmpty) {
      _bookPagesCache[readerUrl] = result;
    }
    return result;
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final readerUrl = _toReaderUrl(novelUrl);
    final info = await _loadBookPages(readerUrl);
    if (info.bookId.isEmpty || info.pages.isEmpty) {
      return [];
    }

    const int pagesPerChapter = 20;
    final chapters = <Chapter>[];
    final slug = Uri.tryParse(readerUrl)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'book';
    final novelId = '${id}_$slug';

    for (int start = 0; start < info.pages.length; start += pagesPerChapter) {
      final end = (start + pagesPerChapter) > info.pages.length ? info.pages.length : (start + pagesPerChapter);
      final chNum = (chapters.length + 1);
      chapters.add(Chapter(
        id: '${novelId}_p${start + 1}_$end',
        novelId: novelId,
        title: 'Pages ${start + 1}–$end',
        chapterNumber: chNum.toDouble(),
        url: '$readerUrl#p=${start + 1}-$end',
      ));
    }

    onBatchLoaded?.call(chapters);
    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final readerUrl = _toReaderUrl(chapterUrl.split('#').first);
    final info = await _loadBookPages(readerUrl);
    if (info.bookId.isEmpty || info.pages.isEmpty) {
      throw Exception('Book pages not found on $chapterUrl');
    }

    int startIdx = 0;
    int endIdx = info.pages.length;
    final fragMatch = RegExp(r'#p=(\d+)-(\d+)').firstMatch(chapterUrl);
    if (fragMatch != null) {
      startIdx = (int.parse(fragMatch.group(1)!) - 1).clamp(0, info.pages.length - 1);
      endIdx = int.parse(fragMatch.group(2)!).clamp(startIdx + 1, info.pages.length);
    }

    final slice = info.pages.sublist(startIdx, endIdx);
    final paragraphs = slice
        .map((p) => '[IMAGE:https://ebooksapi.rekhta.org/images/${info.bookId}/$p]')
        .toList();

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: id,
      title: 'Pages ${startIdx + 1}–$endIdx',
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
