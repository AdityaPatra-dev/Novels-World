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

/// Bespoke Extractor for Beneath Ceaseless Skies (https://beneath-ceaseless-skies.com).
class BeneathCeaselessSkiesExtractor implements NovelSource {
  @override
  final String id = 'beneathceaselessskies';

  @override
  final String name = 'Beneath Ceaseless Skies';

  @override
  final String baseUrl = 'https://beneath-ceaseless-skies.com';

  @override
  final String lang = 'en';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 1000;

  late final http.Client _client;

  BeneathCeaselessSkiesExtractor({http.Client? client}) {
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
      throw HttpException('Failed to load $url from Beneath Ceaseless Skies.');
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
    final targetUrl = page > 1 ? '$baseUrl/stories/page/$page/' : '$baseUrl/stories/';
    final html = await _fetchHtml(targetUrl);
    final list = _parseStories(html);
    if (list.isEmpty) return list;

    // /stories/ archive is text-only; fetch og:image covers in parallel for the page
    final enriched = await Future.wait(list.take(12).map((n) async {
      if (n.coverUrl.isNotEmpty) return n;
      try {
        final sHtml = await _fetchHtml(n.sourceUrl);
        final sDoc = html_parser.parse(sHtml);
        final ogImg = sDoc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
        if (ogImg.isNotEmpty) {
          return Novel(
            id: n.id,
            sourceId: n.sourceId,
            title: n.title,
            author: n.author,
            coverUrl: _cleanUrl(ogImg),
            sourceUrl: n.sourceUrl,
            genres: n.genres,
            status: n.status,
          );
        }
      } catch (_) {}
      return n;
    }));
    return [...enriched, ...list.skip(12)];
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final q = Uri.encodeComponent(query.trim());
    final html = await _fetchHtml('$baseUrl/?s=$q');
    return _parseStories(html);
  }

  List<Novel> _parseStories(String html) {
    final doc = html_parser.parse(html);
    final novels = <Novel>[];
    final seen = <String>{};

    for (final a in doc.querySelectorAll('a[href*="/stories/"]')) {
      final rawHref = a.attributes['href'] ?? '';
      if (rawHref.contains('#comment') || rawHref.endsWith('/stories/')) continue;
      final storyUrl = _cleanUrl(rawHref);
      if (storyUrl == '$baseUrl/stories/' || seen.contains(storyUrl)) continue;

      final title = TextCleaner.cleanNovelTitle(a.text.trim());
      if (title.isEmpty || title.length < 2) continue;
      seen.add(storyUrl);

      final img = a.parent?.parent?.querySelector('img');
      var coverUrl = '';
      if (img != null) {
        final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('data:')) coverUrl = _cleanUrl(src);
      }

      novels.add(Novel(
        id: '${id}_${storyUrl.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: 'Beneath Ceaseless Skies',
        coverUrl: coverUrl,
        sourceUrl: storyUrl,
        genres: const ['Fantasy', 'Short Story'],
        status: 'Completed',
      ));
    }
    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);

    final rawTitle = doc.querySelector('h1.entry-title, h1.story-title, .entry-header h1')?.text.trim() ??
        doc.querySelector('meta[property="og:title"]')?.attributes['content']?.trim() ??
        doc.querySelector('title')?.text.split('|').first.trim() ??
        'Story';
    final title = TextCleaner.cleanNovelTitle(rawTitle);
    final cover = doc.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';
    final desc = doc.querySelector('meta[property="og:description"]')?.attributes['content'] ?? '';
    final author = doc.querySelector('a[href*="/authors/"], .author')?.text.trim() ?? 'Beneath Ceaseless Skies';

    return Novel(
      id: '${id}_${novelUrl.hashCode.abs()}',
      sourceId: id,
      title: title,
      author: author,
      coverUrl: cover.isNotEmpty ? _cleanUrl(cover) : '',
      sourceUrl: novelUrl,
      description: desc,
      genres: const ['Fantasy', 'Short Story'],
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
    final container = doc.querySelector('.bcs-story-content, .entry-content, article');
    if (container == null) {
      throw Exception('Story content not found on $chapterUrl');
    }

    container.querySelectorAll('script, style').forEach((e) => e.remove());

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
