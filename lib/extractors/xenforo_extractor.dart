import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/services/webview_session_manager.dart';
import '../core/utils/http_client_factory.dart';
import '../core/utils/text_cleaner.dart';
import 'novel_source.dart';

/// Shared XenForo + Threadmarks extractor supporting SpaceBattles and Sufficient Velocity.
class XenForoExtractor implements NovelSource {
  @override
  final String id;

  @override
  final String name;

  @override
  final String baseUrl;

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final String lang;

  @override
  final int estimatedNovelCount;

  final String forumPath;
  final http.Client _client;

  XenForoExtractor({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.forumPath,
    this.lang = 'en',
    this.estimatedNovelCount = 15000,
    http.Client? client,
  }) : _client = client ?? createPlatformHttpClient();

  Map<String, String> get _headers => {
        'User-Agent': WebViewSessionManager.defaultUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': '$baseUrl/',
      };

  Future<String> _fetchHtml(String url) async {
    String body = '';
    try {
      final resp = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && !_isChallenge(resp.body)) {
        body = resp.body;
      }
    } catch (_) {}

    // Fallback to Cloudflare Edge proxy if direct request hit Cloudflare challenge
    if (body.isEmpty && webProxyEndpoint.isNotEmpty) {
      try {
        final proxied = '$webProxyEndpoint?url=${Uri.encodeComponent(url)}';
        final resp = await _client.get(Uri.parse(proxied), headers: _headers).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200 && !_isChallenge(resp.body)) {
          body = resp.body;
        }
      } catch (_) {}
    }

    if (body.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null && !_isChallenge(wvHtml)) {
        body = wvHtml;
      }
    }

    if (body.isEmpty) {
      throw HttpException('Failed to load $url from $name');
    }
    return body;
  }

  bool _isChallenge(String html) {
    final low = html.toLowerCase();
    return low.contains('just a moment...') ||
        low.contains('challenge-platform') ||
        low.contains('cf-chl-');
  }

  String _cleanUrl(String url, {bool keepFragment = false}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    try {
      final resolved = Uri.parse(baseUrl).resolve(trimmed);
      if (keepFragment) return resolved.toString();
      return resolved.removeFragment().toString();
    } catch (_) {
      return trimmed;
    }
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final pageSuffix = page > 1 ? 'page-$page' : '';
    final url = '$baseUrl$forumPath$pageSuffix?order=reply_count&direction=desc';
    final html = await _fetchHtml(url);
    return _parseThreadList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final pageSuffix = page > 1 ? 'page-$page' : '';
    final url = '$baseUrl$forumPath$pageSuffix?order=last_post_date&direction=desc';
    final html = await _fetchHtml(url);
    return _parseThreadList(html);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQ = Uri.encodeComponent(query.trim());
    final url = '$baseUrl/search/search?keywords=$cleanQ&c[title_only]=1';
    try {
      final html = await _fetchHtml(url);
      final results = _parseThreadList(html);
      if (results.isNotEmpty) return results;
    } catch (_) {}

    // Fallback: filter popular threads locally if search endpoint requires form token
    final pop = await getPopular(page: page);
    final qLower = query.toLowerCase();
    return pop
        .where((n) => n.title.toLowerCase().contains(qLower) || n.author.toLowerCase().contains(qLower))
        .toList();
  }

  List<Novel> _parseThreadList(String html) {
    final doc = html_parser.parse(html);
    final items = doc.querySelectorAll('.structItem--thread, li.block-row');
    final novels = <Novel>[];
    final seen = <String>{};

    for (final item in items) {
      // Skip sticky admin/rules threads
      if (item.querySelector('.structItem-status--sticky') != null) continue;

      final titleAnchor = item.querySelector('.structItem-title a[href*="/threads/"], .contentRow-title a[href*="/threads/"]');
      if (titleAnchor == null) continue;

      final href = titleAnchor.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      // Normalize thread URL without /unread or page-N
      var threadUrl = _cleanUrl(href).replaceAll(RegExp(r'/unread$'), '/');
      if (!threadUrl.endsWith('/')) threadUrl = '$threadUrl/';
      if (seen.contains(threadUrl)) continue;

      // Prefer threads that actually have Threadmarks (stories) when in forum view
      final hasThreadmarks = item.querySelector('a[href*="/threadmarks"]') != null;
      if (item.classes.contains('structItem--thread') && !hasThreadmarks) {
        continue;
      }

      final title = TextCleaner.cleanNovelTitle(titleAnchor.text.trim());
      if (title.isEmpty) continue;

      seen.add(threadUrl);
      final author = item.attributes['data-author']?.trim() ??
          item.querySelector('.username')?.text.trim() ??
          'Unknown Author';

      final img = item.querySelector('.structItem-iconContainer img, .contentRow-figure img');
      var coverUrl = '';
      if (img != null) {
        final src = img.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('data:')) {
          coverUrl = _cleanUrl(src);
        }
      }

      final wordCountText = item.querySelector('a[href*="/threadmarks"]')?.text.trim() ?? '';
      final segs = Uri.parse(threadUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      final slug = segs.isNotEmpty ? segs.last : threadUrl.hashCode.toString();

      novels.add(Novel(
        id: '${id}_$slug',
        sourceId: id,
        title: title,
        author: author,
        coverUrl: coverUrl,
        sourceUrl: threadUrl,
        description: wordCountText.isNotEmpty ? 'Threadmarks • $wordCountText' : '',
        status: 'Ongoing',
      ));
    }
    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);

    final title = TextCleaner.cleanNovelTitle(
      doc.querySelector('h1.p-title-value')?.text.trim() ??
          doc.querySelector('h1')?.text.trim() ??
          'Story',
    );
    final author = doc.querySelector('.p-description .username, .message-name .username')?.text.trim() ?? 'Unknown Author';

    final tags = doc
        .querySelectorAll('.tagList .tagItem')
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    var coverUrl = '';
    final iconImg = doc.querySelector('.threadmark-index-icon img, .message-avatar img');
    if (iconImg != null) {
      final src = iconImg.attributes['src'] ?? '';
      if (src.isNotEmpty && !src.startsWith('data:')) {
        coverUrl = _cleanUrl(src);
      }
    }

    final firstPostText = doc.querySelector('article.message .bbWrapper')?.text.trim() ?? '';
    final desc = firstPostText.length > 500 ? '${firstPostText.substring(0, 500)}...' : firstPostText;

    final segs = Uri.parse(novelUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    final slug = segs.isNotEmpty ? segs.last : novelUrl.hashCode.toString();

    return Novel(
      id: '${id}_$slug',
      sourceId: id,
      title: title,
      author: author,
      coverUrl: coverUrl,
      sourceUrl: novelUrl,
      description: desc,
      genres: tags,
      status: 'Ongoing',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final baseThread = novelUrl.endsWith('/') ? novelUrl : '$novelUrl/';
    final tmUrl = '${baseThread}threadmarks';

    final page1Html = await _fetchHtml(tmUrl);
    final doc1 = html_parser.parse(page1Html);

    final segs = Uri.parse(baseThread).pathSegments.where((s) => s.isNotEmpty).toList();
    final slug = segs.isNotEmpty ? segs.last : baseThread.hashCode.toString();
    final novelId = '${id}_$slug';

    final chapters = <Chapter>[];
    final seenUrls = <String>{};

    void parseDoc(dom.Document doc) {
      final items = doc.querySelectorAll('.structItem--threadmark');
      for (final item in items) {
        final a = item.querySelector('a[href*="post-"], .structItem-title a[href*="/threads/"]');
        if (a == null) continue;
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final fullUrl = _cleanUrl(href, keepFragment: true);
        if (seenUrls.contains(fullUrl)) continue;
        seenUrls.add(fullUrl);

        final title = a.text.trim();
        if (title.isEmpty) continue;

        final date = item.querySelector('time')?.attributes['datetime'] ?? item.querySelector('time')?.text.trim();
        final postMatch = RegExp(r'post-(\d+)').firstMatch(fullUrl);
        final chId = postMatch != null ? '${novelId}_p${postMatch.group(1)}' : '${novelId}_c${chapters.length + 1}';

        chapters.add(Chapter(
          id: chId,
          novelId: novelId,
          title: title,
          url: fullUrl,
          chapterNumber: (chapters.length + 1).toDouble(),
          releaseDate: date,
        ));
      }
    }

    parseDoc(doc1);
    if (chapters.isNotEmpty) {
      onBatchLoaded?.call(List.from(chapters));
    }

    int maxPage = 1;
    for (final a in doc1.querySelectorAll('.pageNav-main a')) {
      final p = int.tryParse(a.text.trim());
      if (p != null && p > maxPage) maxPage = p;
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'page=(\d+)').firstMatch(href);
      if (m != null) {
        final mp = int.tryParse(m.group(1)!);
        if (mp != null && mp > maxPage) maxPage = mp;
      }
    }

    if (maxPage > 1) {
      const int batchSize = 3;
      final capped = maxPage.clamp(1, 100);
      for (int i = 2; i <= capped; i += batchSize) {
        final end = (i + batchSize - 1) > capped ? capped : (i + batchSize - 1);
        final futures = <Future<String?>>[];
        for (int p = i; p <= end; p++) {
          futures.add(_fetchHtml('$tmUrl?per_page=25&page=$p').then<String?>((v) => v).catchError((_) => null));
        }
        final bodies = await Future.wait(futures);
        bool added = false;
        for (final b in bodies) {
          if (b != null && b.isNotEmpty) {
            final before = chapters.length;
            parseDoc(html_parser.parse(b));
            if (chapters.length > before) added = true;
          }
        }
        if (added) {
          onBatchLoaded?.call(List.from(chapters));
        }
      }
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final html = await _fetchHtml(chapterUrl);
    final doc = html_parser.parse(html);

    final postMatch = RegExp(r'post-(\d+)').firstMatch(chapterUrl);
    dom.Element? postEl;
    if (postMatch != null) {
      final pid = 'post-${postMatch.group(1)}';
      postEl = doc.querySelector('article[data-content="$pid"], #js-$pid');
    }
    postEl ??= doc.querySelector('article.message');

    final title = postEl?.querySelector('.threadmark-title, h3, .message-threadmark-header')?.text.trim() ??
        doc.querySelector('h1.p-title-value')?.text.trim() ??
        'Chapter';

    final wrapper = postEl?.querySelector('.message-body .bbWrapper, .bbWrapper');
    if (wrapper == null) {
      throw Exception('Post content (.bbWrapper) not found on $chapterUrl');
    }

    wrapper.querySelectorAll('script, style, .bbCodeBlock--quote .bbCodeBlock-expandLink').forEach((e) => e.remove());

    final rawHtml = wrapper.innerHtml;
    final cleanHtml = rawHtml
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|li|blockquote)>', caseSensitive: false), '\n\n');

    final fragment = html_parser.parseFragment(cleanHtml);
    final paragraphs = (fragment.text ?? '')
        .split(RegExp(r'\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) {
      throw Exception('Empty chapter content on $chapterUrl');
    }

    return ChapterContent(
      chapterId: postMatch != null ? 'p${postMatch.group(1)}' : chapterUrl.hashCode.toString(),
      novelId: id,
      title: title,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
