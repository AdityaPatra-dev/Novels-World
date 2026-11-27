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

/// Bespoke Extractor for Escape Pod (https://escapepod.org).
class EscapePodExtractor implements NovelSource {
  @override
  final String id = 'escapepod';

  @override
  final String name = 'Escape Pod';

  @override
  final String baseUrl = 'https://escapepod.org';

  @override
  final String lang = 'en';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 1200;

  late final http.Client _client;

  EscapePodExtractor({http.Client? client}) {
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
      throw HttpException('Failed to load $url from Escape Pod.');
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
    final targetUrl = page > 1 ? '$baseUrl/page/$page/' : '$baseUrl/';
    final html = await _fetchHtml(targetUrl);
    return _parseStoryList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final q = Uri.encodeComponent(query.trim());
    final targetUrl = page > 1 ? '$baseUrl/page/$page/?s=$q' : '$baseUrl/?s=$q';
    final html = await _fetchHtml(targetUrl);
    return _parseStoryList(html);
  }

  List<Novel> _parseStoryList(String html) {
    final doc = html_parser.parse(html);
    final novels = <Novel>[];
    final seen = <String>{};

    for (final art in doc.querySelectorAll('article')) {
      final link = art.querySelector('h2 a, h3 a, .entry-title a');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final storyUrl = _cleanUrl(href);
      if (seen.contains(storyUrl)) continue;
      seen.add(storyUrl);

      final title = TextCleaner.cleanNovelTitle(link.text.trim());
      if (title.isEmpty) continue;

      final img = art.querySelector('img');
      var coverUrl = '';
      if (img != null) {
        final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('data:')) {
          coverUrl = _cleanUrl(src);
        }
      }

      final author = art.querySelector('.author a, .byline a')?.text.trim() ?? 'Escape Pod';
      final desc = art.querySelector('.entry-summary p, p')?.text.trim() ?? '';

      novels.add(Novel(
        id: '${id}_${storyUrl.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        coverUrl: coverUrl,
        sourceUrl: storyUrl,
        description: desc,
        genres: const ['Science Fiction', 'Short Story'],
        status: 'Completed',
      ));
    }
    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);

    final rawTitle = doc.querySelector('h1.entry-title')?.text.trim() ??
        doc.querySelector('meta[property="og:title"]')?.attributes['content']?.trim() ??
        doc.querySelector('title')?.text.split('|').first.trim() ??
        'Story';
    final title = TextCleaner.cleanNovelTitle(rawTitle);
    final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
    final desc = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ?? '';
    final author = doc.querySelector('.author a, meta[name="author"]')?.attributes['content'] ??
        doc.querySelector('.author a')?.text.trim() ??
        'Escape Pod';

    return Novel(
      id: '${id}_${novelUrl.hashCode.abs()}',
      sourceId: id,
      title: title,
      author: author,
      coverUrl: cover.isNotEmpty ? _cleanUrl(cover) : '',
      sourceUrl: novelUrl,
      description: desc,
      genres: const ['Science Fiction', 'Short Story'],
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

    final title = doc.querySelector('h1.entry-title, h1')?.text.trim() ?? 'Story';
    final container = doc.querySelector('.entry_content, .entry-content, article');
    if (container == null) {
      throw Exception('Story content not found on $chapterUrl');
    }

    container.querySelectorAll('script, style, .powerpress_player, .sharedaddy').forEach((e) => e.remove());

    final paragraphs = container
        .querySelectorAll('p')
        .map((p) => p.text.trim())
        .where((p) => p.isNotEmpty && !p.startsWith('Audio Player'))
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
