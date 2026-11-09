import 'dart:async';
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
    return search('dune', page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return search('fantasy', page: page);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQuery);

    for (final mirror in mirrors) {
      final url = '$mirror/index.php?req=$encoded&columns%5B%5D=t&objects%5B%5D=f&topics%5B%5D=l&topics%5B%5D=f&res=50';
      try {
        final response = await _client
            .get(Uri.parse(url), headers: _getHeaders(mirror))
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200 && response.body.contains('table')) {
          _activeMirror = mirror;
          final results = parseHtmlTable(response.body, mirror);
          if (results.isNotEmpty) {
            return results;
          }
        }
      } catch (_) {
        // Continue on connection error
      }
    }

    return [];
  }

  /// Parses LibGen search results HTML table into Novel instances
  List<Novel> parseHtmlTable(String html, [String? base]) {
    final currentBase = base ?? _activeMirror;
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll('table#tablelibgen tr, table.table-striped tr, table.c tr, tbody tr, tr');
    final List<Novel> epubResults = [];
    final List<Novel> otherResults = [];

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

      // Extract edition ID if present (e.g. edition.php?id=137287439)
      final rowHtml = row.innerHtml;
      final editionMatch = RegExp(r'edition\.php\?id=(\d+)').firstMatch(rowHtml);
      final editionId = editionMatch?.group(1);

      // Extract library database ID badge (e.g. <span class="badge badge-secondary">l 1510172</span>)
      final libMatch = RegExp(r'>\s*l\s*(\d+)\s*<').firstMatch(rowHtml) ??
          RegExp(r'l\s*(\d+)').firstMatch(rowHtml);
      final libId = libMatch?.group(1);

      // Extract ISBN if available in row (e.g. 0786430575; 9780786430574)
      final isbnMatch = RegExp(r'(?:97[89][-\s]*)?[0-9]{9}[0-9xX]', caseSensitive: false).firstMatch(rowHtml);
      final isbn = isbnMatch?.group(0)?.replaceAll(RegExp(r'[-\s]'), '');

      // Check for inline img tag
      final imgTag = row.querySelector('img[src*="cover"], img[src*="edition"]');
      var coverUrl = '';
      if (imgTag != null) {
        final src = imgTag.attributes['src'] ?? '';
        if (src.isNotEmpty) {
          coverUrl = src.startsWith('http') ? src : '$currentBase$src';
        }
      }

      // Compute standard LibGen library cover path or edition cover
      if (coverUrl.isEmpty && libId != null && int.tryParse(libId) != null) {
        final lNum = int.parse(libId);
        final bucket = (lNum ~/ 1000) * 1000;
        coverUrl = '$currentBase/covers/$bucket/$md5Hash.jpg';
      } else if (coverUrl.isEmpty && editionId != null && int.tryParse(editionId) != null) {
        final edNum = int.parse(editionId);
        final bucket = (edNum ~/ 1000) * 1000;
        coverUrl = '$currentBase/editioncovers/$bucket/$editionId.jpg';
      } else if (coverUrl.isEmpty && isbn != null && isbn.length >= 10) {
        coverUrl = 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false';
      }

      // Real book page with direct download key and cover
      final bookPageUrl = '$currentBase/ads.php?md5=$md5Hash';
      final downloadUrl = '$currentBase/get.php?md5=$md5Hash';

      final item = Novel(
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
      );

      if (epubResults.any((n) => n.id == item.id) || otherResults.any((n) => n.id == item.id)) continue;

      if (format.toLowerCase() == 'epub') {
        epubResults.add(item);
      } else {
        otherResults.add(item);
      }
    }
    return epubResults.isNotEmpty ? epubResults : otherResults;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getNovelDetails(novelUrl);
    }
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
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200 && (res.body.contains('table') || res.body.contains('get.php') || res.body.contains('ads.php'))) {
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
    } else {
      // If landed on edition.php or file.php, resolve underlying ads.php page to extract keyed get.php link
      final md5Match = RegExp(r'md5=([a-fA-F0-9]{32})', caseSensitive: false).firstMatch(novelUrl) ??
          RegExp(r'md5=([a-fA-F0-9]{32})', caseSensitive: false).firstMatch(response.body);
      if (md5Match != null) {
        final md5 = md5Match.group(1)!;
        final adsUrl = '$_activeMirror/ads.php?md5=$md5';
        try {
          final adsRes = await _client
              .get(Uri.parse(adsUrl), headers: _getHeaders(_activeMirror))
              .timeout(const Duration(seconds: 8));
          if (adsRes.statusCode == 200) {
            final adsDoc = html_parser.parse(adsRes.body);
            final dlInAds = adsDoc.querySelector('a[href*="get.php?md5="]');
            if (dlInAds != null) {
              final relHref = dlInAds.attributes['href'] ?? '';
              downloadUrl = relHref.startsWith('http') ? relHref : '$_activeMirror/$relHref';
            }
          }
        } catch (_) {}
      }
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

    // Fallback: extract editioncover or lib cover path or ISBN from page HTML
    if (coverUrl.isEmpty) {
      final edMatch = RegExp(r'/editioncovers/(\d+)/(\d+)\.jpg').firstMatch(response.body);
      if (edMatch != null) {
        coverUrl = '$_activeMirror/editioncovers/${edMatch.group(1)}/${edMatch.group(2)}.jpg';
      } else {
        final covMatch = RegExp(r'/covers/(\d+)/([a-zA-Z0-9]+)\.jpg').firstMatch(response.body);
        if (covMatch != null) {
          coverUrl = '$_activeMirror/covers/${covMatch.group(1)}/${covMatch.group(2)}.jpg';
        } else {
          final isbnMatch = RegExp(r'isbn\s*=\s*\{([^}]+)\}', caseSensitive: false).firstMatch(response.body);
          final isbn = isbnMatch?.group(1)?.replaceAll(RegExp(r'[-\s]'), '');
          if (isbn != null && isbn.length >= 10) {
            coverUrl = 'https://covers.openlibrary.org/b/isbn/$isbn-M.jpg?default=false';
          }
        }
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

    String detectedFormat = 'epub';
    final formatMatch = RegExp(r'\b(epub|pdf|mobi|azw3)\b', caseSensitive: false).firstMatch(response.body);
    if (formatMatch != null) {
      detectedFormat = formatMatch.group(1)!.toLowerCase();
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
      bookFormat: detectedFormat,
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
