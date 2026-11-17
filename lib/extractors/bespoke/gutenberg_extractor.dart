import 'dart:convert';
import 'dart:io';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/services/epub_service.dart';
import 'local_epub_extractor.dart';
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
  final String iconUrl = 'https://www.gutenberg.org/favicon.ico';

  @override
  final int estimatedNovelCount = 70000;

  late final http.Client _client;

  GutenbergExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$baseUrl/',
  };

  Future<String> _fetchHtml(String url) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        return response.body;
      }
    } catch (_) {}

    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
    if (wvHtml != null && wvHtml.isNotEmpty) {
      return wvHtml;
    }
    throw HttpException('Failed to load HTML from $url');
  }

  static const String _gutenbergBase = 'https://www.gutenberg.org';

  static final List<Novel> _topGutenbergClassics = [
    Novel(
      id: 'gutenberg_1342',
      sourceId: 'gutenberg',
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      description: 'A romantic classic following the turbulent relationship between Elizabeth Bennet and Fitzwilliam Darcy.',
      coverUrl: '$_gutenbergBase/cache/epub/1342/pg1342.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/1342',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/1342.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Romance', 'Historical Fiction'],
    ),
    Novel(
      id: 'gutenberg_84',
      sourceId: 'gutenberg',
      title: 'Frankenstein; or, The Modern Prometheus',
      author: 'Mary Wollstonecraft Shelley',
      description: 'Gothic masterpiece about scientist Victor Frankenstein and the sentient creature he creates.',
      coverUrl: '$_gutenbergBase/cache/epub/84/pg84.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/84',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/84.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Gothic', 'Science Fiction'],
    ),
    Novel(
      id: 'gutenberg_11',
      sourceId: 'gutenberg',
      title: "Alice's Adventures in Wonderland",
      author: 'Lewis Carroll',
      description: 'The whimsical tale of Alice tumbling down a rabbit hole into a fantastical world.',
      coverUrl: '$_gutenbergBase/cache/epub/11/pg11.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/11',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/11.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Fantasy', 'Children'],
    ),
    Novel(
      id: 'gutenberg_345',
      sourceId: 'gutenberg',
      title: 'Dracula',
      author: 'Bram Stoker',
      description: 'The definitive vampire horror novel following Count Dracula\'s journey to England.',
      coverUrl: '$_gutenbergBase/cache/epub/345/pg345.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/345',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/345.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Horror', 'Gothic'],
    ),
    Novel(
      id: 'gutenberg_1661',
      sourceId: 'gutenberg',
      title: 'The Adventures of Sherlock Holmes',
      author: 'Arthur Conan Doyle',
      description: 'Twelve detective stories featuring the legendary Baker Street sleuth Sherlock Holmes and Dr. Watson.',
      coverUrl: '$_gutenbergBase/cache/epub/1661/pg1661.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/1661',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/1661.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Mystery', 'Detective'],
    ),
    Novel(
      id: 'gutenberg_98',
      sourceId: 'gutenberg',
      title: 'A Tale of Two Cities',
      author: 'Charles Dickens',
      description: 'Historical novel set in London and Paris before and during the French Revolution.',
      coverUrl: '$_gutenbergBase/cache/epub/98/pg98.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/98',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/98.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Historical Fiction', 'Literature'],
    ),
    Novel(
      id: 'gutenberg_174',
      sourceId: 'gutenberg',
      title: 'The Picture of Dorian Gray',
      author: 'Oscar Wilde',
      description: 'Philosophical gothic tale of aestheticism, moral decay, and an aging portrait.',
      coverUrl: '$_gutenbergBase/cache/epub/174/pg174.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/174',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/174.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Gothic', 'Philosophy'],
    ),
    Novel(
      id: 'gutenberg_2701',
      sourceId: 'gutenberg',
      title: 'Moby Dick; Or, The Whale',
      author: 'Herman Melville',
      description: 'Epic saga of Captain Ahab and his obsessive quest for the elusive white whale.',
      coverUrl: '$_gutenbergBase/cache/epub/2701/pg2701.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/2701',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/2701.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Adventure', 'Literature'],
    ),
    Novel(
      id: 'gutenberg_1260',
      sourceId: 'gutenberg',
      title: 'Jane Eyre: An Autobiography',
      author: 'Charlotte Brontë',
      description: 'Passionate bildungsroman following an orphaned governess and her bond with Mr. Rochester.',
      coverUrl: '$_gutenbergBase/cache/epub/1260/pg1260.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/1260',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/1260.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Romance', 'Gothic'],
    ),
    Novel(
      id: 'gutenberg_1400',
      sourceId: 'gutenberg',
      title: 'Great Expectations',
      author: 'Charles Dickens',
      description: 'The personal growth and fortunes of the orphan Pip amidst Victorian society.',
      coverUrl: '$_gutenbergBase/cache/epub/1400/pg1400.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/1400',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/1400.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Literature', 'Victorian'],
    ),
    Novel(
      id: 'gutenberg_43',
      sourceId: 'gutenberg',
      title: 'The Strange Case of Dr. Jekyll and Mr. Hyde',
      author: 'Robert Louis Stevenson',
      description: 'Chilling psychological exploration of the dual nature of man.',
      coverUrl: '$_gutenbergBase/cache/epub/43/pg43.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/43',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/43.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Mystery', 'Horror'],
    ),
    Novel(
      id: 'gutenberg_1184',
      sourceId: 'gutenberg',
      title: 'The Count of Monte Cristo',
      author: 'Alexandre Dumas',
      description: 'Historical adventure novel of betrayal, immense wealth, and elaborate retribution.',
      coverUrl: '$_gutenbergBase/cache/epub/1184/pg1184.cover.medium.jpg',
      sourceUrl: '$_gutenbergBase/ebooks/1184',
      status: 'COMPLETED',
      isFullBook: true,
      bookDownloadUrl: '$_gutenbergBase/ebooks/1184.epub3.images',
      bookFormat: 'epub',
      genres: const ['Classics', 'Adventure', 'Historical Fiction'],
    ),
  ];

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final startIndex = (page - 1) * 25 + 1;
    final url = '$baseUrl/ebooks/search/?sort_order=downloads&start_index=$startIndex';
    final live = await _parseSearchGrid(url);
    if (live.isNotEmpty) return live;
    return _topGutenbergClassics;
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final startIndex = (page - 1) * 25 + 1;
    final url = '$baseUrl/ebooks/search/?sort_order=release_date&start_index=$startIndex';
    final live = await _parseSearchGrid(url);
    if (live.isNotEmpty) return live;
    return _topGutenbergClassics.reversed.toList();
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final startIndex = (page - 1) * 25 + 1;
    final encoded = Uri.encodeComponent(query.trim());
    final url = '$baseUrl/ebooks/search/?query=$encoded&start_index=$startIndex';
    final live = await _parseSearchGrid(url);
    if (live.isNotEmpty) return live;

    return _topGutenbergClassics.where((n) {
      return n.title.toLowerCase().contains(cleanQuery) ||
          n.author.toLowerCase().contains(cleanQuery) ||
          n.description.toLowerCase().contains(cleanQuery);
    }).toList();
  }

  Future<List<Novel>> _parseSearchGrid(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return _fetchFromGutendex(url);
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

        final downloadUrl = bookNum.isNotEmpty ? '$baseUrl/ebooks/$bookNum.epub.images' : '';
        novelList.add(Novel(
          id: '${id}_$bookNum',
          sourceId: id,
          title: rawTitle,
          author: author,
          coverUrl: coverUrl,
          sourceUrl: fullUrl,
          status: 'COMPLETED',
          isFullBook: true,
          bookDownloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
          bookFormat: 'epub',
        ));
      }

      if (novelList.isNotEmpty) {
        return novelList;
      }
      return _fetchFromGutendex(url);
    } catch (_) {
      return _fetchFromGutendex(url);
    }
  }

  Future<List<Novel>> _fetchFromGutendex(String url) async {
    try {
      final uri = Uri.parse(url);
      final query = uri.queryParameters['query'];
      final sortOrder = uri.queryParameters['sort_order'];
      final startIndex = int.tryParse(uri.queryParameters['start_index'] ?? '1') ?? 1;
      final page = (startIndex ~/ 25) + 1;

      String gutendexUrl;
      if (query != null && query.isNotEmpty) {
        gutendexUrl = 'https://gutendex.com/books/?search=${Uri.encodeComponent(query)}&page=$page';
      } else if (sortOrder == 'release_date') {
        gutendexUrl = 'https://gutendex.com/books/?sort=ascending&page=$page';
      } else {
        gutendexUrl = 'https://gutendex.com/books/?sort=popular&page=$page';
      }

      final resp = await _client.get(Uri.parse(gutendexUrl), headers: {
        'User-Agent': WebViewSessionManager.defaultUserAgent,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 3));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final books = data['results'] as List?;
      if (books == null) return [];

      final list = <Novel>[];
      for (final item in books) {
        final b = item as Map<String, dynamic>;
        final bookId = b['id']?.toString() ?? '';
        if (bookId.isEmpty) continue;

        final rawTitle = b['title']?.toString() ?? 'Untitled';
        final title = TextCleaner.cleanNovelTitle(rawTitle);

        final authors = (b['authors'] as List?)
                ?.map((a) => (a as Map)['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .join(', ') ??
            'Unknown Author';

        final formats = b['formats'] as Map<String, dynamic>? ?? {};
        final coverUrl = formats['image/jpeg']?.toString() ??
            '$baseUrl/cache/epub/$bookId/pg$bookId.cover.medium.jpg';
        final epubUrl = formats['application/epub+zip']?.toString() ??
            '$baseUrl/ebooks/$bookId.epub.images';

        final summaries = b['summaries'] as List?;
        final desc = summaries != null && summaries.isNotEmpty
            ? summaries.first.toString()
            : ((b['subjects'] as List?)?.take(3).join(' • ') ?? 'Public Domain Classic');

        list.add(Novel(
          id: '${id}_$bookId',
          sourceId: id,
          title: title,
          author: authors,
          description: desc,
          coverUrl: coverUrl,
          sourceUrl: '$baseUrl/ebooks/$bookId',
          status: 'COMPLETED',
          isFullBook: true,
          bookDownloadUrl: epubUrl,
          bookFormat: 'epub',
          genres: const ['Classics', 'Public Domain'],
        ));
      }

      return list;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getNovelDetails(novelUrl);
    }
    final bookNum = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';

    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode != 200) {
        if (bookNum.isNotEmpty) {
          final curated = _topGutenbergClassics.firstWhere(
            (n) => n.id == '${id}_$bookNum' || n.sourceUrl.endsWith('/$bookNum'),
            orElse: () => Novel(
              id: '${id}_$bookNum',
              sourceId: id,
              title: 'Project Gutenberg Book #$bookNum',
              author: 'Unknown Author',
              description: 'Public domain book from Project Gutenberg.',
              coverUrl: '$baseUrl/cache/epub/$bookNum/pg$bookNum.cover.medium.jpg',
              genres: const ['Classics', 'Public Domain'],
              status: 'COMPLETED',
              sourceUrl: novelUrl,
              isFullBook: true,
              bookDownloadUrl: '$baseUrl/ebooks/$bookNum.epub.images',
              bookFormat: 'epub',
            ),
          );
          return curated;
        }
        throw HttpException('Failed to load novel details from Project Gutenberg ($novelUrl)');
      }

      final doc = html_parser.parse(response.body);

    final rawTitleEl = doc.querySelector('#book_title');
    String title = rawTitleEl?.text.trim() ?? 'Untitled';
    if (title.contains(' by ')) {
      title = title.split(' by ').first.trim();
    }
    title = TextCleaner.cleanNovelTitle(title);

    // Author
    String author = 'Unknown Author';
    final authorEl = doc.querySelector('a[href*="/ebooks/author/"]');
    if (authorEl != null) {
      final text = authorEl.text.trim();
      final match = RegExp(r'by\s+(.*)', caseSensitive: false).firstMatch(text);
      author = match != null ? match.group(1)!.trim() : text;
    }

    // Cover
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

    final downloadUrl = bookNum.isNotEmpty ? '$baseUrl/ebooks/$bookNum.epub.images' : '';
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
      isFullBook: true,
      bookDownloadUrl: downloadUrl.isNotEmpty ? downloadUrl : null,
      bookFormat: 'epub',
    );
    } catch (_) {
      if (bookNum.isNotEmpty) {
        return Novel(
          id: '${id}_$bookNum',
          sourceId: id,
          title: 'Project Gutenberg Book #$bookNum',
          author: 'Unknown Author',
          description: 'Public domain book from Project Gutenberg.',
          coverUrl: '$baseUrl/cache/epub/$bookNum/pg$bookNum.cover.medium.jpg',
          genres: const ['Classics', 'Public Domain'],
          status: 'COMPLETED',
          sourceUrl: novelUrl,
          isFullBook: true,
          bookDownloadUrl: '$baseUrl/ebooks/$bookNum.epub.images',
          bookFormat: 'epub',
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    if (novelUrl.startsWith('file:') || novelUrl.startsWith('/')) {
      return LocalEpubExtractor().getChapterList(novelUrl, onBatchLoaded: onBatchLoaded);
    }
    final bookNum = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
    if (bookNum.isEmpty) return [];

    try {
      final htmlUrl = '$baseUrl/cache/epub/$bookNum/pg$bookNum-images.html';
      final html = await _fetchHtml(htmlUrl);
      final chs = _extractChaptersFromHtml(html, htmlUrl, bookNum);
      if (chs.isNotEmpty) {
        onBatchLoaded?.call(chs);
        return chs;
      }
    } catch (_) {}

    // Fallback: provide a full book download/reading chapter
    final fallbackChapter = [
      Chapter(
        id: 'gutenberg_${bookNum}_ch_1',
        novelId: 'gutenberg_$bookNum',
        title: 'Complete Book / EPUB Edition',
        url: '$baseUrl/ebooks/$bookNum.epub3.images',
        chapterNumber: 1.0,
      ),
    ];
    onBatchLoaded?.call(fallbackChapter);
    return fallbackChapter;
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
    if (chapterUrl.startsWith('file:') || chapterUrl.startsWith('/')) {
      return EpubService().loadChapterContent(chapterUrl);
    }
    final uri = Uri.parse(chapterUrl);
    final anchor = uri.fragment;
    final htmlUrl = uri.replace(fragment: '').toString();

    final html = await _fetchHtml(htmlUrl);
    final doc = html_parser.parse(html);
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

