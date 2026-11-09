import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for OceanofPDF (https://oceanofpdf.com).
/// Premier digital fiction repository with complete editions of modern bestsellers,
/// fantasy sagas, science fiction, and young adult literature.
class OceanofPdfExtractor implements NovelSource {
  @override
  final String id = 'oceanofpdf';

  @override
  final String name = 'OceanofPDF';

  @override
  final String baseUrl = 'https://oceanofpdf.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://oceanofpdf.com/favicon.ico';

  @override
  final int estimatedNovelCount = 80000;

  late final http.Client _client;

  OceanofPdfExtractor({http.Client? client}) {
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

  (String title, String author) _parseTitleAndAuthor(String rawTitle) {
    String clean = rawTitle
        .replaceAll(RegExp(r'\[PDF\]|\[EPUB\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bDownload\b', caseSensitive: false), '')
        .trim();

    final byMatch = RegExp(r'^(.*?)\s+by\s+(.*?)$', caseSensitive: false).firstMatch(clean);
    if (byMatch != null) {
      final title = byMatch.group(1)?.trim() ?? clean;
      final author = byMatch.group(2)?.trim() ?? 'Unknown Author';
      return (title.isNotEmpty ? title : clean, author);
    }

    return (clean.isNotEmpty ? clean : 'Unknown Novel', 'Unknown Author');
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return search('Fantasy', page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return search('Fiction', page: page);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQuery);
    final targetUrl = page <= 1
        ? '$baseUrl/?s=$encoded'
        : '$baseUrl/page/$page/?s=$encoded';

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

    return _parseNovelList(htmlBody);
  }

  /// Parses OceanofPDF HTML list of books
  List<Novel> parseHtml(String html) => _parseNovelList(html);

  List<Novel> _parseNovelList(String html) {
    final document = html_parser.parse(html);
    final articles = document.querySelectorAll('article.post, .post, article');
    final List<Novel> novels = [];

    for (final article in articles) {
      final titleElem = article.querySelector('.entry-title a, h2 a, h3 a');
      if (titleElem == null) continue;

      final novelUrl = titleElem.attributes['href'] ?? '';
      if (novelUrl.isEmpty) continue;

      var (title, parsedAuthor) = _parseTitleAndAuthor(titleElem.text.trim());

      // Fallback: extract author from OceanofPDF author URL slug
      if (parsedAuthor == 'Unknown Author') {
        final authorUrlMatch = RegExp(r'/authors/([^/]+)/').firstMatch(novelUrl);
        if (authorUrlMatch != null) {
          final authorSlug = authorUrlMatch.group(1)!;
          parsedAuthor = authorSlug
              .split('-')
              .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
              .join(' ')
              .trim();
        }
      }

      String coverUrl = '';
      final imgElem = article.querySelector('img');
      if (imgElem != null) {
        coverUrl = imgElem.attributes['data-lazy-src'] ??
            imgElem.attributes['data-src'] ??
            imgElem.attributes['src'] ??
            '';
      }

      novels.add(Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: parsedAuthor,
        coverUrl: coverUrl,
        sourceUrl: novelUrl,
        status: 'COMPLETED',
        isFullBook: true,
        bookFormat: 'epub',
      ));
    }

    return novels;
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
      throw Exception('Failed to load OceanofPDF details from $novelUrl');
    }

    final doc = html_parser.parse(htmlBody);

    final titleElem = doc.querySelector('.entry-title, h1.title, h1');
    final rawTitle = titleElem?.text.trim() ?? 'Novel';
    final (title, parsedAuthor) = _parseTitleAndAuthor(rawTitle);

    var author = parsedAuthor;
    for (final p in doc.querySelectorAll('.entry-content p, .entry-content strong')) {
      final text = p.text.trim();
      if (text.toLowerCase().startsWith('author:') || text.toLowerCase().startsWith('by:')) {
        author = text.replaceFirst(RegExp(r'^(author|by):\s*', caseSensitive: false), '').trim();
        break;
      }
    }

    final ogImg = doc.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
    var coverUrl = ogImg?.attributes['content'] ?? '';

    if (coverUrl.isEmpty) {
      final imgElem = doc.querySelector('.entry-content img, article img, .post-thumbnail img');
      if (imgElem != null) {
        coverUrl = imgElem.attributes['data-lazy-src'] ??
            imgElem.attributes['data-src'] ??
            imgElem.attributes['src'] ??
            '';
      }
    }

    // Look for EPUB download button / form
    String? downloadUrl;
    final forms = doc.querySelectorAll('form[action*="epub"], form[action*="download"], form');
    for (final f in forms) {
      final action = f.attributes['action'] ?? '';
      if (action.toLowerCase().contains('.epub') || action.toLowerCase().contains('download')) {
        downloadUrl = action.startsWith('http') ? action : '$baseUrl$action';
        break;
      }
    }

    if (downloadUrl == null) {
      final epubAnchor = doc.querySelector('a[href*=".epub"], a[href*="/download/"]');
      if (epubAnchor != null) {
        final href = epubAnchor.attributes['href'] ?? '';
        downloadUrl = href.startsWith('http') ? href : '$baseUrl$href';
      }
    }

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      author: author,
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
    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    throw UnsupportedError('OceanofPDF books are unpacked locally via whole-book EPUB download.');
  }
}
