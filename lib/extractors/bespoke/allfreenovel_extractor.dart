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

/// Extractor for AllFreeNovel (https://allfreenovel.com).
/// Massive mainstream bookstore novel aggregator hosting 280,000+ published paperbacks,
/// commercial fiction, bestsellers, romance, thrillers, fantasy, and classics.
class AllFreeNovelExtractor implements NovelSource {
  @override
  final String id = 'allfreenovel';

  @override
  final String name = 'AllFreeNovel';

  @override
  final String baseUrl = 'https://allfreenovel.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 280000;

  late final http.Client _client;

  AllFreeNovelExtractor({http.Client? client}) {
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (cert, host, port) => true;
      nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
      _client = IOClient(nativeHttpClient);
    }
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
    // TopBooks lists the all-time most popular bookstore novels
    final url = page == 1 ? '$baseUrl/Book/TopBooks' : '$baseUrl/Book/LastRelease/$page';
    return _parseBookGrid(url);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final url = '$baseUrl/Book/LastRelease/$page';
    return _parseBookGrid(url);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final encoded = Uri.encodeComponent(query.trim());
    final url = '$baseUrl/Book/Search?searchString=$encoded&page=$page';
    return _parseBookGrid(url);
  }

  Future<List<Novel>> _parseBookGrid(String url) async {
    String html = '';
    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200) {
        html = response.body;
      }
    } catch (_) {}

    if (html.isEmpty || html.contains('Just a moment...')) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null && wvHtml.isNotEmpty) {
        html = wvHtml;
      }
    }

    if (html.isEmpty) {
      return [];
    }

    final doc = html_parser.parse(html);
    final novelList = <Novel>[];
    final seenUrls = <String>{};

    // Each book entry has a link to /Book/Details/{id}/{slug}
    final detailAnchors = doc.querySelectorAll('a[href*="/Book/Details/"]');

    for (final a in detailAnchors) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final fullUrl = _resolveUrl(href);
      if (seenUrls.contains(fullUrl)) continue;

      // Extract title from span or img alt
      final titleSpan = a.querySelector('span');
      final imgEl = a.querySelector('img');
      String title = titleSpan?.text.trim() ?? imgEl?.attributes['alt']?.trim() ?? a.attributes['title']?.trim() ?? '';
      title = title.replaceAll(RegExp(r'^Read\s+', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+Online\s+for\s+Free.*$', caseSensitive: false), '')
          .trim();

      if (title.isEmpty) continue;

      // Locate surrounding card/row for author & cover
      dom.Element? parentRow = a.parent;
      while (parentRow != null && !parentRow.classes.contains('row')) {
        parentRow = parentRow.parent;
      }
      String author = 'Unknown Author';
      String coverUrl = '';

      if (parentRow != null) {
        final authorEl = parentRow.querySelector('a[href*="/Book/Author"]');
        if (authorEl != null) {
          author = authorEl.text.trim();
        }

        final coverImg = parentRow.querySelector('img.custom-card-img-book-list, img[src*="/Covers/"]');
        if (coverImg != null) {
          final src = coverImg.attributes['data-src'] ?? coverImg.attributes['src'];
          if (src != null && src.isNotEmpty) {
            coverUrl = _resolveUrl(src);
          }
        }
      }

      if (coverUrl.isEmpty && imgEl != null) {
        final src = imgEl.attributes['data-src'] ?? imgEl.attributes['src'];
        if (src != null && src.isNotEmpty) {
          coverUrl = _resolveUrl(src);
        }
      }

      seenUrls.add(fullUrl);

      final slug = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? fullUrl.hashCode.toString();
      final bookId = '${id}_$slug';

      novelList.add(Novel(
        id: bookId,
        sourceId: id,
        title: title,
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
    String html = '';
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200) {
        html = response.body;
      }
    } catch (_) {}

    if (html.isEmpty || html.contains('Just a moment...')) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null && wvHtml.isNotEmpty) {
        html = wvHtml;
      }
    }

    if (html.isEmpty) {
      throw HttpException('Failed to load novel details from AllFreeNovel ($novelUrl)');
    }

    final doc = html_parser.parse(html);

    final title = doc.querySelector('h1')?.text.trim() ?? 'Untitled';

    // Author
    String author = 'Unknown Author';
    final authorEl = doc.querySelector('h5 a[href*="/Book/Author"]');
    if (authorEl != null) {
      author = authorEl.text.trim();
    }

    // Cover
    String coverUrl = '';
    final coverEl = doc.querySelector('img.book-details-image, img[src*="/Covers/"]');
    if (coverEl != null) {
      final src = coverEl.attributes['data-src'] ?? coverEl.attributes['src'];
      if (src != null && src.isNotEmpty) {
        coverUrl = _resolveUrl(src);
      }
    }

    // Synopsis
    String description = '';
    final descEl = doc.querySelector('.noselect');
    if (descEl != null) {
      description = descEl.text.trim();
    }

    // Genres
    final genres = <String>[];
    for (final gEl in doc.querySelectorAll('h5 a[href*="/Book/Category/"]')) {
      final gName = gEl.text.trim();
      if (gName.isNotEmpty && !genres.contains(gName)) {
        genres.add(gName);
      }
    }

    final slug = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? novelUrl.hashCode.toString();

    return Novel(
      id: '${id}_$slug',
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
    String html = '';
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200) {
        html = response.body;
      }
    } catch (_) {}

    if (html.isEmpty || html.contains('Just a moment...')) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null && wvHtml.isNotEmpty) {
        html = wvHtml;
      }
    }

    if (html.isEmpty) {
      return [];
    }

    final doc = html_parser.parse(html);
    final pageListContainer = doc.querySelector('#PageList');
    if (pageListContainer == null) {
      return [];
    }

    final pageAnchors = pageListContainer.querySelectorAll('a[href*="/Page/Story/"]');
    final chapters = <Chapter>[];
    final slug = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? novelUrl.hashCode.toString();
    final novelId = '${id}_$slug';

    int index = 1;
    for (final a in pageAnchors) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final fullUrl = _resolveUrl(href);
      final rawTitle = a.text.trim();
      final title = rawTitle.isNotEmpty ? rawTitle : 'Page $index';

      chapters.add(Chapter(
        id: '${id}_${slug}_$index',
        novelId: novelId,
        title: title,
        url: fullUrl,
        chapterNumber: index.toDouble(),
      ));
      index++;
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    String html = '';
    try {
      final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
      if (response.statusCode == 200) {
        html = response.body;
      }
    } catch (_) {}

    if (html.isEmpty || html.contains('Just a moment...')) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(chapterUrl);
      if (wvHtml != null && wvHtml.isNotEmpty) {
        html = wvHtml;
      }
    }

    if (html.isEmpty) {
      throw HttpException('Failed to load chapter content from $chapterUrl');
    }

    final doc = html_parser.parse(html);

    final rawParas = <String>[];
    final storyTextElements = doc.querySelectorAll('p.storyText');

    for (final p in storyTextElements) {
      final text = p.text.trim();
      if (text.isNotEmpty) {
        rawParas.add(text);
      }
    }

    if (rawParas.isEmpty) {
      // Fallback: search main reader content
      final mainContainer = doc.querySelector('.container');
      if (mainContainer != null) {
        mainContainer.querySelectorAll('script, style, nav, header, footer, .card, .row').forEach((el) => el.remove());
        for (final p in mainContainer.querySelectorAll('p')) {
          final text = p.text.trim();
          if (text.length > 20 && !text.contains('All novels given here') && !text.contains('Contact Us')) {
            rawParas.add(text);
          }
        }
      }
    }

    final paragraphs = TextCleaner.cleanParagraphs(rawParas);
    final rawText = TextCleaner.toCleanRawText(paragraphs);

    final segments = Uri.parse(chapterUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final pageSlug = segments.isNotEmpty ? segments.last : chapterUrl.hashCode.toString();
    final novelSlug = segments.length > 2 ? segments[2] : 'novel';
    final novelId = '${id}_$novelSlug';
    final chapterId = '${id}_${novelSlug}_$pageSlug';

    final title = doc.querySelector('title')?.text.split('|').first.trim() ?? 'Page';

    return ChapterContent(
      chapterId: chapterId,
      novelId: novelId,
      title: title,
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

