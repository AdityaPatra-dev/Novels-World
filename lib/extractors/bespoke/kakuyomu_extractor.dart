import 'dart:convert';
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

/// Bespoke Extractor for Kakuyomu (https://kakuyomu.jp).
/// Kadokawa's official Japanese webfiction platform hosting over 600,000+
/// serialized works, light novels, and web fictions.
class KakuyomuExtractor implements NovelSource {
  @override
  final String id = 'kakuyomu';

  @override
  final String name = 'Kakuyomu';

  @override
  final String baseUrl = 'https://kakuyomu.jp';

  @override
  final String lang = 'ja';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 600000;

  late final http.Client _client;

  KakuyomuExtractor({http.Client? client}) {
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
      'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
      'Referer': baseUrl,
    };
    final cookie = WebViewSessionManager.instance.getCookieHeader(baseUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final url = page == 1
        ? '$baseUrl/rankings/all/weekly?work_variation=long'
        : '$baseUrl/rankings/all/weekly?work_variation=long&page=$page';
    return _fetchAndParseWorks(url);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final url = page == 1
        ? '$baseUrl/search?order=published_at'
        : '$baseUrl/search?order=published_at&page=$page';
    return _fetchAndParseWorks(url);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQ = query.trim();
    if (cleanQ.isEmpty) return [];

    final encoded = Uri.encodeComponent(cleanQ);
    final url = page == 1
        ? '$baseUrl/search?q=$encoded'
        : '$baseUrl/search?q=$encoded&page=$page';
    return _fetchAndParseWorks(url);
  }

  Future<List<Novel>> _fetchAndParseWorks(String url) async {
    String htmlBody = '';
    try {
      final resp = await _client.get(Uri.parse(url), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        htmlBody = resp.body;
      }
    } catch (_) {}

    if (htmlBody.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null) htmlBody = wvHtml;
    }

    if (htmlBody.isEmpty) return [];

    final doc = html_parser.parse(htmlBody);

    // 1. First attempt: Parse from Next.js __NEXT_DATA__ JSON state
    final nextDataEl = doc.querySelector('#__NEXT_DATA__');
    if (nextDataEl != null && nextDataEl.text.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(nextDataEl.text);
        final apollo = jsonMap['props']?['pageProps']?['__APOLLO_STATE__'];
        if (apollo is Map) {
          final list = _parseFromApolloState(apollo);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }

    // 2. Fallback: Parse directly from HTML DOM
    return _parseFromDom(doc);
  }

  List<Novel> _parseFromApolloState(Map apollo) {
    final List<Novel> novels = [];
    final seenIds = <String>{};

    for (final entry in apollo.entries) {
      final key = entry.key.toString();
      if (!key.startsWith('Work:')) continue;

      final val = entry.value;
      if (val is! Map) continue;

      final workId = val['id']?.toString() ?? key.replaceFirst('Work:', '');
      if (workId.isEmpty || seenIds.contains(workId)) continue;

      final title = val['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;

      seenIds.add(workId);

      // Author extraction
      String author = 'Unknown Author';
      final authorRef = val['author']?['__ref']?.toString();
      if (authorRef != null && apollo.containsKey(authorRef)) {
        final authorObj = apollo[authorRef];
        if (authorObj is Map) {
          author = authorObj['activityName']?.toString().trim() ??
              authorObj['name']?.toString().trim() ??
              'Unknown Author';
        }
      }

      // Cover image
      String coverUrl = val['adminSquareImageUrl']?.toString() ?? '';
      if (coverUrl.isEmpty) {
        coverUrl = 'https://cdn-static.kakuyomu.jp/works/$workId/ogimage.png';
      }

      final novelUrl = '$baseUrl/works/$workId';
      final genre = val['genre']?.toString();
      final genres = genre != null ? [genre] : <String>[];

      novels.add(
        Novel(
          id: '${id}_$workId',
          sourceId: id,
          title: title,
          author: author,
          coverUrl: coverUrl,
          genres: genres,
          sourceUrl: novelUrl,
        ),
      );
    }

    return novels;
  }

  List<Novel> _parseFromDom(dynamic doc) {
    final List<Novel> novels = [];
    final seenUrls = <String>{};

    final links = doc.querySelectorAll('a[href*="/works/"]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty || href.contains('/episodes') || href.contains('/reviews')) {
        continue;
      }

      final fullUrl = Uri.parse(baseUrl).resolve(href).toString();
      if (seenUrls.contains(fullUrl)) continue;

      final title = a.text.trim();
      if (title.isEmpty || title.length < 2 || !TextCleaner.isValidNovelTitle(title, fullUrl)) {
        continue;
      }

      seenUrls.add(fullUrl);

      final segments = Uri.parse(fullUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      final workId = segments.isNotEmpty ? segments.last : fullUrl.hashCode.toString();

      final parent = a.parent?.parent;
      final img = parent?.querySelector('img');
      String coverUrl = img?.attributes['src'] ?? img?.attributes['data-src'] ?? '';
      if (coverUrl.isEmpty) {
        coverUrl = 'https://cdn-static.kakuyomu.jp/works/$workId/ogimage.png';
      }

      final authorEl = parent?.querySelector('a[href*="/users/"]');
      final author = authorEl?.text.trim() ?? 'Unknown Author';

      novels.add(
        Novel(
          id: '${id}_$workId',
          sourceId: id,
          title: title,
          author: author,
          coverUrl: coverUrl,
          sourceUrl: fullUrl,
        ),
      );
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    if (TextCleaner.isGenreOrCategoryUrl(novelUrl)) {
      throw HttpException('Invalid novel URL: $novelUrl is a category link.');
    }

    String body = '';
    try {
      final resp = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        body = resp.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load novel details from Kakuyomu ($novelUrl)');
    }

    final doc = html_parser.parse(body);

    final segments = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final workId = segments.isNotEmpty ? segments.last : novelUrl.hashCode.toString();

    // Check __NEXT_DATA__ Apollo state first
    final nextDataEl = doc.querySelector('#__NEXT_DATA__');
    if (nextDataEl != null && nextDataEl.text.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(nextDataEl.text);
        final apollo = jsonMap['props']?['pageProps']?['__APOLLO_STATE__'];
        if (apollo is Map) {
          final workKey = 'Work:$workId';
          if (apollo.containsKey(workKey)) {
            final w = apollo[workKey] as Map;
            final title = w['title']?.toString().trim() ?? 'Untitled';

            String author = 'Unknown Author';
            final authorRef = w['author']?['__ref']?.toString();
            if (authorRef != null && apollo.containsKey(authorRef)) {
              final a = apollo[authorRef] as Map;
              author = a['activityName']?.toString().trim() ??
                  a['name']?.toString().trim() ??
                  'Unknown Author';
            }

            final description = w['catchphrase']?.toString().trim() ?? '';
            final genre = w['genre']?.toString();
            final genres = genre != null ? [genre] : <String>[];
            final coverUrl = w['adminSquareImageUrl']?.toString() ??
                'https://cdn-static.kakuyomu.jp/works/$workId/ogimage.png';

            return Novel(
              id: '${id}_$workId',
              sourceId: id,
              title: title,
              author: author,
              description: description,
              coverUrl: coverUrl,
              genres: genres,
              status: w['serialStatus'] == 'COMPLETED' ? 'COMPLETED' : 'ONGOING',
              sourceUrl: novelUrl,
            );
          }
        }
      } catch (_) {}
    }

    // HTML fallback
    final title = doc.querySelector('h1, meta[property="og:title"]')?.attributes['content'] ??
        doc.querySelector('h1')?.text.trim() ??
        'Untitled';

    final author = doc.querySelector('a[href*="/users/"]')?.text.trim() ?? 'Unknown Author';
    final description = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ??
        doc.querySelector('#work-introduction, .description')?.text.trim() ??
        '';

    final ogImage = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
        'https://cdn-static.kakuyomu.jp/works/$workId/ogimage.png';

    return Novel(
      id: '${id}_$workId',
      sourceId: id,
      title: title,
      author: author,
      description: description,
      coverUrl: ogImage,
      status: 'ONGOING',
      sourceUrl: novelUrl,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    String body = '';
    try {
      final resp = await _client.get(Uri.parse(novelUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        body = resp.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(novelUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) return [];

    final segments = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final workId = segments.isNotEmpty ? segments.last : novelUrl.hashCode.toString();
    final novelId = '${id}_$workId';

    final doc = html_parser.parse(body);
    final List<Chapter> chapters = [];

    // 1. Parse complete episode index from Next.js Apollo state
    final nextDataEl = doc.querySelector('#__NEXT_DATA__');
    if (nextDataEl != null && nextDataEl.text.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(nextDataEl.text);
        final apollo = jsonMap['props']?['pageProps']?['__APOLLO_STATE__'];
        if (apollo is Map) {
          final List<Map> epEntries = [];
          for (final entry in apollo.entries) {
            final key = entry.key.toString();
            if (key.startsWith('Episode:') && entry.value is Map) {
              epEntries.add(entry.value as Map);
            }
          }

          // Sort by publishedAt / index order if available
          epEntries.sort((a, b) {
            final pubA = a['publishedAt']?.toString() ?? '';
            final pubB = b['publishedAt']?.toString() ?? '';
            return pubA.compareTo(pubB);
          });

          for (final ep in epEntries) {
            final epId = ep['id']?.toString() ?? '';
            if (epId.isEmpty) continue;

            final epTitle = ep['title']?.toString().trim() ?? 'Episode';
            final epUrl = '$baseUrl/works/$workId/episodes/$epId';
            final chId = '${id}_${workId}_$epId';

            chapters.add(
              Chapter(
                id: chId,
                novelId: novelId,
                title: epTitle,
                url: epUrl,
                chapterNumber: (chapters.length + 1).toDouble(),
                releaseDate: ep['publishedAt']?.toString(),
              ),
            );
          }

          if (chapters.isNotEmpty) return chapters;
        }
      } catch (_) {}
    }

    // 2. Fallback: Parse from HTML anchor elements
    final epLinks = doc.querySelectorAll('a[href*="/episodes/"]');
    final seenUrls = <String>{};

    for (final a in epLinks) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final epUrl = Uri.parse(baseUrl).resolve(href).toString();
      if (seenUrls.contains(epUrl)) continue;

      seenUrls.add(epUrl);
      final epSegments = Uri.parse(epUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      final epId = epSegments.isNotEmpty ? epSegments.last : epUrl.hashCode.toString();

      final title = a.text.trim();
      final chId = '${id}_${workId}_$epId';

      chapters.add(
        Chapter(
          id: chId,
          novelId: novelId,
          title: title.isEmpty ? 'Episode ${chapters.length + 1}' : title,
          url: epUrl,
          chapterNumber: (chapters.length + 1).toDouble(),
        ),
      );
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    String body = '';
    try {
      final resp = await _client.get(Uri.parse(chapterUrl), headers: _headers);
      if (resp.statusCode == 200 && !resp.body.contains('Just a moment...')) {
        body = resp.body;
      }
    } catch (_) {}

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(chapterUrl);
      if (wvHtml != null) body = wvHtml;
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load episode content from Kakuyomu ($chapterUrl)');
    }

    final doc = html_parser.parse(body);
    final paragraphs = <String>[];

    final pElements = doc.querySelectorAll('.widget-episodeBody p, .js-vertical-composition-item p, .widget-episodeBody');
    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      paragraphs.add(text);
    }

    final segments = Uri.parse(chapterUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final epId = segments.isNotEmpty ? segments.last : chapterUrl.hashCode.toString();
    final workId = segments.length > 2 ? segments[1] : 'work';

    final chapterId = '${id}_${workId}_$epId';
    final novelId = '${id}_$workId';
    final rawText = paragraphs.join('\n\n');
    final title = doc.querySelector('.widget-episodeTitle, h1, title')?.text.trim() ?? 'Episode';

    return ChapterContent(
      chapterId: chapterId,
      novelId: novelId,
      title: title,
      rawText: rawText,
      paragraphs: paragraphs,
    );
  }
}

