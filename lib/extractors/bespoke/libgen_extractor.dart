import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke extractor for Library Genesis (https://libgen.li).
/// World's largest open book and academic repository containing complete digital editions
/// of Harry Potter, Dune, Game of Thrones, The Hobbit, and millions of published novels.
/// Features multi-mirror failover across libgen.li, libgen.la, and libgen.bz to prevent HTTP 522 Cloudflare timeouts.
class LibGenExtractor implements NovelSource {
  @override
  final String id = 'libgen';

  @override
  final String name = 'Library Genesis';

  @override
  String get baseUrl => _activeMirror;

  static const List<String> mirrors = [
    'https://libgen.li',
    'https://libgen.la',
    'https://libgen.bz',
  ];

  String _activeMirror = mirrors.first;

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://libgen.li/img/logo.png';

  @override
  final int estimatedNovelCount = 2000000;

  late final http.Client _client;

  LibGenExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> _getHeaders(String base) => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$base/',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    return search('fantasy fiction', page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return search('sci-fi', page: page);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQuery);

    // Multi-mirror failover: if libgen.li returns HTTP 522/timeout, rotate to libgen.la or libgen.bz
    for (final mirror in mirrors) {
      final url = '$mirror/index.php?req=$encoded&columns%5B%5D=t&objects%5B%5D=f&topics%5B%5D=l&res=25';
      try {
        final response = await _client
            .get(Uri.parse(url), headers: _getHeaders(mirror))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 && response.body.contains('table')) {
          _activeMirror = mirror;
          final results = parseHtmlTable(response.body, mirror);
          if (results.isNotEmpty) {
            return results;
          }
        }
      } catch (_) {
        // Continue to next mirror on timeout or connection error (HTTP 522)
      }
    }

    return [];
  }

  /// Parses LibGen search results HTML table into Novel instances
  List<Novel> parseHtmlTable(String html, [String? base]) {
    final currentBase = base ?? _activeMirror;
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll('table#tablelibgen tr, table.table-striped tr, table.c tr, tbody tr, tr');
    final List<Novel> results = [];

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 5) continue;

      final titleAnchor = row.querySelector('a[href*="edition.php"]') ??
          row.querySelector('a[href*="book/index.php"]') ??
          row.querySelector('a[href*="ads.php"]') ??
          row.querySelector('a[id*="title"]') ??
          cells[0].querySelector('a');
      final rawTitle = titleAnchor?.text.trim() ?? '';
      if (rawTitle.isEmpty || rawTitle.toLowerCase() == 'title') continue;
      final title = TextCleaner.cleanNovelTitle(rawTitle);

      var author = 'Unknown Author';
      if (cells.length > 1) {
        final authorText = cells[1].text.trim();
        if (authorText.isNotEmpty && authorText.toLowerCase() != 'author') {
          author = authorText;
        }
      }

      var format = 'epub';
      for (final c in cells) {
        final txt = c.text.trim().toLowerCase();
        if (txt == 'epub' || txt == 'pdf' || txt == 'mobi' || txt == 'azw3') {
          format = txt;
          break;
        }
      }

      final md5Anchor = row.querySelector('a[href*="ads.php?md5="]') ??
          row.querySelector('a[href*="md5="]') ??
          row.querySelector('a[href*="/get.php"]');
      final href = md5Anchor?.attributes['href'] ?? '';
      final md5Match = RegExp(r'md5=([a-zA-Z0-9]+)').firstMatch(href);
      final md5Hash = md5Match?.group(1);
      if (md5Hash == null || md5Hash.isEmpty) continue;

      // Real book page with direct download key and cover
      final bookPageUrl = '$currentBase/ads.php?md5=$md5Hash';
      final downloadUrl = '$currentBase/get.php?md5=$md5Hash';

      // LibGen standardized cover image path
      final coverPrefix = md5Hash.length >= 3 ? md5Hash.substring(0, 3) : '000';
      final coverUrl = '$currentBase/covers/${coverPrefix}000/$md5Hash.jpg';

      if (results.any((n) => n.id == '${id}_$md5Hash')) continue;

      results.add(Novel(
        id: '${id}_$md5Hash',
        sourceId: id,
        title: title,
        author: author,
        description: 'Format: ${format.toUpperCase()}',
        coverUrl: coverUrl,
        sourceUrl: bookPageUrl,
        status: 'COMPLETED',
        isFullBook: true,
        bookDownloadUrl: downloadUrl,
        bookFormat: format,
      ));
    }
    return results;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final uri = Uri.parse(novelUrl);
    final currentBase = '${uri.scheme}://${uri.host}';

    http.Response? response;
    // Try current base first, then fallback to mirrors
    final tryBases = [currentBase, ...mirrors.where((m) => m != currentBase)];

    for (final base in tryBases) {
      final targetUrl = novelUrl.startsWith('http')
          ? novelUrl.replaceFirst(RegExp(r'^https?://[^/]+'), base)
          : '$base/$novelUrl';

      try {
        final res = await _client
            .get(Uri.parse(targetUrl), headers: _getHeaders(base))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          response = res;
          _activeMirror = base;
          break;
        }
      } catch (_) {}
    }

    if (response == null || response.statusCode != 200) {
      throw Exception('Failed to load LibGen novel details from $novelUrl');
    }

    final doc = html_parser.parse(response.body);

    // Look for direct get.php download button with active session key
    final downloadAnchor = doc.querySelector('a[href*="get.php?md5="]');
    var downloadUrl = novelUrl;
    if (downloadAnchor != null) {
      final relHref = downloadAnchor.attributes['href'] ?? '';
      downloadUrl = relHref.startsWith('http') ? relHref : '$_activeMirror/$relHref';
    }

    // Cover image extraction
    final coverImg = doc.querySelector('img[src*="covers/"], img[src*="cover"], img[src*="/editioncovers/"], img[src*="/comicscovers/"]');
    var coverUrl = '';
    if (coverImg != null) {
      final src = coverImg.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        coverUrl = src.startsWith('http') ? src : '$_activeMirror$src';
      }
    }

    // Extract Title and Author from BibTeX or Table text
    final bibtext = doc.querySelector('textarea#bibtext, textarea[name="bibtext"]')?.text ?? '';
    String? rawTitle;
    String? rawAuthor;

    if (bibtext.isNotEmpty) {
      final titleMatch = RegExp(r'title\s*=\s*\{([^}]+)\}', caseSensitive: false).firstMatch(bibtext);
      if (titleMatch != null) rawTitle = titleMatch.group(1)?.trim();

      final authorMatch = RegExp(r'author\s*=\s*\{([^}]+)\}', caseSensitive: false).firstMatch(bibtext);
      if (authorMatch != null) rawAuthor = authorMatch.group(1)?.trim();
    }

    // Fallback: parse from table rows or strong labels
    if (rawTitle == null || rawTitle.isEmpty) {
      final bodyText = response.body;
      final titleRowMatch = RegExp(r'Title:\s*([^<\n\r]+)', caseSensitive: false).firstMatch(bodyText);
      if (titleRowMatch != null) {
        rawTitle = titleRowMatch.group(1)?.trim();
      }
    }

    if (rawAuthor == null || rawAuthor.isEmpty) {
      final bodyText = response.body;
      final authorRowMatch = RegExp(r'Author\(s\):\s*([^<\n\r]+)', caseSensitive: false).firstMatch(bodyText);
      if (authorRowMatch != null) {
        rawAuthor = authorRowMatch.group(1)?.trim();
      }
    }

    // If still not found, try heading elements but ignore default site title "Library Genesis"
    if (rawTitle == null || rawTitle.isEmpty) {
      final h = doc.querySelector('h1, h2, .title')?.text.trim();
      if (h != null && h.isNotEmpty && h.toLowerCase() != 'library genesis' && h.toLowerCase() != 'get') {
        rawTitle = h;
      }
    }

    final title = TextCleaner.cleanNovelTitle(
      (rawTitle != null && rawTitle.isNotEmpty && rawTitle.toLowerCase() != 'library genesis')
          ? rawTitle
          : 'Book',
    );
    final author = (rawAuthor != null && rawAuthor.isNotEmpty) ? rawAuthor : 'Unknown Author';

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
    throw UnsupportedError('LibGen chapters are unpacked locally via whole-book EPUB download.');
  }
}
