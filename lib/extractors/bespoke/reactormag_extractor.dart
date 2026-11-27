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

/// Bespoke Extractor for Reactor Mag / Tor.com Original Fiction (https://reactormag.com/fiction/).
class ReactorMagExtractor implements NovelSource {
  @override
  final String id = 'reactormag';

  @override
  final String name = 'Reactor Mag';

  @override
  final String baseUrl = 'https://reactormag.com';

  @override
  final String lang = 'en';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 1500;

  late final http.Client _client;

  ReactorMagExtractor({http.Client? client}) {
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
      throw HttpException('Failed to load $url from Reactor Mag.');
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
    final html = await _fetchHtml('$baseUrl/fiction/');
    return _parseStoryList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final list = await getPopular(page: 1);
    final qLower = query.toLowerCase();
    return list
        .where((n) => n.title.toLowerCase().contains(qLower) || n.author.toLowerCase().contains(qLower))
        .toList();
  }

  List<Novel> _parseStoryList(String html) {
    final doc = html_parser.parse(html);
    final novels = <Novel>[];
    final seen = <String>{};

    for (final a in doc.querySelectorAll('h2 a, h3 a, .entry-title a')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty || href.contains('/fictions/') || href.contains('/category/')) continue;
      final storyUrl = _cleanUrl(href);
      if (!storyUrl.startsWith(baseUrl) || seen.contains(storyUrl)) continue;
      seen.add(storyUrl);

      final title = TextCleaner.cleanNovelTitle(a.text.trim());
      if (title.isEmpty) continue;

      final card = a.parent?.parent?.parent ?? a.parent?.parent;
      final img = card?.querySelector('img');
      var coverUrl = '';
      if (img != null) {
        final src = img.attributes['data-lazy-src'] ??
            img.attributes['data-src'] ??
            img.attributes['src'] ??
            '';
        if (src.isNotEmpty && !src.startsWith('data:')) coverUrl = _cleanUrl(src);
      }

      novels.add(Novel(
        id: '${id}_${storyUrl.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: 'Reactor Mag',
        coverUrl: coverUrl,
        sourceUrl: storyUrl,
        genres: const ['Sci-Fi & Fantasy', 'Short Story'],
        status: 'Completed',
      ));
    }
    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);

    var rawTitle = doc.querySelector('h1.entry-title, article h1, h1')?.text.trim() ??
        doc.querySelector('meta[property="og:title"]')?.attributes['content']?.trim() ??
        'Story';
    rawTitle = rawTitle.replaceFirst(RegExp(r'\s*[-–|]\s*Reactor\s*$', caseSensitive: false), '').trim();
    final title = TextCleaner.cleanNovelTitle(rawTitle);
    final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
    final desc = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ?? '';
    final author = doc.querySelector('a[rel="author"], .author-name')?.text.trim() ?? 'Reactor Mag';

    return Novel(
      id: '${id}_${novelUrl.hashCode.abs()}',
      sourceId: id,
      title: title,
      author: author,
      coverUrl: cover.isNotEmpty ? _cleanUrl(cover) : '',
      sourceUrl: novelUrl,
      description: desc,
      genres: const ['Sci-Fi & Fantasy', 'Short Story'],
      status: 'Completed',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final ch = [
      Chapter(
        id: '${id}_${novelUrl.hashCode.abs()}_1',
        novelId: '${id}_${novelUrl.hashCode.abs()}',
        title: 'Full Story',
        chapterNumber: 1.0,
        url: novelUrl,
      ),
    ];
    onBatchLoaded?.call(ch);
    return ch;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final html = await _fetchHtml(chapterUrl);
    final doc = html_parser.parse(html);

    final title = doc.querySelector('h1')?.text.trim() ?? 'Story';
    final container = doc.querySelector('article, .entry-content, main');
    if (container == null) {
      throw Exception('Story content not found on $chapterUrl');
    }

    container.querySelectorAll('script, style, nav, footer, .comments-area').forEach((e) => e.remove());

    final paragraphs = container
        .querySelectorAll('p')
        .map((p) => p.text.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) {
      throw Exception('Empty story text on $chapterUrl');
    }

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}_1',
      novelId: id,
      title: title,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
