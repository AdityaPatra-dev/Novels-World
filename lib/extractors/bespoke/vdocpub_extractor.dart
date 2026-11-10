import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke extractor for vdoc.pub (https://vdoc.pub).
/// Digital archive of complete digital books, fantasy, sci-fi, and literature.
/// Utilizes automated background cookie synchronization via WebViewSessionManager
/// to bypass Cloudflare Turnstile without user interruption.
class VdocPubExtractor implements NovelSource {
  @override
  final String id = 'vdocpub';

  @override
  final String name = 'vdoc.pub';

  @override
  final String baseUrl = 'https://vdoc.pub';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = 'https://vdoc.pub/favicon.ico';

  @override
  final int estimatedNovelCount = 150000;

  late final http.Client _client;

  VdocPubExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
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
    return search('fantasy', page: page);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    return search('novel', page: page);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQuery);
    final targetUrl = page <= 1
        ? '$baseUrl/search/$encoded'
        : '$baseUrl/search/$encoded?page=$page';

    String? htmlBody;
    try {
      final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
      if (response.statusCode == 200) {
        htmlBody = response.body;
      }
    } catch (_) {}

    // Headless WebView fallback if Cloudflare challenge is encountered
    if (htmlBody == null ||
        htmlBody.contains('Just a moment...') ||
        htmlBody.contains('challenge-running') ||
        htmlBody.contains('cf-chl-') ||
        htmlBody.contains('Attention Required')) {
      htmlBody = await WebViewSessionManager.instance.fetchHtmlViaWebView(targetUrl);
    }

    if (htmlBody == null ||
        htmlBody.isEmpty ||
        htmlBody.contains('Just a moment...') ||
        htmlBody.contains('challenge-running') ||
        htmlBody.contains('cf-chl-')) {
      await WebViewSessionManager.instance.clearCookies(baseUrl);
      throw Exception('Cloudflare Turnstile challenge requires in-app WebView session. Open in WebView to solve.');
    }

    final novels = parseHtml(htmlBody);
    if (novels.isEmpty) {
      if (htmlBody.contains('Just a moment...') ||
          htmlBody.contains('challenge-running') ||
          htmlBody.contains('cf-chl-') ||
          htmlBody.contains('Attention Required') ||
          htmlBody.contains('Forbidden') ||
          !WebViewSessionManager.instance.hasClearanceCookie(baseUrl)) {
        await WebViewSessionManager.instance.clearCookies(baseUrl);
        throw Exception('Cloudflare Turnstile challenge requires in-app WebView session. Open in WebView to solve.');
      }
    }

    return novels;
  }

  static String _cleanVdocTitle(String raw) {
    final s = raw
        .replaceAll(RegExp(r'\[(?:PDF|EPUB|MOBI|AZW3)\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\((?:PDF|EPUB|MOBI|AZW3)\)', caseSensitive: false), '')
        .trim();
    return TextCleaner.cleanNovelTitle(s);
  }

  /// Parses vdoc.pub search results HTML
  List<Novel> parseHtml(String html) {
    final doc = html_parser.parse(html);
    final List<Novel> epubResults = [];
    final List<Novel> otherResults = [];
    final seenUrls = <String>{};

    // Broad container selector matching document cards, grid columns, list items, search results
    final items = doc.querySelectorAll(
      '.document-item, .card, .search-card, .search-result, .document, .row .col-md-6, .col-sm-6, .col-12, .col-md-4, .media, article, li'
    );

    for (final item in items) {
      final titleAnchor = item.querySelector('a[href*="/document/"], a[href*="/documents/"]') ??
          item.querySelector('h2 a, h3 a, h4 a, .title a, a');
      if (titleAnchor == null) continue;

      final href = titleAnchor.attributes['href'] ?? '';
      if (href.isEmpty || (!href.contains('/document/') && !href.contains('/documents/'))) continue;

      final fullUrl = href.startsWith('http') ? href : '$baseUrl$href';
      if (seenUrls.contains(fullUrl)) continue;

      var rawTitle = '';
      // Look for title element that isn't "preview document" or "download"
      final possibleTitles = item.querySelectorAll('h1, h2, h3, h4, .title, .document-title, strong, a');
      for (final el in possibleTitles) {
        final t = el.text.trim();
        final lower = t.toLowerCase();
        if (t.isNotEmpty &&
            !lower.contains('preview document') &&
            lower != 'download' &&
            lower != 'read online' &&
            !lower.startsWith('by ') &&
            !lower.contains('views') &&
            !lower.contains('pages') &&
            !lower.contains('mb') &&
            !lower.contains('kb')) {
          rawTitle = t;
          break;
        }
      }
      if (rawTitle.isEmpty) {
        final aTitle = titleAnchor.attributes['title']?.trim();
        if (aTitle != null && aTitle.isNotEmpty && !aTitle.toLowerCase().contains('preview document')) {
          rawTitle = aTitle;
        }
      }
      if (rawTitle.isEmpty || rawTitle.toLowerCase().contains('preview document') || rawTitle.toLowerCase() == 'download') {
        final path = Uri.parse(fullUrl).path;
        final slug = path.split('/').where((s) => s.isNotEmpty).last;
        final cleanSlug = slug
            .replaceAll(RegExp(r'-[a-z0-9]{8,25}$', caseSensitive: false), '')
            .replaceAll(RegExp(r'-(?:pdf|epub|mobi)$', caseSensitive: false), '');
        rawTitle = cleanSlug.split('-').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
      }
      if (rawTitle.isEmpty) continue;
      final title = _cleanVdocTitle(rawTitle);

      final authorEl = item.querySelector('.author, .text-muted, [itemprop="author"], p, .meta');
      String author = 'Unknown Author';
      if (authorEl != null) {
        final text = authorEl.text.trim();
        final byMatch = RegExp(r'\bby\s+(.*?)$', caseSensitive: false).firstMatch(text);
        if (byMatch != null) {
          author = byMatch.group(1)!.trim();
        } else if (text.isNotEmpty && !text.contains('pages') && !text.contains('MB') && !text.contains('views')) {
          author = text;
        }
      }

      final img = item.querySelector('img');
      String coverUrl = '';
      if (img != null) {
        var src = img.attributes['data-cfsrc'] ??
            img.attributes['data-src'] ??
            img.attributes['data-original'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'] ??
            '';
        if (src.contains('data:image') || src.contains('placeholder') || src.contains('blank.gif')) {
          src = img.attributes['data-cfsrc'] ?? img.attributes['data-src'] ?? img.attributes['data-original'] ?? '';
        }
        if (src.isNotEmpty && !src.contains('data:image')) {
          coverUrl = src.startsWith('http') ? src : (src.startsWith('//') ? 'https:$src' : '$baseUrl$src');
        }
      }

      final segments = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      final docId = segments.isNotEmpty ? segments.last : '${fullUrl.hashCode.abs()}';

      // Fallback cover if thumbnail is empty
      if (coverUrl.isEmpty) {
        coverUrl = 'https://img.vdoc.pub/img/detail/$docId.jpg';
      }

      // Format detection
      var format = 'epub';
      final checkStr = '$fullUrl $rawTitle'.toLowerCase();
      if (checkStr.contains('-pdf-') || checkStr.contains('.pdf') || checkStr.contains('[pdf]')) {
        format = 'pdf';
      } else if (checkStr.contains('-mobi-') || checkStr.contains('.mobi') || checkStr.contains('[mobi]')) {
        format = 'mobi';
      } else if (checkStr.contains('-epub-') || checkStr.contains('.epub') || checkStr.contains('[epub]')) {
        format = 'epub';
      }

      final downloadUrl = '$baseUrl/download/$docId';

      final itemNovel = Novel(
        id: '${id}_$docId',
        sourceId: id,
        title: title,
        author: author,
        description: 'Format: ${format.toUpperCase()}',
        coverUrl: coverUrl,
        sourceUrl: fullUrl,
        status: 'COMPLETED',
        isFullBook: true,
        bookFormat: format,
        bookDownloadUrl: downloadUrl,
      );

      seenUrls.add(fullUrl);
      if (format == 'epub') {
        epubResults.add(itemNovel);
      } else {
        otherResults.add(itemNovel);
      }
    }

    // Fallback: scan any standalone document links on page
    if (epubResults.isEmpty && otherResults.isEmpty) {
      final standaloneAnchors = doc.querySelectorAll('a[href*="/document/"], a[href*="/documents/"]');
      for (final a in standaloneAnchors) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final fullUrl = href.startsWith('http') ? href : '$baseUrl$href';
        if (seenUrls.contains(fullUrl)) continue;

        var rawTitle = a.text.trim();
        if (rawTitle.isEmpty || rawTitle.toLowerCase() == 'download' || rawTitle.toLowerCase().contains('preview document')) {
          rawTitle = a.attributes['title'] ?? '';
        }
        if (rawTitle.isEmpty || rawTitle.toLowerCase() == 'download' || rawTitle.toLowerCase().contains('preview document')) {
          final path = Uri.parse(fullUrl).path;
          final slug = path.split('/').where((s) => s.isNotEmpty).last;
          final cleanSlug = slug
              .replaceAll(RegExp(r'-[a-z0-9]{8,25}$', caseSensitive: false), '')
              .replaceAll(RegExp(r'-(?:pdf|epub|mobi)$', caseSensitive: false), '');
          rawTitle = cleanSlug.split('-').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
        }
        if (rawTitle.isEmpty) continue;
        final title = _cleanVdocTitle(rawTitle);

        final segments = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).toList();
        final docId = segments.isNotEmpty ? segments.last : '${fullUrl.hashCode.abs()}';

        var format = 'epub';
        final checkStr = '$fullUrl $rawTitle'.toLowerCase();
        if (checkStr.contains('-pdf-') || checkStr.contains('.pdf') || checkStr.contains('[pdf]')) {
          format = 'pdf';
        }

        final itemNovel = Novel(
          id: '${id}_$docId',
          sourceId: id,
          title: title,
          author: 'Unknown Author',
          description: 'Format: ${format.toUpperCase()}',
          coverUrl: 'https://img.vdoc.pub/img/detail/$docId.jpg',
          sourceUrl: fullUrl,
          status: 'COMPLETED',
          isFullBook: true,
          bookFormat: format,
          bookDownloadUrl: '$baseUrl/download/$docId',
        );

        seenUrls.add(fullUrl);
        if (format == 'epub') {
          epubResults.add(itemNovel);
        } else {
          otherResults.add(itemNovel);
        }
      }
    }

    final all = [...epubResults, ...otherResults];
    return all;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    String? htmlBody;
    try {
      final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (response.statusCode == 200) {
        htmlBody = response.body;
      }
    } catch (_) {}

    if (htmlBody == null ||
        htmlBody.contains('Just a moment...') ||
        htmlBody.contains('challenge-running') ||
        htmlBody.contains('cf-chl-') ||
        htmlBody.contains('Attention Required')) {
      htmlBody = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
    }

    if (htmlBody == null ||
        htmlBody.contains('Just a moment...') ||
        htmlBody.contains('challenge-running') ||
        htmlBody.contains('cf-chl-')) {
      throw Exception('Cloudflare Turnstile challenge requires in-app WebView session. Open in WebView to solve.');
    }

    final doc = html_parser.parse(htmlBody);

    // 1. Robust Title Extraction:
    // vdoc.pub uses <meta name="og:title"> and <h3 class="cs_title"> instead of <h1>
    String rawTitle = '';
    final metaTitle = doc.querySelector('meta[name="og:title"], meta[property="og:title"], meta[name="twitter:title"]')?.attributes['content']?.trim();
    if (metaTitle != null && metaTitle.isNotEmpty) {
      rawTitle = metaTitle;
    }
    if (rawTitle.isEmpty) {
      final h = doc.querySelector('h3.cs_title, h1, h2, h3, .document-title, .book-title')?.text.trim();
      if (h != null && h.isNotEmpty) {
        rawTitle = h;
      }
    }
    if (rawTitle.isEmpty) {
      final pageTitle = doc.querySelector('title')?.text.trim();
      if (pageTitle != null && pageTitle.isNotEmpty) {
        rawTitle = pageTitle
            .replaceAll(RegExp(r'\s*-\s*vdoc\.pub.*$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*\[(?:PDF|EPUB|MOBI|AZW3)\]', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*\[[a-z0-9]{8,25}\]', caseSensitive: false), '')
            .trim();
      }
    }
    final segments = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final docId = segments.isNotEmpty ? segments.last : '${novelUrl.hashCode.abs()}';

    if (rawTitle.isEmpty || rawTitle.toLowerCase() == 'unknown book' || rawTitle.toLowerCase() == 'untitled') {
      final cleanSlug = docId
          .replaceAll(RegExp(r'-[a-z0-9]{8,25}$', caseSensitive: false), '')
          .replaceAll(RegExp(r'-(?:pdf|epub|mobi)$', caseSensitive: false), '');
      rawTitle = cleanSlug.split('-').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
    }
    final title = _cleanVdocTitle(rawTitle.isNotEmpty ? rawTitle : 'Unknown Book');

    // 2. Author Extraction:
    // vdoc.pub displays author in list items prefixed with "Authors:" (e.g. <li>Authors: Hudson, Sindy</li>)
    String author = 'Unknown Author';
    for (final item in doc.querySelectorAll('li, .list-inline-item, tr, p, div')) {
      final text = item.text.trim();
      final m = RegExp(r'Authors?:\s*(.+)', caseSensitive: false).firstMatch(text);
      if (m != null) {
        final a = m.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (a.isNotEmpty && !a.toLowerCase().contains('pages') && !a.toLowerCase().contains('views')) {
          author = a;
          break;
        }
      }
    }
    if (author == 'Unknown Author') {
      final authorMeta = doc.querySelector('meta[name="author"]')?.attributes['content']?.trim();
      if (authorMeta != null && authorMeta.isNotEmpty) {
        author = authorMeta;
      }
    }
    if (author == 'Unknown Author') {
      final authorEl = doc.querySelector('.author, [itemprop="author"]')?.text.trim();
      if (authorEl != null && authorEl.isNotEmpty) {
        author = authorEl;
      }
    }

    var description = doc.querySelector('.description, .synopsis, #description, .card-body p, .content, [itemprop="description"]')?.text.trim() ?? '';
    if (description.isEmpty) {
      final metaDesc = doc.querySelector('meta[name="description"], meta[property="og:description"]')?.attributes['content'];
      if (metaDesc != null && metaDesc.isNotEmpty) {
        description = metaDesc;
      }
    }

    // 3. Cover Image:
    final ogImg = doc.querySelector('meta[name="og:image"], meta[property="og:image"], meta[name="twitter:image"]');
    var coverUrl = ogImg?.attributes['content']?.trim() ?? '';

    if (coverUrl.isEmpty) {
      final img = doc.querySelector('img[src*="img/detail/"], img[src*="img.vdoc.pub"], .cover-image img, .document-cover img, img.img-fluid, .cover img, img');
      if (img != null) {
        var src = img.attributes['data-cfsrc'] ??
            img.attributes['data-src'] ??
            img.attributes['data-original'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'] ??
            '';
        if (src.contains('data:image') || src.contains('placeholder') || src.contains('blank.gif')) {
          src = img.attributes['data-cfsrc'] ?? img.attributes['data-src'] ?? img.attributes['data-original'] ?? '';
        }
        if (src.isNotEmpty && !src.contains('data:image')) {
          coverUrl = src.startsWith('http') ? src : (src.startsWith('//') ? 'https:$src' : '$baseUrl$src');
        }
      }
    }

    if (coverUrl.isEmpty) {
      coverUrl = 'https://img.vdoc.pub/img/detail/$docId.jpg';
    }

    var detectedFormat = 'epub';
    final checkStr = '$novelUrl $rawTitle $htmlBody'.toLowerCase();
    if (checkStr.contains('-pdf-') || checkStr.contains('.pdf') || checkStr.contains('[pdf]')) {
      detectedFormat = 'pdf';
    } else if (checkStr.contains('-mobi-') || checkStr.contains('.mobi') || checkStr.contains('[mobi]')) {
      detectedFormat = 'mobi';
    }

    // Direct download link resolution from page
    final dlAnchor = doc.querySelector('a[href*="/download/"], a[href*="/dl/"], a.btn-download');
    String? downloadUrl = dlAnchor?.attributes['href'];
    if (downloadUrl != null && !downloadUrl.startsWith('http')) {
      downloadUrl = '$baseUrl$downloadUrl';
    }

    final effectiveDownloadUrl = downloadUrl ?? '$baseUrl/download/$docId';

    return Novel(
      id: '${id}_$docId',
      sourceId: id,
      title: title,
      author: author,
      description: description.isNotEmpty ? description : 'Format: ${detectedFormat.toUpperCase()}',
      coverUrl: coverUrl,
      sourceUrl: novelUrl,
      status: 'COMPLETED',
      isFullBook: true,
      bookFormat: detectedFormat,
      bookDownloadUrl: effectiveDownloadUrl,
    );
  }

  /// Resolves the final direct binary download URL from a vdoc.pub download page
  Future<String?> resolveDirectDownloadUrl(String downloadPageUrl) async {
    try {
      final res = await _client
          .get(Uri.parse(downloadPageUrl), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final cType = res.headers['content-type'] ?? '';
        if (cType.contains('epub') || cType.contains('octet-stream') || cType.contains('zip')) {
          return downloadPageUrl;
        }

        final doc = html_parser.parse(res.body);

        // 1. Direct file anchor
        final directAnchor = doc.querySelector(
          'a[href*="/dl/"], a[href*="/file/"], a[href*=".epub"], a[href*=".pdf"], a[download], a.btn-download, a[href*="attachment"]'
        );
        if (directAnchor != null) {
          final href = directAnchor.attributes['href'];
          if (href != null && href.isNotEmpty) {
            return href.startsWith('http') ? href : '$baseUrl$href';
          }
        }

        // 2. Form submission action
        final form = doc.querySelector('form[action*="download"], form');
        if (form != null) {
          final action = form.attributes['action'];
          if (action != null && action.isNotEmpty) {
            return action.startsWith('http') ? action : '$baseUrl$action';
          }
        }

        // 3. JavaScript redirect
        final jsMatch = RegExp(r'''window\.location(?:\.href)?\s*=\s*['"]([^'"]+)['"]''').firstMatch(res.body) ??
            RegExp(r'''location\.replace\(['"]([^'"]+)['"]\)''').firstMatch(res.body) ??
            RegExp(r'''href\s*=\s*['"]([^'"]+\.(?:epub|pdf)[^'"]*)['"]''').firstMatch(res.body);
        if (jsMatch != null) {
          final target = jsMatch.group(1)!;
          return target.startsWith('http') ? target : '$baseUrl$target';
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    // Complete books do not have individual chapter URLs before download.
    // Whole package is downloaded once via downloadEntireBook() and unpacked locally.
    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    throw UnsupportedError(
      'vdoc.pub books are packaged as complete digital editions. '
      'Use downloadEntireBook() to read offline with chapter navigation.',
    );
  }
}
