import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke extractor for vdoc.pub (https://vdoc.pub).
/// Digital archive of complete digital books, fantasy, sci-fi, and literature.
/// Utilizes automated background cookie synchronization via WebViewSessionManager
/// to bypass Cloudflare Turnstile without user interruption.
class VdocPubExtractor implements NovelSource {
  @override
  final String id = 'vdocpub';

  @override
  final String name = 'vdoc.pub';

  @override
  final String baseUrl = 'https://vdoc.pub';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://vdoc.pub/favicon.ico';

  @override
  final int estimatedNovelCount = 150000;

  late final http.Client _client;

  VdocPubExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': '$baseUrl/',
    };
    final cookie = WebViewSessionManager.instance.getCookieHeader(baseUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return search('fantasy', page: page);
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
    final targetUrl = page <= 1
        ? '$baseUrl/search/$encoded'
        : '$baseUrl/search/$encoded?page=$page';

    String? htmlBody;
    try {
      final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
      if (response.statusCode == 200) {
        htmlBody = response.body;
      }
    } catch (_) {}

    // Headless WebView fallback if Cloudflare challenge is encountered
    if (htmlBody == null || htmlBody.contains('Just a moment...') || htmlBody.contains('challenge-running')) {
      htmlBody = await WebViewSessionManager.instance.fetchHtmlViaWebView(targetUrl);
    }

    if (htmlBody == null || htmlBody.isEmpty) return [];

    return parseHtml(htmlBody);
  }

  /// Parses vdoc.pub search results HTML
  List<Novel> parseHtml(String html) {
    final doc = html_parser.parse(html);
    final items = doc.querySelectorAll('.document-item, .card, .row .col-md-6, article');
    final List<Novel> results = [];

    for (final item in items) {
      final titleAnchor = item.querySelector('a[href*="/documents/"]') ?? item.querySelector('h2 a, h3 a, h4 a, a');
      if (titleAnchor == null) continue;

      final href = titleAnchor.attributes['href'] ?? '';
      if (href.isEmpty || !href.contains('/documents/')) continue;

      final fullUrl = href.startsWith('http') ? href : '$baseUrl$href';
      if (results.any((n) => n.sourceUrl == fullUrl)) continue;

      final rawTitle = titleAnchor.text.trim();
      if (rawTitle.isEmpty) continue;
      final title = TextCleaner.cleanNovelTitle(rawTitle);

      final authorEl = item.querySelector('.author, .text-muted, p');
      String author = 'Unknown Author';
      if (authorEl != null) {
        final text = authorEl.text.trim();
        final byMatch = RegExp(r'\bby\s+(.*?)$', caseSensitive: false).firstMatch(text);
        if (byMatch != null) {
          author = byMatch.group(1)!.trim();
        } else if (text.isNotEmpty && !text.contains('pages') && !text.contains('MB')) {
          author = text;
        }
      }

      final img = item.querySelector('img');
      String coverUrl = '';
      if (img != null) {
        var src = img.attributes['data-src'] ??
            img.attributes['data-original'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'] ??
            '';
        if (src.contains('data:image') || src.contains('placeholder')) {
          src = img.attributes['data-src'] ?? img.attributes['data-original'] ?? '';
        }
        if (src.isNotEmpty && !src.contains('data:image')) {
          coverUrl = src.startsWith('http') ? src : '$baseUrl$src';
        }
      }

      // vdoc.pub document identifier from URL path
      final segments = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      final docId = segments.isNotEmpty ? segments.last : '${fullUrl.hashCode.abs()}';

      // vdoc direct download link format
      final downloadUrl = '$baseUrl/download/$docId';

      results.add(Novel(
        id: '${id}_$docId',
        sourceId: id,
        title: title,
        author: author,
        coverUrl: coverUrl,
        sourceUrl: fullUrl,
        status: 'COMPLETED',
        isFullBook: true,
        bookFormat: 'epub',
        bookDownloadUrl: downloadUrl,
      ));
    }

    return results;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    String? htmlBody;
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200) {
        htmlBody = response.body;
      }
    } catch (_) {}

    if (htmlBody == null || htmlBody.contains('Just a moment...')) {
      htmlBody = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
    }

    if (htmlBody == null) {
      throw Exception('Failed to load vdoc.pub details from $novelUrl');
    }

    final doc = html_parser.parse(htmlBody);
    final rawTitle = doc.querySelector('h1, .document-title')?.text.trim() ?? 'Unknown Book';
    final title = TextCleaner.cleanNovelTitle(rawTitle);

    final author = doc.querySelector('.author, [itemprop="author"]')?.text.trim() ?? 'Unknown Author';
    final description = doc.querySelector('.description, .synopsis, #description, .card-body p')?.text.trim() ?? '';

    final ogImg = doc.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
    var coverUrl = ogImg?.attributes['content'] ?? '';

    if (coverUrl.isEmpty) {
      final img = doc.querySelector('.cover-image img, .document-cover img, img.img-fluid, .cover img, img');
      if (img != null) {
        var src = img.attributes['data-src'] ??
            img.attributes['data-original'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'] ??
            '';
        if (src.contains('data:image') || src.contains('placeholder')) {
          src = img.attributes['data-src'] ?? img.attributes['data-original'] ?? '';
        }
        if (src.isNotEmpty && !src.contains('data:image')) {
          coverUrl = src.startsWith('http') ? src : '$baseUrl$src';
        }
      }
    }

    // Download URL extraction
    final dlAnchor = doc.querySelector('a[href*="/download/"]');
    String? downloadUrl = dlAnchor?.attributes['href'];
    if (downloadUrl != null && !downloadUrl.startsWith('http')) {
      downloadUrl = '$baseUrl$downloadUrl';
    }

    final segments = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final docId = segments.isNotEmpty ? segments.last : '${novelUrl.hashCode.abs()}';

    return Novel(
      id: '${id}_$docId',
      sourceId: id,
      title: title,
      author: author,
      description: description,
      coverUrl: coverUrl,
      sourceUrl: novelUrl,
      status: 'COMPLETED',
      isFullBook: true,
      bookFormat: 'epub',
      bookDownloadUrl: downloadUrl ?? '$baseUrl/download/$docId',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    // Complete books do not have individual chapter URLs before download.
    // Whole package is downloaded once via downloadEntireBook() and unpacked locally.
    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    throw UnsupportedError(
      'vdoc.pub books are packaged as complete digital editions. '
      'Use downloadEntireBook() to read offline with chapter navigation.',
    );
  }
}
