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

/// Bespoke extractor for OceanofPDF (https://oceanofpdf.com)
/// Premier digital novel and book library offering full novels and literature.
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
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
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

  String _cleanUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    } else if (url.startsWith('/')) {
      return '$baseUrl$url';
    }
    return url;
  }

  /// Sanitizes raw OceanofPDF title formatting:
  /// "[PDF] [EPUB] The Way of Kings by Brandon Sanderson Download" -> ("The Way of Kings", "Brandon Sanderson")
  (String title, String author) _parseTitleAndAuthor(String rawTitle) {
    String clean = rawTitle
        .replaceAll(RegExp(r'\[PDF\]|\[EPUB\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bDownload\b', caseSensitive: false), '')
        .trim();

    // Check for "by [Author]" pattern
    final byMatch = RegExp(r'^(.*?)\s+by\s+(.*?)$', caseSensitive: false).firstMatch(clean);
    if (byMatch != null) {
      final title = byMatch.group(1)?.trim() ?? clean;
      final author = byMatch.group(2)?.trim() ?? 'Unknown Author';
      return (title.isNotEmpty ? title : clean, author);
    }

    return (clean.isNotEmpty ? clean : 'Unknown Novel', 'Unknown Author');
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final encodedQuery = Uri.encodeComponent(query);
    final targetUrl = page <= 1
        ? '$baseUrl/?s=$encodedQuery'
        : '$baseUrl/page/$page/?s=$encodedQuery';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      return [];
    }

    return _parseNovelList(response.body);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = page <= 1
        ? '$baseUrl/category/fiction/'
        : '$baseUrl/category/fiction/page/$page/';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      // Fallback to homepage
      final homeResponse = await _client.get(Uri.parse(baseUrl), headers: _headers);
      if (homeResponse.statusCode == 200) {
        return _parseNovelList(homeResponse.body);
      }
      return [];
    }

    return _parseNovelList(response.body);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final targetUrl = page <= 1
        ? '$baseUrl/'
        : '$baseUrl/page/$page/';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      return [];
    }

    return _parseNovelList(response.body);
  }

  List<Novel> _parseNovelList(String html) {
    final document = html_parser.parse(html);
    final List<Novel> novels = [];

    // Articles represent posts/books on OceanofPDF
    final articles = document.querySelectorAll('article.post, article, .post');
    for (final article in articles) {
      final titleElem = article.querySelector('.entry-title a, h2 a, h3 a');
      if (titleElem == null) continue;

      final rawTitle = titleElem.text.trim();
      final novelUrl = _cleanUrl(titleElem.attributes['href'] ?? '');
      if (novelUrl.isEmpty) continue;

      final (title, parsedAuthor) = _parseTitleAndAuthor(rawTitle);

      // Extract cover image
      final imgElem = article.querySelector('img');
      String coverUrl = '';
      if (imgElem != null) {
        coverUrl = imgElem.attributes['data-lazy-src'] ??
            imgElem.attributes['data-src'] ??
            imgElem.attributes['src'] ??
            '';
        coverUrl = _cleanUrl(coverUrl);
      }

      // Extract category/genres if available
      final genreElems = article.querySelectorAll('.entry-categories a, .cat-links a, .post-category a');
      final genres = genreElems.map((e) => e.text.trim()).where((g) => g.isNotEmpty).toList();

      novels.add(Novel(
        id: novelUrl,
        sourceId: id,
        title: title,
        author: parsedAuthor,
        coverUrl: coverUrl,
        sourceUrl: novelUrl,
        genres: genres,
        status: 'COMPLETED',
      ));
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load OceanofPDF details from $novelUrl (status ${response.statusCode})');
    }

    final document = html_parser.parse(response.body);

    // Title & Author
    final titleElem = document.querySelector('.entry-title, h1.title, h1');
    final rawTitle = titleElem?.text.trim() ?? 'Unknown Novel';
    final (title, parsedAuthor) = _parseTitleAndAuthor(rawTitle);

    // Try finding specific author line in entry-content: e.g. "Author: Brandon Sanderson" or strong tags
    String author = parsedAuthor;
    for (final p in document.querySelectorAll('.entry-content p, .entry-content strong')) {
      final text = p.text.trim();
      if (text.toLowerCase().startsWith('author:') || text.toLowerCase().startsWith('by:')) {
        author = text.replaceFirst(RegExp(r'^(author|by):\s*', caseSensitive: false), '').trim();
        break;
      }
    }

    // Cover Image
    String coverUrl = '';
    final imgElem = document.querySelector('.entry-content img, article img, .post-image img');
    if (imgElem != null) {
      coverUrl = imgElem.attributes['data-lazy-src'] ??
          imgElem.attributes['data-src'] ??
          imgElem.attributes['src'] ??
          '';
      coverUrl = _cleanUrl(coverUrl);
    }

    // Synopsis / Description paragraphs
    final contentParagraphs = document.querySelectorAll('.entry-content p');
    final List<String> descLines = [];
    for (final p in contentParagraphs) {
      final t = p.text.trim();
      if (t.isEmpty) continue;
      // Skip download buttons and metadata lines
      if (t.toLowerCase().contains('download') ||
          t.toLowerCase().contains('click below') ||
          t.toLowerCase().contains('status:') ||
          t.toLowerCase().contains('isbn:')) {
        continue;
      }
      descLines.add(t);
    }

    final description = descLines.join('\n\n');

    // Genres
    final genreElems = document.querySelectorAll('.entry-categories a, .cat-links a, .tagcloud a, a[rel="category tag"]');
    final genres = genreElems.map((e) => e.text.trim()).where((g) => g.isNotEmpty).toSet().toList();

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      author: author,
      description: description,
      coverUrl: coverUrl,
      genres: genres,
      status: 'COMPLETED',
      sourceUrl: novelUrl,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      return [];
    }

    final document = html_parser.parse(response.body);
    final titleElem = document.querySelector('.entry-title, h1.title, h1');
    final (title, _) = _parseTitleAndAuthor(titleElem?.text.trim() ?? 'Novel');

    final List<Chapter> chapters = [];

    // Check if the article contains sub-chapter links or sections
    final chapterLinks = document.querySelectorAll('.entry-content a[href*="/chapter-"], .entry-content a[href*="/part-"]');
    if (chapterLinks.isNotEmpty) {
      int index = 1;
      for (final link in chapterLinks) {
        final chapterUrl = _cleanUrl(link.attributes['href'] ?? '');
        final chapterTitle = link.text.trim();
        if (chapterUrl.isNotEmpty && chapterTitle.isNotEmpty) {
          chapters.add(Chapter(
            id: chapterUrl,
            novelId: novelUrl,
            title: chapterTitle,
            chapterNumber: index.toDouble(),
            url: chapterUrl,
          ));
          index++;
        }
      }
    }

    // Default to Full Book / Complete Reading Edition if discrete chapter links are not partitioned
    if (chapters.isEmpty) {
      chapters.add(Chapter(
        id: novelUrl,
        novelId: novelUrl,
        title: '$title - Complete Reading Edition',
        chapterNumber: 1.0,
        url: novelUrl,
      ));
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load OceanofPDF content from $chapterUrl (status ${response.statusCode})');
    }

    final document = html_parser.parse(response.body);
    final titleElem = document.querySelector('.entry-title, h1.title, h1');
    final (title, _) = _parseTitleAndAuthor(titleElem?.text.trim() ?? 'Chapter Content');

    final contentElem = document.querySelector('.entry-content, article, .post-content');
    final List<String> rawParagraphs = [];

    if (contentElem != null) {
      for (final p in contentElem.querySelectorAll('p')) {
        final text = p.text.trim();
        if (text.isEmpty) continue;
        // Strip download buttons, copyright footers, and request notes
        if (text.toLowerCase().contains('download') ||
            text.toLowerCase().contains('click below') ||
            text.toLowerCase().contains('file size:') ||
            text.toLowerCase().contains('contact us') ||
            text.toLowerCase().contains('dmca')) {
          continue;
        }
        rawParagraphs.add(text);
      }
    }

    final paragraphs = TextCleaner.cleanParagraphs(rawParagraphs);
    final rawText = paragraphs.join('\n\n');

    return ChapterContent(
      chapterId: chapterUrl,
      novelId: chapterUrl,
      title: title,
      rawText: rawText,
      paragraphs: paragraphs,
    );
  }
}
