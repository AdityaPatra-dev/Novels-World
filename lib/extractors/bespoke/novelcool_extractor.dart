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

/// Extractor for NovelCool (https://www.novelcool.com).
/// High-capacity international webnovel aggregator hosting 120,000+ translated
/// and original novels with full chapter archives and high-speed HTML delivery.
class NovelCoolExtractor implements NovelSource {
  @override
  final String id = 'novelcool';

  @override
  final String name = 'NovelCool';

  @override
  final String baseUrl = 'https://www.novelcool.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 120000;

  late final http.Client _client;

  NovelCoolExtractor({http.Client? client}) {
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (cert, host, port) => true;
      nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
      _client = IOClient(nativeHttpClient);
    }
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': baseUrl,
    };
    final cookie = WebViewSessionManager.instance.getCookieHeader(baseUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final url = page == 1
        ? '$baseUrl/category/popular.html'
        : '$baseUrl/category/popular_$page.html';
    return _fetchAndParseList(url);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final url = page == 1
        ? '$baseUrl/category/latest.html'
        : '$baseUrl/category/latest_$page.html';
    return _fetchAndParseList(url);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQ);
    final url = page == 1
        ? '$baseUrl/search/?wd=$encoded'
        : '$baseUrl/search/?wd=$encoded&page=$page';

    return _fetchAndParseList(url);
  }

  Future<List<Novel>> _fetchAndParseList(String url) async {
    String htmlBody = '';
    try {
      final resp = await _client.get(Uri.parse(url), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        htmlBody = resp.body;
      }
    } catch (_) {}

    if (htmlBody.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null) htmlBody = wvHtml;
    }

    if (htmlBody.isEmpty) {
      return [];
    }

    return _parseBooks(htmlBody);
  }

  List<Novel> _parseBooks(String htmlBody) {
    final doc = html_parser.parse(htmlBody);
    final items = doc.querySelectorAll('.book-item');
    final List<Novel> list = [];
    final seen = <String>{};

    for (final item in items) {
      // Exclude manga or comics to ensure only pure novels are ingested
      final typeText = item.querySelector('.book-type')?.text.trim().toLowerCase() ?? '';
      if (typeText.contains('manga') || typeText.contains('comic')) {
        continue;
      }

      final anchor = item.querySelector('.book-pic a, a[itemprop="url"], a');
      if (anchor == null) continue;

      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final fullUrl = Uri.parse(baseUrl).resolve(href).toString();
      if (seen.contains(fullUrl)) continue;

      final title = item.querySelector('.book-pic')?.attributes['title']?.trim() ??
          anchor.attributes['title']?.trim() ??
          anchor.text.trim();

      if (title.isEmpty || !TextCleaner.isValidNovelTitle(title, fullUrl)) {
        continue;
      }

      seen.add(fullUrl);

      final img = item.querySelector('img');
      String cover = '';
      if (img != null) {
        cover = img.attributes['lazy_url'] ??
            img.attributes['cover_url'] ??
            img.attributes['data-src'] ??
            img.attributes['src'] ??
            '';
        if (cover.contains('default_pic.jpg') || cover.startsWith('data:')) {
          cover = '';
        } else if (cover.isNotEmpty) {
          cover = Uri.parse(baseUrl).resolve(cover).toString();
        }
      }

      final slug = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
          fullUrl.hashCode.toString();

      list.add(
        Novel(
          id: '${id}_$slug',
          sourceId: id,
          title: title,
          author: 'Unknown Author',
          coverUrl: cover,
          sourceUrl: fullUrl,
        ),
      );
    }

    return list;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (TextCleaner.isGenreOrCategoryUrl(novelUrl)) {
      throw HttpException('Invalid novel URL: $novelUrl is a genre/category link.');
    }

    String body = '';
    try {
      final resp = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        body = resp.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load novel details from NovelCool ($novelUrl)');
    }

    final doc = html_parser.parse(body);

    final title = doc.querySelector('h1.bookinfo-title, .bookinfo-title')?.text.trim() ??
        doc.querySelector('title')?.text.split('-').first.trim() ??
        'Untitled';

    // Author
    var author = doc.querySelector('.bookinfo-author span[itemprop="creator"], .bookinfo-author a')?.text.trim() ??
        'Unknown Author';
    author = author.replaceAll(RegExp(r'^Author:\s*', caseSensitive: false), '').trim();
    if (author.isEmpty) author = 'Unknown Author';

    // Genres
    final genres = doc
        .querySelectorAll('.bookinfo-category-list a')
        .map((e) => e.text.trim())
        .where((g) => g.isNotEmpty)
        .toList();

    // Cover
    final img = doc.querySelector('.bookinfo-pic img, img[itemprop="image"]');
    String cover = '';
    if (img != null) {
      cover = img.attributes['lazy_url'] ??
          img.attributes['cover_url'] ??
          img.attributes['data-src'] ??
          img.attributes['src'] ??
          '';
      if (cover.contains('default_pic.jpg') || cover.startsWith('data:')) {
        cover = '';
      } else if (cover.isNotEmpty) {
        cover = Uri.parse(baseUrl).resolve(cover).toString();
      }
    }

    // Description
    final summaryEl = doc.querySelector('.bookinfo-summary span[itemprop="description"], .bookinfo-summary');
    String description = '';
    if (summaryEl != null) {
      description = summaryEl.text.trim();
      if (description.toLowerCase() == 'n/a') description = '';
    }

    final slug = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
        novelUrl.hashCode.toString();

    return Novel(
      id: '${id}_$slug',
      sourceId: id,
      title: title,
      author: author,
      description: description,
      coverUrl: cover,
      genres: genres,
      status: 'ONGOING',
      sourceUrl: novelUrl,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    String body = '';
    try {
      final resp = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        body = resp.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) return [];

    final doc = html_parser.parse(body);
    final chpLinks = doc.querySelectorAll('.chp-item a');
    final List<Chapter> chapters = [];

    final novelSlug = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
        novelUrl.hashCode.toString();
    final novelId = '${id}_$novelSlug';

    for (final link in chpLinks) {
      final href = link.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final chapterUrl = Uri.parse(baseUrl).resolve(href).toString();
      final title = link.querySelector('.chapter-item-headtitle')?.text.trim() ??
          link.querySelector('.chapter-item-title')?.text.trim() ??
          link.attributes['title']?.trim() ??
          link.text.trim();

      final chSlug = Uri.parse(chapterUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
          chapterUrl.hashCode.toString();
      final chId = '${id}_${novelSlug}_$chSlug';

      chapters.add(
        Chapter(
          id: chId,
          novelId: novelId,
          url: chapterUrl,
          title: title.isEmpty ? 'Chapter ${chapters.length + 1}' : title,
          chapterNumber: (chapters.length + 1).toDouble(),
        ),
      );
    }

    // NovelCool lists chapters in reverse order (newest to oldest).
    // Invert to chronological order (Chapter 1 first) for optimal reading experience.
    return chapters.reversed.toList();
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    String body = '';
    try {
      final resp = await _client.get(Uri.parse(chapterUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        body = resp.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(chapterUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load chapter content from $chapterUrl');
    }

    final doc = html_parser.parse(body);
    final paragraphs = <String>[];

    final pElements = doc.querySelectorAll('.overflow-hidden p, .chapter-reading-section-list p');
    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;

      // Filter out utility labels, ads, and report tags
      if (p.classes.contains('chapter-start-mark') ||
          p.classes.contains('chapter-end-mark') ||
          p.classes.contains('chapter-section-report') ||
          text.toLowerCase().contains('chapter end') ||
          text.contains('Please let us know < report >') ||
          text.contains('auto_novel_ads')) {
        continue;
      }

      paragraphs.add(text);
    }

    final segments = Uri.parse(chapterUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final chSlug = segments.isNotEmpty ? segments.last : chapterUrl.hashCode.toString();
    final novelSlug = segments.length > 1 ? segments[segments.length - 2] : 'novel';
    final novelId = '${id}_$novelSlug';
    final chapterId = '${id}_${novelSlug}_$chSlug';
    final rawText = paragraphs.join('\n\n');
    final title = doc.querySelector('h1, title')?.text.trim() ?? 'Chapter';

    return ChapterContent(
      chapterId: chapterId,
      novelId: novelId,
      title: title,
      rawText: rawText,
      paragraphs: paragraphs,
    );
  }
}
