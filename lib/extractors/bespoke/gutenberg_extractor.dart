import 'dart:io';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Extractor for Project Gutenberg (https://www.gutenberg.org).
/// Global benchmark for classic literature, hosting 70,000+ public domain literary masterpieces
/// (Shakespeare, Dostoevsky, Jane Austen, Arthur Conan Doyle, Mary Shelley, Leo Tolstoy, etc.).
class GutenbergExtractor implements NovelSource {
  @override
  final String id = 'gutenberg';

  @override
  final String name = 'Project Gutenberg';

  @override
  final String baseUrl = 'https://www.gutenberg.org';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 70000;

  late final http.Client _client;

  GutenbergExtractor({http.Client? client}) {
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (cert, host, port) => true;
      nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
      _client = IOClient(nativeHttpClient);
    }
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$baseUrl/',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final startIndex = (page - 1) * 25 + 1;
    final url = '$baseUrl/ebooks/search/?sort_order=downloads&start_index=$startIndex';
    return _parseSearchGrid(url);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final startIndex = (page - 1) * 25 + 1;
    final url = '$baseUrl/ebooks/search/?sort_order=release_date&start_index=$startIndex';
    return _parseSearchGrid(url);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final startIndex = (page - 1) * 25 + 1;
    final encoded = Uri.encodeComponent(query.trim());
    final url = '$baseUrl/ebooks/search/?query=$encoded&start_index=$startIndex';
    return _parseSearchGrid(url);
  }

  Future<List<Novel>> _parseSearchGrid(String url) async {
    final response = await _client.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      return [];
    }

    final doc = html_parser.parse(response.body);
    final novelList = <Novel>[];
    final items = doc.querySelectorAll('li.booklink');

    for (final item in items) {
      final anchor = item.querySelector('a.link');
      if (anchor == null) continue;

      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final fullUrl = _resolveUrl(href);
      final rawTitle = item.querySelector('.title')?.text.trim() ?? '';
      if (rawTitle.isEmpty) continue;

      final author = item.querySelector('.subtitle')?.text.trim() ?? 'Unknown Author';

      // Extract book id (e.g. 1342)
      final bookNum = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      String coverUrl = '';
      if (bookNum.isNotEmpty) {
        coverUrl = '$baseUrl/cache/epub/$bookNum/pg$bookNum.cover.medium.jpg';
      }

      novelList.add(Novel(
        id: '${id}_$bookNum',
        sourceId: id,
        title: rawTitle,
        author: author,
        coverUrl: coverUrl,
        sourceUrl: fullUrl,
        status: 'COMPLETED',
      ));
    }

    return novelList;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('Failed to load novel details from Project Gutenberg ($novelUrl)');
    }

    final doc = html_parser.parse(response.body);

    final rawTitleEl = doc.querySelector('#book_title');
    String title = rawTitleEl?.text.trim() ?? 'Untitled';
    if (title.contains(' by ')) {
      title = title.split(' by ').first.trim();
    }

    // Author
    String author = 'Unknown Author';
    final authorEl = doc.querySelector('a[href*="/ebooks/author/"]');
    if (authorEl != null) {
      final text = authorEl.text.trim();
      final match = RegExp(r'by\s+(.*)', caseSensitive: false).firstMatch(text);
      author = match != null ? match.group(1)!.trim() : text;
    }

    // Cover
    final bookNum = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
    String coverUrl = '';
    if (bookNum.isNotEmpty) {
      coverUrl = '$baseUrl/cache/epub/$bookNum/pg$bookNum.cover.medium.jpg';
    }

    // Subjects / Genres
    final genres = <String>[];
    for (final row in doc.querySelectorAll('tr[property*="dcterms:subject"], tr[about*="subject"]')) {
      final td = row.querySelector('td');
      if (td != null) {
        final text = td.text.trim();
        if (text.isNotEmpty && !genres.contains(text)) {
          genres.add(text);
        }
      }
    }

    // Summary / Description
    String description = '';
    final summaryEl = doc.querySelector('tr[property*="dcterms:description"] td, .summary, [id*="summary"]');
    if (summaryEl != null) {
      description = summaryEl.text.trim();
    } else if (genres.isNotEmpty) {
      description = 'Subjects: ${genres.join(", ")}';
    }

    return Novel(
      id: '${id}_$bookNum',
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
    final bookNum = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
    if (bookNum.isEmpty) return [];

    final htmlUrl = '$baseUrl/cache/epub/$bookNum/pg$bookNum-images.html';
    final response = await _client.get(Uri.parse(htmlUrl), headers: _headers);
    if (response.statusCode != 200) {
      // Fallback without -images
      final fallbackUrl = '$baseUrl/cache/epub/$bookNum/pg$bookNum.html';
      final fbResp = await _client.get(Uri.parse(fallbackUrl), headers: _headers);
      if (fbResp.statusCode != 200) return [];
      return _extractChaptersFromHtml(fbResp.body, fallbackUrl, bookNum);
    }

    return _extractChaptersFromHtml(response.body, htmlUrl, bookNum);
  }

  List<Chapter> _extractChaptersFromHtml(String html, String bookHtmlUrl, String bookNum) {
    final doc = html_parser.parse(html);

    // Strip boilerplates
    doc.querySelectorAll('.pg-boilerplate, header#pg-header, section#pg-footer').forEach((el) => el.remove());

    final chapters = <Chapter>[];
    final headings = doc.querySelectorAll('h2, h3, h4');

    int index = 1;
    for (final h in headings) {
      final text = h.text.trim();
      final lower = text.toLowerCase();

      // Check if heading looks like a chapter/section
      final isChapter = lower.contains('chapter') ||
          lower.contains('letter') ||
          lower.contains('book') ||
          lower.contains('part') ||
          lower.contains('canto') ||
          lower.contains('act') ||
          lower.contains('scene') ||
          lower.contains('prologue') ||
          lower.contains('epilogue') ||
          lower.contains('preface') ||
          RegExp(r'^[ivxlcdm]+\b', caseSensitive: false).hasMatch(text);

      if (!isChapter && text.length > 50) continue;
      if (lower.contains('contents') || lower.contains('illustration')) continue;

      final anchor = h.querySelector('a[id]');
      final anchorId = anchor?.attributes['id'] ?? h.attributes['id'] ?? 'h_$index';
      final chTitle = text.isNotEmpty ? text : 'Chapter $index';

      chapters.add(Chapter(
        id: '${id}_${bookNum}_$index',
        novelId: '${id}_$bookNum',
        title: chTitle,
        url: '$bookHtmlUrl#$anchorId',
        chapterNumber: index.toDouble(),
      ));
      index++;
    }

    // Fallback if no headings matched (e.g. poetry or short works)
    if (chapters.isEmpty) {
      final pList = doc.querySelectorAll('p');
      final totalP = pList.length;
      final chunkSize = 30;
      final totalChunks = (totalP / chunkSize).ceil().clamp(1, 9999);

      for (int i = 0; i < totalChunks; i++) {
        chapters.add(Chapter(
          id: '${id}_${bookNum}_${i + 1}',
          novelId: '${id}_$bookNum',
          title: 'Part ${i + 1}',
          url: '$bookHtmlUrl#part_${i + 1}',
          chapterNumber: (i + 1).toDouble(),
        ));
      }
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final uri = Uri.parse(chapterUrl);
    final anchor = uri.fragment;
    final htmlUrl = uri.replace(fragment: '').toString();

    final response = await _client.get(Uri.parse(htmlUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw HttpException('Failed to load chapter content from $chapterUrl');
    }

    final doc = html_parser.parse(response.body);
    doc.querySelectorAll('.pg-boilerplate, header#pg-header, section#pg-footer').forEach((el) => el.remove());

    final rawParas = <String>[];

    if (anchor.startsWith('part_')) {
      final partNum = int.tryParse(anchor.replaceAll('part_', '')) ?? 1;
      const chunkSize = 30;
      final pList = doc.querySelectorAll('p');
      final start = (partNum - 1) * chunkSize;
      final end = (start + chunkSize).clamp(0, pList.length);

      for (int i = start; i < end; i++) {
        final t = pList[i].text.trim();
        if (t.isNotEmpty) rawParas.add(t);
      }
    } else {
      // Find the element by id
      dom.Element? target = doc.getElementById(anchor);
      if (target == null && anchor.isNotEmpty) {
        target = doc.querySelector('a[id="$anchor"]');
      }

      dom.Element? heading = target;
      if (heading != null && !['H2', 'H3', 'H4'].contains(heading.localName?.toUpperCase())) {
        heading = heading.parent;
        while (heading != null && !['H2', 'H3', 'H4'].contains(heading.localName?.toUpperCase())) {
          heading = heading.parent;
        }
      }

      if (heading != null) {
        // Collect following siblings until next heading
        dom.Element? curr = heading.nextElementSibling;
        while (curr != null) {
          if (['H2', 'H3', 'H4'].contains(curr.localName?.toUpperCase())) {
            break;
          }
          if (curr.localName?.toUpperCase() == 'P') {
            final t = curr.text.trim();
            if (t.isNotEmpty) rawParas.add(t);
          } else {
            for (final p in curr.querySelectorAll('p')) {
              final t = p.text.trim();
              if (t.isNotEmpty) rawParas.add(t);
            }
          }
          curr = curr.nextElementSibling;
        }
      }
    }

    if (rawParas.isEmpty) {
      // Ultimate fallback: take reader p tags
      for (final p in doc.querySelectorAll('p').take(40)) {
        final t = p.text.trim();
        if (t.isNotEmpty) rawParas.add(t);
      }
    }

    final paragraphs = TextCleaner.cleanParagraphs(rawParas);
    final rawText = TextCleaner.toCleanRawText(paragraphs);

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final bookNum = segments.length > 2 ? segments[segments.length - 2] : 'book';

    return ChapterContent(
      chapterId: '${id}_${bookNum}_$anchor',
      novelId: '${id}_$bookNum',
      title: 'Chapter',
      rawText: rawText,
      paragraphs: paragraphs,
    );
  }

  String _resolveUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('//')) {
      return 'https:$path';
    }
    if (path.startsWith('/')) {
      return '$baseUrl$path';
    }
    return '$baseUrl/$path';
  }
}

