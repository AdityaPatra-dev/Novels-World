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

/// Bespoke Extractor for Flash Fiction Online (https://flashfictiononline.com).
/// Each issue is represented as a multi-chapter anthology containing that issue's stories.
class FlashFictionOnlineExtractor implements NovelSource {
  @override
  final String id = 'flashfictiononline';

  @override
  final String name = 'Flash Fiction Online';

  @override
  final String baseUrl = 'https://flashfictiononline.com';

  @override
  final String lang = 'en';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 800;

  late final http.Client _client;

  FlashFictionOnlineExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
        'User-Agent': WebViewSessionManager.defaultUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': '$baseUrl/',
      };

  Future<String> _fetchHtml(String url) async {
    String htmlBody = '';
    try {
      final resp = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) htmlBody = resp.body;
    } catch (_) {}

    if (htmlBody.isEmpty) {
      final wvHtml = await WebViewSessionManager.instance.fetchHtmlViaWebView(url);
      if (wvHtml != null) htmlBody = wvHtml;
    }
    if (htmlBody.isEmpty) {
      throw HttpException('Failed to load $url from Flash Fiction Online.');
    }
    return htmlBody;
  }

  String _cleanUrl(String url) {
    final t = url.trim();
    if (t.isEmpty) return '';
    try {
      return Uri.parse(baseUrl).resolve(t).removeFragment().toString();
    } catch (_) {
      return t;
    }
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final html = await _fetchHtml('$baseUrl/issues/');
    return _parseIssues(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final list = await getPopular(page: 1);
    final qLower = query.toLowerCase();
    return list.where((n) => n.title.toLowerCase().contains(qLower)).toList();
  }

  List<Novel> _parseIssues(String html) {
    final doc = html_parser.parse(html);
    final novels = <Novel>[];
    final seen = <String>{};

    for (final a in doc.querySelectorAll('a[href*="/issues/"]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty || href.endsWith('/issues/')) continue;
      final issueUrl = _cleanUrl(href);
      if (issueUrl == '$baseUrl/issues/' || seen.contains(issueUrl)) continue;
      seen.add(issueUrl);

      final title = TextCleaner.cleanNovelTitle(a.text.trim());
      if (title.isEmpty || title.toLowerCase().contains('all issues')) continue;

      final img = a.parent?.parent?.querySelector('img');
      var coverUrl = '';
      if (img != null) {
        final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('data:')) coverUrl = _cleanUrl(src);
      }

      novels.add(Novel(
        id: '${id}_${issueUrl.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: 'Flash Fiction Online',
        coverUrl: coverUrl,
        sourceUrl: issueUrl,
        genres: const ['Flash Fiction', 'Sci-Fi & Fantasy'],
        status: 'Completed',
      ));
    }
    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);

    final title = TextCleaner.cleanNovelTitle(doc.querySelector('h1')?.text.trim() ?? 'Issue');
    final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
    final desc = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ?? '';

    return Novel(
      id: '${id}_${novelUrl.hashCode.abs()}',
      sourceId: id,
      title: title,
      author: 'Flash Fiction Online',
      coverUrl: cover.isNotEmpty ? _cleanUrl(cover) : '',
      sourceUrl: novelUrl,
      description: desc,
      genres: const ['Flash Fiction', 'Sci-Fi & Fantasy'],
      status: 'Completed',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);
    final novelId = '${id}_${novelUrl.hashCode.abs()}';

    final chapters = <Chapter>[];
    final seenIds = <String>{};

    // Issue TOC links point to #story-slug fragments on the same issue page
    for (final a in doc.querySelectorAll('a[href*="#"]')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('#')) continue;
      final frag = href.split('#').last.trim();
      if (frag.isEmpty || frag == 'respond' || frag.startsWith('comment') || seenIds.contains(frag)) continue;
      final title = a.text.trim();
      if (title.isEmpty || title.toLowerCase().contains('cancel reply')) continue;
      seenIds.add(frag);

      chapters.add(Chapter(
        id: '${novelId}_$frag',
        novelId: novelId,
        title: title,
        chapterNumber: (chapters.length + 1).toDouble(),
        url: '${novelUrl.split('#').first}#$frag',
      ));
    }

    if (chapters.isEmpty) {
      chapters.add(Chapter(
        id: '${novelId}_1',
        novelId: novelId,
        title: 'Full Issue',
        chapterNumber: 1.0,
        url: novelUrl,
      ));
    }

    onBatchLoaded?.call(chapters);
    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final base = chapterUrl.split('#').first;
    final frag = chapterUrl.contains('#') ? chapterUrl.split('#').last.trim() : '';
    final html = await _fetchHtml(base);
    final doc = html_parser.parse(html);

    final blocks = doc.querySelectorAll('.tb_text_wrap');
    final paragraphs = <String>[];
    String title = doc.querySelector('h1')?.text.trim() ?? 'Story';

    if (frag.isNotEmpty) {
      final targetEl = doc.querySelector('#$frag');
      if (targetEl != null) {
        title = targetEl.text.trim().isNotEmpty ? targetEl.text.trim() : title;
        // Collect paragraphs from the nearest following .tb_text_wrap section(s)
        var parentRow = targetEl.parent;
        while (parentRow != null && parentRow.querySelectorAll('.tb_text_wrap p').length < 3) {
          parentRow = parentRow.parent;
        }
        final scope = parentRow ?? doc.body;
        if (scope != null) {
          for (final p in scope.querySelectorAll('.tb_text_wrap p')) {
            final t = p.text.trim();
            if (t.isNotEmpty) paragraphs.add(t);
          }
        }
      }
    }

    if (paragraphs.isEmpty) {
      for (final b in blocks) {
        for (final p in b.querySelectorAll('p')) {
          final t = p.text.trim();
          if (t.isNotEmpty) paragraphs.add(t);
        }
      }
    }

    if (paragraphs.isEmpty) {
      throw Exception('Empty story text on $chapterUrl');
    }

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: id,
      title: title,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
