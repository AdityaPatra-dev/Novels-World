import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/utils/text_cleaner.dart';
import '../novel_source.dart';

/// Bespoke Extractor for WoopRead (https://woopread.com).
/// High quality translation collective & web novel portal hosting popular
/// Korean fantasy, Otome, and progression webnovels. Modern Next.js stack.
class WoopReadExtractor implements NovelSource {
  @override
  final String id = 'woopread';

  @override
  final String name = 'Woopread';

  @override
  final String baseUrl = 'https://woopread.com';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 15000;

  late final http.Client _client;

  WoopReadExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': '$baseUrl/',
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

  String _cleanImageUrl(String imgUrl) {
    if (imgUrl.contains('_next/image') && imgUrl.contains('url=')) {
      try {
        final uri = Uri.parse(imgUrl);
        final innerUrl = uri.queryParameters['url'];
        if (innerUrl != null && innerUrl.isNotEmpty) {
          return innerUrl;
        }
      } catch (_) {}
    }
    return _cleanUrl(imgUrl);
  }

  Future<String> _fetchHtml(String url) async {
    String htmlBody = '';
    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode == 200 &&
          !response.body.contains('Just a moment...') &&
          !response.body.contains('challenge-running') &&
          !response.body.contains('cf-chl-')) {
        htmlBody = response.body;
      }
    } catch (_) {}

    if (htmlBody.isEmpty) {
      final wvHtml =
          await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null && wvHtml.isNotEmpty) {
        htmlBody = wvHtml;
      }
    }

    if (htmlBody.isEmpty ||
        htmlBody.contains('Just a moment...') ||
        htmlBody.contains('challenge-running') ||
        htmlBody.contains('cf-chl-')) {
      throw const HttpException(
        'Cloudflare challenge encountered on Woopread. Open in WebView to solve.',
      );
    }

    return htmlBody;
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = Uri.encodeComponent(query);
    final targetUrl = '$baseUrl/browse?q=$cleanQuery&page=$page';
    final html = await _fetchHtml(targetUrl);
    return parseNovelList(html);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = page > 1 ? '$baseUrl/browse?page=$page' : '$baseUrl/browse';
    final html = await _fetchHtml(targetUrl);
    return parseNovelList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final targetUrl = page > 1 ? '$baseUrl/browse?page=$page' : '$baseUrl/browse';
    final html = await _fetchHtml(targetUrl);
    return parseNovelList(html);
  }

  List<Novel> parseNovelList(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final novels = <Novel>[];
    final seenUrls = <String>{};

    final cards = document.querySelectorAll('a[href^="/series/"]');
    for (final card in cards) {
      final href = card.attributes['href'];
      if (href == null || href.isEmpty || href == '/series' || href == '/series/') {
        continue;
      }

      // Avoid matching chapter links inside cards
      final segments = href.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length != 2) {
        // We only want /series/<slug>
        continue;
      }

      final novelUrl = _cleanUrl(href);
      if (seenUrls.contains(novelUrl)) continue;
      seenUrls.add(novelUrl);

      final imgEl = card.querySelector('img');
      var rawCover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
      final coverUrl = _cleanImageUrl(rawCover);

      // Best title from img alt, fallback to card text
      var title = imgEl?.attributes['alt']?.trim() ?? '';
      if (title.isEmpty) {
        final heading = card.querySelector('h2, h3, h4, .title');
        title = heading?.text.trim() ?? card.text.trim();
      }

      if (title.isNotEmpty) {
        novels.add(
          Novel(
            id: novelUrl,
            sourceId: id,
            title: title,
            sourceUrl: novelUrl,
            coverUrl: coverUrl,
          ),
        );
      }
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    return parseNovelDetails(novelUrl, html);
  }

  Novel parseNovelDetails(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    // Title
    final h1 = document.querySelector('h1');
    final metaTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'];
    final title = h1?.text.trim() ?? metaTitle?.trim() ?? 'Unknown Novel';

    // Cover
    final metaCover = document.querySelector('meta[property="og:image"]')?.attributes['content'];
    final coverEl = document.querySelector('img.object-cover, img[alt="$title"]');
    final rawCover = metaCover ?? coverEl?.attributes['src'] ?? '';
    final coverUrl = _cleanImageUrl(rawCover);

    // Description
    final metaDesc = document.querySelector('meta[name="description"]')?.attributes['content'] ??
        document.querySelector('meta[property="og:description"]')?.attributes['content'];
    final descEl = document.querySelector('p.text-text, div.description, .synopsis');
    var description = descEl?.text.trim() ?? metaDesc?.trim() ?? '';
    if (description.startsWith('pIt ')) {
      description = 'It ${description.substring(4)}';
    }

    // Author
    var author = 'Unknown Author';
    final authorLink = document.querySelector('a[href*="/author/"]');
    if (authorLink != null && authorLink.text.trim().isNotEmpty) {
      author = authorLink.text.trim();
    }

    // Genres
    final genres = <String>[];
    for (final g in document.querySelectorAll('a[href*="/genre/"], a[href*="/tag/"]')) {
      final gText = g.text.trim();
      if (gText.isNotEmpty && !genres.contains(gText)) {
        genres.add(gText);
      }
    }

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      sourceUrl: novelUrl,
      coverUrl: coverUrl,
      author: author,
      description: description,
      genres: genres,
      status: 'Ongoing',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final html = await _fetchHtml(novelUrl);
    final chapters = parseChapterList(novelUrl, html);
    if (chapters.isNotEmpty) onBatchLoaded?.call(chapters);
    return chapters;
  }

  List<Chapter> parseChapterList(String novelUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final chapters = <Chapter>[];
    final seenUrls = <String>{};

    final cleanNovelUrl = _cleanUrl(novelUrl);
    final novelPath = Uri.parse(cleanNovelUrl).path;

    final links = document.querySelectorAll('a[href*="$novelPath/"]');
    for (final a in links) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final chUrl = _cleanUrl(href);
      if (chUrl == cleanNovelUrl || seenUrls.contains(chUrl)) continue;
      seenUrls.add(chUrl);

      // Extract title e.g. "Chapter 12"
      var title = a.text.trim();
      // Remove timestamps like "almost 2 years ago" or "2 months ago"
      final timeRegex = RegExp(r'(\d+\s+(?:days?|hours?|months?|years?|minutes?)\s+ago)', caseSensitive: false);
      title = title.replaceAll(timeRegex, '').trim();

      if (title.isEmpty || title.toLowerCase() == 'read now') {
        final slug = chUrl.split('/').where((s) => s.isNotEmpty).last;
        title = slug.replaceAll('-', ' ').replaceAllMapped(RegExp(r'(\d+)'), (m) => ' ${m[1]}').trim();
        if (title.isNotEmpty) {
          title = title[0].toUpperCase() + title.substring(1);
        }
      }

      final chNumMatch = RegExp(r'chapter\s+(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(title);
      final chNumber = chNumMatch != null ? double.tryParse(chNumMatch.group(1)!) : null;

      chapters.add(
        Chapter(
          id: chUrl,
          novelId: novelUrl,
          title: title,
          chapterNumber: chNumber,
          url: chUrl,
        ),
      );
    }

    // Chapters are usually in descending order on the webpage; sort ascending
    final chRegex = RegExp(r'chapter\s+(\d+(?:\.\d+)?)', caseSensitive: false);
    bool allNumbered = chapters.isNotEmpty;
    for (final c in chapters) {
      if (!chRegex.hasMatch(c.title)) {
        allNumbered = false;
        break;
      }
    }

    if (allNumbered) {
      chapters.sort((a, b) {
        final numA = double.tryParse(chRegex.firstMatch(a.title)?.group(1) ?? '0') ?? 0;
        final numB = double.tryParse(chRegex.firstMatch(b.title)?.group(1) ?? '0') ?? 0;
        return numA.compareTo(numB);
      });
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final html = await _fetchHtml(chapterUrl);
    return parseChapterContent(chapterUrl, html);
  }

  ChapterContent parseChapterContent(String chapterUrl, String htmlContent) {
    final document = html_parser.parse(htmlContent);

    // Title
    final h1 = document.querySelector('h1, h2');
    var chapterTitle = h1?.text.trim() ?? 'Chapter';

    // Content container
    final container = document.querySelector('div.text-text') ??
        document.querySelector('div.reading-content') ??
        document.querySelector('article') ??
        document.body;

    if (container == null) {
      return ChapterContent(
        chapterId: chapterUrl,
        novelId: chapterUrl,
        title: chapterTitle,
        rawText: '',
        paragraphs: const [],
      );
    }

    // Clean scripts, ads, headers
    for (final el in container.querySelectorAll('script, style, iframe, ins, .adsbygoogle, header, nav, button')) {
      el.remove();
    }

    final pElements = container.querySelectorAll('p');
    final rawParagraphs = <String>[];

    if (pElements.isNotEmpty) {
      for (final p in pElements) {
        if (p.text.trim().isNotEmpty) {
          rawParagraphs.add(p.text.trim());
        }
      }
    } else {
      final lines = container.text.split('\n');
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          rawParagraphs.add(line.trim());
        }
      }
    }

    final cleanedParagraphs = TextCleaner.cleanParagraphs(rawParagraphs);

    return ChapterContent(
      chapterId: chapterUrl,
      novelId: chapterUrl,
      title: chapterTitle,
      rawText: cleanedParagraphs.join('\n\n'),
      paragraphs: cleanedParagraphs,
    );
  }
}
