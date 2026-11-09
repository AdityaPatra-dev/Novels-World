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
class LibGenExtractor implements NovelSource {
  @override
  final String id = 'libgen';

  @override
  final String name = 'Library Genesis';

  @override
  final String baseUrl = 'https://libgen.li';

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

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$baseUrl/',
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
    final url = '$baseUrl/index.php?req=$encoded&columns%5B%5D=t&objects%5B%5D=f&topics%5B%5D=l&res=25';

    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];
      return parseHtmlTable(response.body);
    } catch (_) {
      return [];
    }
  }

  /// Parses LibGen search results HTML table into Novel instances
  List<Novel> parseHtmlTable(String html) {
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll('table.c tr, tbody tr, tr');
    final List<Novel> results = [];

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 9) continue;

      final titleAnchor = row.querySelector('a[href*="edition.php"]') ??
          row.querySelector('a[href*="book/index.php"]') ??
          row.querySelector('a[id*="title"]') ??
          cells[0].querySelector('a');
      final rawTitle = titleAnchor?.text.trim() ?? '';
      if (rawTitle.isEmpty) continue;
      final title = TextCleaner.cleanNovelTitle(rawTitle);

      final author = cells[1].text.trim().isNotEmpty ? cells[1].text.trim() : 'Unknown Author';

      var format = 'epub';
      for (final c in cells) {
        final txt = c.text.trim().toLowerCase();
        if (txt == 'epub' || txt == 'pdf' || txt == 'mobi' || txt == 'azw3') {
          format = txt;
          break;
        }
      }

      final md5Anchor = row.querySelector('a[href*="md5="]') ?? row.querySelector('a[href*="/get.php"]');
      final href = md5Anchor?.attributes['href'] ?? '';
      final md5Match = RegExp(r'md5=([a-zA-Z0-9]+)').firstMatch(href);
      final md5Hash = md5Match?.group(1);
      if (md5Hash == null || md5Hash.isEmpty) continue;

      final bookUrl = '$baseUrl/get.php?md5=$md5Hash';

      results.add(Novel(
        id: '${id}_$md5Hash',
        sourceId: id,
        title: title,
        author: author,
        description: 'Format: ${format.toUpperCase()}',
        coverUrl: '',
        sourceUrl: bookUrl,
        status: 'COMPLETED',
        isFullBook: true,
        bookDownloadUrl: bookUrl,
        bookFormat: format,
      ));
    }
    return results;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load LibGen novel details from $novelUrl');
    }

    final doc = html_parser.parse(response.body);

    // Look for direct get.php download button with key
    final downloadAnchor = doc.querySelector('a[href*="get.php?md5="]');
    var downloadUrl = novelUrl;
    if (downloadAnchor != null) {
      final relHref = downloadAnchor.attributes['href'] ?? '';
      downloadUrl = relHref.startsWith('http') ? relHref : '$baseUrl/$relHref';
    }

    final title = doc.querySelector('h1, .title, title')?.text.trim() ?? 'Novel';

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: TextCleaner.cleanNovelTitle(title),
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
