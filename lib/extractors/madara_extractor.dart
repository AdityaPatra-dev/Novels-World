import 'dart:io';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/services/webview_session_manager.dart';
import '../core/utils/text_cleaner.dart';
import 'novel_source.dart';

class MadaraExtractor implements NovelSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final String baseUrl;
  @override
  final String lang;
  @override
  final String iconUrl;
  @override
  final int estimatedNovelCount;

  final bool useNewChapterEndpoint;
  final String? customChapterAjaxUrl;
  final String? customContentSelector;
  final String? customPopularPath;

  late final http.Client _client;

  MadaraExtractor({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lang = 'en',
    this.iconUrl = '',
    this.estimatedNovelCount = 1000,
    this.useNewChapterEndpoint = false,
    this.customChapterAjaxUrl,
    this.customContentSelector,
    this.customPopularPath,
  }) {
    final nativeHttpClient = HttpClient();
    nativeHttpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
    _client = IOClient(nativeHttpClient);
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

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = Uri.encodeComponent(query);
    final targetUrl = page == 1
        ? '$baseUrl/?s=$cleanQuery&post_type=wp-manga'
        : '$baseUrl/page/$page/?s=$cleanQuery&post_type=wp-manga';

    try {
      final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        final list = parseNovelList(response.body);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(targetUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    return [];
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final candidates = [
      if (customPopularPath != null)
        page == 1 ? '$baseUrl$customPopularPath' : '$baseUrl${customPopularPath!.contains('?') ? customPopularPath!.replaceFirst('?', '/page/$page/?') : '${customPopularPath!}page/$page/'}',
      page == 1 ? '$baseUrl/novel/?m_orderby=views' : '$baseUrl/novel/page/$page/?m_orderby=views',
      page == 1 ? '$baseUrl/series/?m_orderby=views' : '$baseUrl/series/page/$page/?m_orderby=views',
      page == 1 ? '$baseUrl/mangas/?m_orderby=views' : '$baseUrl/mangas/page/$page/?m_orderby=views',
      page == 1 ? '$baseUrl/?m_orderby=trending' : '$baseUrl/page/$page/?m_orderby=trending',
      page == 1 ? '$baseUrl/?m_orderby=views&post_type=wp-manga' : '$baseUrl/page/$page/?m_orderby=views&post_type=wp-manga',
      page == 1 ? '$baseUrl/manga/?m_orderby=views' : '$baseUrl/manga/page/$page/?m_orderby=views',
      page == 1 ? '$baseUrl/novel/' : '$baseUrl/novel/page/$page/',
      page == 1 ? '$baseUrl/series/' : '$baseUrl/series/page/$page/',
      page == 1 ? '$baseUrl/mangas/' : '$baseUrl/mangas/page/$page/',
      page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/',
    ];

    for (final url in candidates) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _headers);
        if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
          final list = parseNovelList(resp.body);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    final primaryUrl = page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load popular novels from $name. Please try another source or tap Open in WebView.');
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final candidates = [
      page == 1 ? '$baseUrl/novel/?m_orderby=latest' : '$baseUrl/novel/page/$page/?m_orderby=latest',
      page == 1 ? '$baseUrl/series/?m_orderby=latest' : '$baseUrl/series/page/$page/?m_orderby=latest',
      page == 1 ? '$baseUrl/?m_orderby=latest&post_type=wp-manga' : '$baseUrl/page/$page/?m_orderby=latest&post_type=wp-manga',
      page == 1 ? '$baseUrl/manga/?m_orderby=latest' : '$baseUrl/manga/page/$page/?m_orderby=latest',
      page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/',
    ];

    for (final url in candidates) {
      try {
        final resp = await _client.get(Uri.parse(url), headers: _headers);
        if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
          final list = parseNovelList(resp.body);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    final primaryUrl = page == 1 ? '$baseUrl/' : '$baseUrl/page/$page/';
    final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(primaryUrl);
    if (wvHtml != null && !wvHtml.contains('Just a moment...')) {
      final list = parseNovelList(wvHtml);
      if (list.isNotEmpty) return list;
    }

    throw HttpException('Could not load latest novels from $name. Please try another source or tap Open in WebView.');
  }

  List<Novel> parseNovelList(String htmlBody) {
    final document = html_parser.parse(htmlBody);
    final List<Novel> novels = [];
    final seenUrls = <String>{};

    final items = document.querySelectorAll(
      '.c-tabs-item__content, .page-item-detail, .badge-pos-1, .row.c-tabs-item__content, .page-listing-item, .post-item, .novel-item, .col-6.col-md-3, .col-6.col-md-2, article.post',
    );

    for (final item in items) {
      final titleAnchor = item.querySelector('.post-title h3 a, .post-title h4 a, h3.h4 a, .post-title a, h3 a, h2 a');
      if (titleAnchor == null) continue;

      final title = titleAnchor.text.trim();
      final url = _cleanUrl(titleAnchor.attributes['href'] ?? '');
      if (url.isEmpty || title.isEmpty || seenUrls.contains(url)) continue;
      if (!TextCleaner.isValidNovelTitle(title, url)) continue;
      seenUrls.add(url);

      var img = item.querySelector('.item-thumb img, img');
      img ??= item.parent?.querySelector('.item-thumb img, img');
      img ??= item.previousElementSibling?.querySelector('.item-thumb img, img');

      String cover = '';
      if (img != null) {
        cover = img.attributes['data-src'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['data-original'] ??
            img.attributes['data-cfsrc'] ??
            img.attributes['data-srcset']?.split(' ').first ??
            img.attributes['srcset']?.split(' ').first ??
            img.attributes['src'] ??
            '';
        cover = _cleanUrl(cover);
        cover = cover.replaceAll(RegExp(r'render_js.*$'), '');
        if (cover.startsWith('data:') || cover.contains('blank.gif') || cover.contains('dflazy.jpg')) {
          cover = '';
        }
      }

      final authorEl = item.querySelector('.mg_author .summary-content a, .author a, .post-author');
      final author = authorEl?.text.trim() ?? 'Unknown Author';

      final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
      final slug = segments.isNotEmpty ? segments.last : url.hashCode.toString();
      final novelId = '${id}_$slug';

      novels.add(
        Novel(
          id: novelId,
          sourceId: id,
          title: title,
          author: author,
          coverUrl: cover,
          sourceUrl: url,
        ),
      );
    }

    // Fallback: If no structured items matched, find novel links directly
    if (novels.isEmpty) {
      final titleAnchors = document.querySelectorAll('.post-title a, .novel-title a, .manga-title a');
      for (final anchor in titleAnchors) {
        final title = anchor.text.trim();
        final url = _cleanUrl(anchor.attributes['href'] ?? '');
        if (url.isEmpty || title.isEmpty || seenUrls.contains(url)) continue;
        if (!TextCleaner.isValidNovelTitle(title, url)) continue;
        if (url == baseUrl || url.endsWith('/novel/') || url.endsWith('/series/')) continue;
        seenUrls.add(url);

        final parent = anchor.parent?.parent;
        final img = parent?.querySelector('img');
        String cover = '';
        if (img != null) {
          cover = _cleanUrl(img.attributes['data-src'] ??
              img.attributes['data-lazy-src'] ??
              img.attributes['data-original'] ??
              img.attributes['data-srcset']?.split(' ').first ??
              img.attributes['src'] ??
              '');
          cover = cover.replaceAll(RegExp(r'render_js.*$'), '');
          if (cover.startsWith('data:') || cover.contains('blank.gif') || cover.contains('dflazy.jpg')) {
            cover = '';
          }
        }

        final segments = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
        final slug = segments.isNotEmpty ? segments.last : url.hashCode.toString();
        novels.add(
          Novel(
            id: '${id}_$slug',
            sourceId: id,
            title: title,
            author: 'Unknown Author',
            coverUrl: cover,
            sourceUrl: url,
          ),
        );
      }
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    String body = '';
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        body = response.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw Exception('Failed to load novel details for $novelUrl');
    }

    final document = html_parser.parse(body);

    final title = document.querySelector('.post-title h1, .post-title h3, .post-title')?.text.trim() ?? 'Untitled';

    final img = document.querySelector('.summary_image img');
    String cover = '';
    if (img != null) {
      cover = img.attributes['data-src'] ??
          img.attributes['data-lazy-src'] ??
          img.attributes['srcset']?.split(' ').first ??
          img.attributes['src'] ??
          '';
      cover = _cleanUrl(cover);
    }

    final author = document.querySelector('.author-content a, .mg_author .summary-content a')?.text.trim() ??
        'Unknown Author';

    final genres = document
        .querySelectorAll('.genres-content a, .genres a')
        .map((e) => e.text.trim())
        .where((g) => g.isNotEmpty)
        .toList();

    final status = document.querySelector('.post-status .post-content_item .summary-content')?.text.trim() ??
        'ONGOING';

    final synopsisEls = document.querySelectorAll(
      '.summary__content p, .description-summary p, .manga-excerpt p, .summary__content',
    );
    String description = '';
    if (synopsisEls.isNotEmpty) {
      description = synopsisEls.map((e) => e.text.trim()).where((s) => s.isNotEmpty).join('\n\n');
    }

    final novelId = '${id}_${Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).last}';

    return Novel(
      id: novelId,
      sourceId: id,
      title: title,
      author: author,
      description: description,
      coverUrl: cover,
      genres: genres,
      status: status.toUpperCase().contains('COMPLET') ? 'COMPLETED' : 'ONGOING',
      sourceUrl: novelUrl,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    String body = '';
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        body = response.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw Exception('Failed to load chapter list for $novelUrl');
    }

    final document = html_parser.parse(body);
    final novelId = '${id}_${Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).last}';

    // 1. Try static chapter parsing
    List<Chapter> chapters = _parseChaptersFromDoc(document, novelId);
    if (chapters.isNotEmpty) {
      return chapters;
    }

    // 2. Try newer Madara AJAX chapter endpoint ($novelUrl/ajax/chapters/)
    final cleanUrl = novelUrl.endsWith('/') ? novelUrl : '$novelUrl/';
    try {
      final ajaxResp = await _client.post(
        Uri.parse('${cleanUrl}ajax/chapters/'),
        headers: {
          ..._headers,
          'X-Requested-With': 'XMLHttpRequest',
        },
      );
      if (ajaxResp.statusCode == 200) {
        final ajaxDoc = html_parser.parse(ajaxResp.body);
        chapters = _parseChaptersFromDoc(ajaxDoc, novelId);
        if (chapters.isNotEmpty) {
          return chapters;
        }
      }
    } catch (_) {}

    // 3. Try legacy Madara admin-ajax.php endpoint
    final mangaIdInput = document.querySelector('#wp-manga-post-id, input.rating-post-id, [data-id]');
    final mangaId = mangaIdInput?.attributes['value'] ?? mangaIdInput?.attributes['data-id'];

    if (mangaId != null && mangaId.isNotEmpty) {
      final ajaxUrl = customChapterAjaxUrl ?? '$baseUrl/wp-admin/admin-ajax.php';
      try {
        final ajaxResp = await _client.post(
          Uri.parse(ajaxUrl),
          headers: {
            ..._headers,
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
          },
          body: {
            'action': 'manga_get_chapters',
            'manga': mangaId,
          },
        );

        if (ajaxResp.statusCode == 200) {
          final ajaxDoc = html_parser.parse(ajaxResp.body);
          chapters = _parseChaptersFromDoc(ajaxDoc, novelId);
          if (chapters.isNotEmpty) {
            return chapters;
          }
        }
      } catch (_) {}
    }

    return chapters;
  }

  List<Chapter> _parseChaptersFromDoc(dom.Document doc, String novelId) {
    var chapterEls = doc.querySelectorAll(
      'ul.main.version-chap li.wp-manga-chapter, li.wp-manga-chapter, .wp-manga-chapter, .listing-chapters_wrap li, .chapter-list li, .sub-chap-list li',
    );
    final List<Chapter> list = [];

    for (final el in chapterEls) {
      final a = el.querySelector('a');
      if (a == null) continue;

      final url = _cleanUrl(a.attributes['href'] ?? '');
      final title = a.text.trim();
      if (url.isEmpty || title.isEmpty) continue;

      final date = el.querySelector('.chapter-release-date')?.text.trim();
      final chapterId = '${novelId}_${Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).last}';

      // Parse chapter number if available in title
      final match = RegExp(r'chapter\s+(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(title);
      final double? chapterNum = match != null ? double.tryParse(match.group(1)!) : null;

      list.add(
        Chapter(
          id: chapterId,
          novelId: novelId,
          title: title,
          chapterNumber: chapterNum,
          url: url,
          releaseDate: date,
        ),
      );
    }

    // Chapters in Madara are often listed newest first; reverse so Chapter 1 is first
    return list.reversed.toList();
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    String body = '';
    try {
      final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
      if (response.statusCode == 200 && !response.body.contains('Just a moment...')) {
        body = response.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(chapterUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw Exception('Failed to load chapter content: $chapterUrl');
    }

    final document = html_parser.parse(body);

    final title = document.querySelector('.cha-tit h3, h2.chapter-title, .breadcrumb li.active')?.text.trim() ??
        'Chapter Content';

    final selector = customContentSelector ??
        '.text-left, .reading-content, .entry-content, .cha-words, #chapter-content';
    final contentContainer = document.querySelector(selector);

    List<String> rawParagraphs = [];

    if (contentContainer != null) {
      final pTags = contentContainer.querySelectorAll('p');
      if (pTags.isNotEmpty) {
        rawParagraphs = pTags.map((p) => p.text).toList();
      } else {
        // Fallback for content separated by <br> tags
        final innerHtml = contentContainer.innerHtml;
        rawParagraphs = innerHtml.split(RegExp(r'<br\s*/?>', caseSensitive: false));
      }
    }

    final cleanedParagraphs = TextCleaner.cleanParagraphs(rawParagraphs);
    final rawText = TextCleaner.toCleanRawText(cleanedParagraphs);

    final chapterId = Uri.parse(chapterUrl).pathSegments.where((s) => s.isNotEmpty).last;

    return ChapterContent(
      chapterId: chapterId,
      novelId: '',
      title: title,
      rawText: rawText,
      paragraphs: cleanedParagraphs,
    );
  }
}
