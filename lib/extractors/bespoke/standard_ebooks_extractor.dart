import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../../core/services/epub_service.dart';
import 'local_epub_extractor.dart';
import '../novel_source.dart';

/// Bespoke extractor for Standard Ebooks (https://standardebooks.org).
/// High-quality, professionally typeset, and beautifully formatted public domain masterpieces.
class StandardEbooksExtractor implements NovelSource {
  @override
  final String id = 'standard_ebooks';

  @override
  final String name = 'Standard Ebooks';

  @override
  final String baseUrl = 'https://standardebooks.org';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://standardebooks.org/favicon.ico';

  @override
  final int estimatedNovelCount = 5000;

  late final http.Client _client;

  StandardEbooksExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return search('Tolstoy', page: page);
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
    final url = '$baseUrl/ebooks?query=$encoded';

    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];
      return parseHtml(response.body);
    } catch (_) {
      return [];
    }
  }

  /// Parses Standard Ebooks search / catalog HTML
  List<Novel> parseHtml(String html) {
    final doc = html_parser.parse(html);
    final List<Novel> results = [];

    final items = doc.querySelectorAll('li[itemscope], li[typeof*="Book"], .list-item, ol.ebooks-list li, ol li, article');
    for (final item in items) {
      final anchors = item.querySelectorAll('a[href*="/ebooks/"]');
      if (anchors.isEmpty) continue;

      // Find anchor that points to the specific book edition
      String? href;
      for (final a in anchors) {
        final h = a.attributes['href'] ?? '';
        final uri = Uri.tryParse(h);
        if (uri != null && uri.pathSegments.length >= 3 && uri.pathSegments[0] == 'ebooks') {
          href = h;
          break;
        }
      }
      href ??= item.attributes['about'] ?? anchors.first.attributes['href'] ?? '';
      if (href.isEmpty || href.endsWith('/ebooks') || href.contains('?')) continue;

      final fullUrl = href.startsWith('http') ? href : '$baseUrl$href';
      if (results.any((n) => n.sourceUrl == fullUrl)) continue;

      final nameSpan = item.querySelector('span[property="schema:name"]');
      final rawTitle = nameSpan?.text.trim().isNotEmpty == true
          ? nameSpan!.text.trim()
          : anchors.map((a) => a.text.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => Uri.parse(fullUrl).pathSegments.last);
      if (rawTitle.isEmpty || rawTitle.toLowerCase() == 'ebooks') continue;
      final title = TextCleaner.cleanNovelTitle(rawTitle);

      final authorEl = item.querySelector('[property="schema:author"] span, [itemprop="author"], .author');
      final author = authorEl?.text.trim().isNotEmpty == true ? authorEl!.text.trim() : 'Unknown Author';

      final img = item.querySelector('img');
      String coverUrl = '';
      if (img != null) {
        final src = img.attributes['src'] ?? '';
        if (src.isNotEmpty) {
          coverUrl = src.startsWith('http') ? src : '$baseUrl$src';
        }
      }

      String? downloadUrl;
      final segments = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 3 && segments[0] == 'ebooks') {
        final authorSlug = segments[1];
        final titleSlug = segments[2];
        downloadUrl = '$baseUrl/ebooks/$authorSlug/$titleSlug/downloads/${authorSlug}_$titleSlug.epub';
      }

      results.add(Novel(
        id: '${id}_${fullUrl.hashCode.abs()}',
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
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getNovelDetails(novelUrl);
    }
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load Standard Ebooks details from $novelUrl');
    }

    final doc = html_parser.parse(response.body);
    final titleEl = doc.querySelector('h1, [itemprop="name"]');
    final title = titleEl?.text.trim() ?? 'Novel';

    final authorEl = doc.querySelector('[itemprop="author"] a, [itemprop="author"]');
    final author = authorEl?.text.trim() ?? 'Unknown Author';

    final descEl = doc.querySelector('#description, .description, [itemprop="description"]');
    final description = descEl?.text.trim() ?? '';

    // Find EPUB download button: standard .epub (not kepub or advanced)
    String? downloadUrl;
    final downloadAnchors = doc.querySelectorAll('a[href*=".epub"]');
    for (final a in downloadAnchors) {
      final href = a.attributes['href'] ?? '';
      if (href.endsWith('.epub') && !href.contains('kepub') && !href.contains('advanced')) {
        downloadUrl = href.startsWith('http') ? href : '$baseUrl$href';
        break;
      }
    }

    downloadUrl ??= downloadAnchors.firstOrNull?.attributes['href'];
    if (downloadUrl != null && !downloadUrl.startsWith('http')) {
      downloadUrl = '$baseUrl$downloadUrl';
    }

    final imgEl = doc.querySelector('img[itemprop="image"], .hero-image img, header img');
    String coverUrl = '';
    if (imgEl != null) {
      final src = imgEl.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        coverUrl = src.startsWith('http') ? src : '$baseUrl$src';
      }
    }

    return Novel(
      id: novelUrl,
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
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getChapterList(novelUrl, onBatchLoaded: onBatchLoaded);
    }
    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    return EpubService().loadChapterContent(chapterUrl);
  }
}
