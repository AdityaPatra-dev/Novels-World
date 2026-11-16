import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for ePustakalay (https://epustakalay.com).
/// India's largest Hindi digital library containing thousands of historical chronicles,
/// classical literature, mythological texts, and timeless novels.
class EPustakalayExtractor implements NovelSource {
  @override
  final String id = 'epustakalay';

  @override
  final String name = 'ePustakalay (ई-पुस्तकालय)';

  @override
  final String baseUrl = 'https://epustakalay.com';

  @override
  final String lang = 'hi';

  @override
  final String iconUrl = 'https://epustakalay.com/favicon.ico';

  @override
  final int estimatedNovelCount = 40000;

  late final http.Client _client;

  EPustakalayExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'hi,en-US,en;q=0.9',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final url = page <= 1
        ? '$baseUrl/most-popular-books/'
        : '$baseUrl/most-popular-books/page/$page/';
    return _fetchBookListing(url);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final url = page <= 1
        ? '$baseUrl/genres/upanyas-novel/'
        : '$baseUrl/genres/upanyas-novel/page/$page/';
    return _fetchBookListing(url);
  }

  static const Map<String, String> _writerSlugs = {
    'प्रेमचंद': 'munshi-premchand',
    'premchand': 'munshi-premchand',
    'गोदान': 'munshi-premchand',
    'गबन': 'munshi-premchand',
    'निर्मला': 'munshi-premchand',
    'प्रसाद': 'jaishankar-prasad',
    'जयशंकर': 'jaishankar-prasad',
    'दिनकर': 'ramdhari-singh-dinkar',
    'उपन्यास': 'genres/upanyas-novel',
    'कहानी': 'genres/kahani-story',
    'इतिहास': 'genres/itihas-history',
    'धार्मिक': 'genres/dharmik-religious',
    'साहित्य': 'genres/sahitya-literature',
  };

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    // 1. Check known writer/category slugs
    for (final entry in _writerSlugs.entries) {
      if (cleanQuery.contains(entry.key.toLowerCase()) || entry.key.toLowerCase().contains(cleanQuery)) {
        final path = entry.value.startsWith('genres/') ? entry.value : 'writers/${entry.value}';
        final writerUrl = page <= 1 ? '$baseUrl/$path/' : '$baseUrl/$path/page/$page/';
        final results = await _fetchBookListing(writerUrl);
        if (results.isNotEmpty) return results;
      }
    }

    // 2. Direct slug check if query is Latin / romanized
    final romanSlug = cleanQuery.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (romanSlug.isNotEmpty && romanSlug.length >= 3) {
      final writerUrl = page <= 1 ? '$baseUrl/writers/$romanSlug/' : '$baseUrl/writers/$romanSlug/page/$page/';
      final results = await _fetchBookListing(writerUrl);
      if (results.isNotEmpty) return results;
    }

    // 3. Fallback: filter popular & latest novels by query match
    final popular = await getPopular(page: page);
    final filtered = popular.where((n) {
      return n.title.toLowerCase().contains(cleanQuery) ||
          n.author.toLowerCase().contains(cleanQuery);
    }).toList();
    if (filtered.isNotEmpty) return filtered;

    // 4. Return popular listing as resilient fallback
    return popular;
  }

  Future<List<Novel>> _fetchBookListing(String url) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final List<Novel> books = [];
      final seenUrls = <String>{};

      final anchors = doc.querySelectorAll('a[href*="/book/"]');
      for (final a in anchors) {
        final href = a.attributes['href'] ?? '';
        final text = a.text.trim();
        if (href.isEmpty || text.isEmpty || text.length < 3) continue;

        final fullUrl = href.startsWith('http') ? href : '$baseUrl$href';
        if (!seenUrls.add(fullUrl)) continue;

        var cleanTitle = text.replaceAll(RegExp(r'^Hindi|^Marathi|^English', caseSensitive: false), '').trim();
        var author = 'Unknown Author';

        if (cleanTitle.contains('-')) {
          final parts = cleanTitle.split('-');
          cleanTitle = parts[0].trim();
        }

        // Extract author from slug if available e.g. /book/123-title-by-author-name/
        final byMatch = RegExp(r'-by-([a-z0-9-]+)/?$', caseSensitive: false).firstMatch(fullUrl);
        if (byMatch != null) {
          author = byMatch.group(1)!
              .split('-')
              .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
              .join(' ');
        }

        // Extract thumbnail cover image, removing size suffixes for high definition
        var coverUrl = '';
        final imgElem = a.querySelector('img') ?? a.parent?.querySelector('img');
        if (imgElem != null) {
          var src = imgElem.attributes['src'] ?? imgElem.attributes['data-src'] ?? '';
          if (src.isNotEmpty) {
            if (!src.startsWith('http')) src = '$baseUrl$src';
            coverUrl = src.replaceAll(RegExp(r'-\d+x\d+(\.[a-zA-Z]+)$'), r'$1');
          }
        }

        books.add(Novel(
          id: '${id}_${fullUrl.hashCode.abs()}',
          sourceId: id,
          title: cleanTitle.isNotEmpty ? cleanTitle : text,
          author: author,
          description: 'Hindi digital book on ePustakalay.',
          coverUrl: coverUrl,
          genres: const ['Hindi', 'History', 'Literature'],
          status: 'COMPLETED',
          sourceUrl: fullUrl,
          isFullBook: true,
          bookFormat: 'pdf',
        ));
      }

      return books;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to load book from $novelUrl');
      }

      final doc = html_parser.parse(response.body);
      final rawHeading = doc.querySelector('h1')?.text.trim() ?? 'Hindi Book';
      final cleanTitle = rawHeading.contains('|') ? rawHeading.split('|')[0].trim() : rawHeading;

      var author = 'Unknown Author';
      final byMatch = RegExp(r'-by-([a-z0-9-]+)/?$', caseSensitive: false).firstMatch(novelUrl);
      if (byMatch != null) {
        author = byMatch.group(1)!
            .split('-')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
            .join(' ');
      }

      // Extract high-resolution book cover
      var coverUrl = '';
      final coverImg = doc.querySelector('img[alt*="Book Image"], .entry-content img, .book-description img, img[src*="wp-content/uploads/"]');
      if (coverImg != null) {
        var src = coverImg.attributes['src'] ?? coverImg.attributes['data-src'] ?? '';
        if (src.isNotEmpty) {
          if (!src.startsWith('http')) src = '$baseUrl$src';
          coverUrl = src.replaceAll(RegExp(r'-\d+x\d+(\.[a-zA-Z]+)$'), r'$1');
        }
      }

      // Look for PDF download URL
      String? pdfUrl;
      final pdfAnchors = doc.querySelectorAll('a[href*=".pdf"], a[href*="archive.org/download/"]');
      for (final a in pdfAnchors) {
        final href = a.attributes['href'] ?? '';
        if (href.isNotEmpty) {
          pdfUrl = href;
          break;
        }
      }

      // Extract synopsis
      final descElem = doc.querySelector('.entry-content, .book-description, #description');
      final desc = descElem?.querySelector('p')?.text.trim() ?? 'Hindi Book from ePustakalay collection.';

      return Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: cleanTitle,
        author: author,
        description: desc,
        coverUrl: coverUrl,
        genres: const ['Hindi', 'History', 'Literature'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
        isFullBook: true,
        bookDownloadUrl: pdfUrl,
        bookFormat: 'pdf',
      );
    } catch (_) {
      return Novel(
        id: '${id}_${novelUrl.hashCode.abs()}',
        sourceId: id,
        title: 'Hindi Book',
        author: 'Unknown Author',
        sourceUrl: novelUrl,
        isFullBook: true,
        bookFormat: 'pdf',
      );
    }
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    // Single full-book volume
    final single = [
      Chapter(
        id: '${id}_${novelUrl.hashCode.abs()}',
        novelId: '${id}_${novelUrl.hashCode.abs()}',
        title: 'सम्पूर्ण पुस्तक (Complete Book PDF)',
        url: novelUrl,
        chapterNumber: 1.0,
      ),
    ];
    onBatchLoaded?.call(single);
    return single;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final novel = await getNovelDetails(chapterUrl);
    final text = '${novel.title}\n\nलेखक: ${novel.author}\n\nविवरण: ${novel.description}\n\nडाउनलोड लिंक: ${novel.bookDownloadUrl ?? "Direct Archive Reader"}';
    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: '${id}_${chapterUrl.hashCode.abs()}',
      title: novel.title,
      rawText: text,
      paragraphs: [
        novel.title,
        'लेखक: ${novel.author}',
        novel.description,
        'यह पुस्तक संपूर्ण पीडीएफ (PDF) प्रारूप में उपलब्ध है।',
      ],
    );
  }
}
