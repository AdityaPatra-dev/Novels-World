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

/// Bespoke Extractor for Inkitt (https://www.inkitt.com).
class InkittExtractor implements NovelSource {
  @override
  final String id = 'inkitt';

  @override
  final String name = 'Inkitt';

  @override
  final String baseUrl = 'https://www.inkitt.com';

  @override
  final String lang = 'en';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 50000;

  late final http.Client _client;

  InkittExtractor({http.Client? client}) {
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
      throw HttpException('Failed to load $url from Inkitt.');
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
    final genres = ['romance', 'fantasy', 'scifi', 'mystery'];
    final genre = genres[(page - 1) % genres.length];
    final html = await _fetchHtml('$baseUrl/genres/$genre');
    return _parseStoryList(html);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final pop = await getPopular(page: 1);
    final qLower = query.toLowerCase();
    return pop
        .where((n) => n.title.toLowerCase().contains(qLower) || n.author.toLowerCase().contains(qLower))
        .toList();
  }

  List<Novel> _parseStoryList(String html) {
    final doc = html_parser.parse(html);
    final novels = <Novel>[];
    final seen = <String>{};

    for (final a in doc.querySelectorAll('a[href*="/stories/"]')) {
      final href = a.attributes['href'] ?? '';
      final match = RegExp(r'^/stories/(\d+)$').firstMatch(href) ??
          RegExp(r'inkitt\.com/stories/(\d+)$').firstMatch(href);
      if (match == null) continue;

      final storyId = match.group(1)!;
      final storyUrl = '$baseUrl/stories/$storyId';
      if (seen.contains(storyUrl)) continue;

      final title = TextCleaner.cleanNovelTitle(a.text.trim());
      if (title.isEmpty || title.length < 2) continue;

      seen.add(storyUrl);
      final card = a.parent?.parent;
      final img = card?.querySelector('img');
      var coverUrl = '';
      if (img != null) {
        final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('data:')) coverUrl = _cleanUrl(src);
      }

      novels.add(Novel(
        id: '${id}_$storyId',
        sourceId: id,
        title: title,
        author: 'Inkitt Author',
        coverUrl: coverUrl,
        sourceUrl: storyUrl,
        genres: const ['Romance', 'Web Fiction'],
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
      doc.querySelector('h1')?.text.trim() ??
          doc.querySelector('meta[property="og:title"]')?.attributes['content']?.trim() ??
          'Story',
    );
    final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
    final desc = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ?? '';
    final author = doc.querySelector('a[href*="/users/"], [rel="author"]')?.text.trim() ?? 'Inkitt Author';

    final match = RegExp(r'/stories/(\d+)').firstMatch(novelUrl);
    final storyId = match?.group(1) ?? novelUrl.hashCode.abs().toString();

    return Novel(
      id: '${id}_$storyId',
      sourceId: id,
      title: title,
      author: author,
      coverUrl: cover.isNotEmpty ? _cleanUrl(cover) : '',
      sourceUrl: novelUrl,
      description: desc,
      genres: const ['Romance', 'Web Fiction'],
      status: 'Ongoing',
    );
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);

    final match = RegExp(r'/stories/(\d+)').firstMatch(novelUrl);
    final storyId = match?.group(1) ?? novelUrl.hashCode.abs().toString();
    final novelId = '${id}_$storyId';

    final chapters = <Chapter>[];
    final seenUrls = <String>{};

    for (final a in doc.querySelectorAll('a[href*="/chapters/"]')) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final chUrl = _cleanUrl(href);
      if (seenUrls.contains(chUrl)) continue;
      seenUrls.add(chUrl);

      final title = a.text.trim().isNotEmpty ? a.text.trim() : 'Chapter ${chapters.length + 1}';
      final numMatch = RegExp(r'/chapters/(\d+)').firstMatch(chUrl);
      final chNum = numMatch != null ? double.tryParse(numMatch.group(1)!) : (chapters.length + 1).toDouble();

      chapters.add(Chapter(
        id: '${novelId}_c${numMatch?.group(1) ?? chapters.length + 1}',
        novelId: novelId,
        title: title,
        chapterNumber: chNum,
        url: chUrl,
      ));
    }

    if (chapters.isNotEmpty) {
      chapters.sort((a, b) => (a.chapterNumber ?? 0).compareTo(b.chapterNumber ?? 0));
      onBatchLoaded?.call(chapters);
    }
    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final html = await _fetchHtml(chapterUrl);
    final doc = html_parser.parse(html);

    final title = doc.querySelector('h1, h2')?.text.trim() ?? 'Chapter';
    final container = doc.querySelector('article, #story-text, .story-text, main');
    if (container == null) {
      throw Exception('Chapter content not found on $chapterUrl');
    }

    container.querySelectorAll('script, style, nav, footer').forEach((e) => e.remove());

    final paragraphs = container
        .querySelectorAll('p')
        .map((p) => p.text.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) {
      throw Exception('Empty chapter content on $chapterUrl');
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
