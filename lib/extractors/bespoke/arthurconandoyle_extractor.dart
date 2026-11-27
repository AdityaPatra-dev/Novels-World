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

/// Bespoke Extractor for The Arthur Conan Doyle Encyclopedia (https://www.arthur-conan-doyle.com).
class ArthurConanDoyleExtractor implements NovelSource {
  @override
  final String id = 'arthurconandoyle';

  @override
  final String name = 'Arthur Conan Doyle Online';

  @override
  final String baseUrl = 'https://www.arthur-conan-doyle.com';

  @override
  final String lang = 'en';

  @override
  String get iconUrl => '$baseUrl/favicon.ico';

  @override
  final int estimatedNovelCount = 550;

  late final http.Client _client;
  List<Novel>? _cachedCatalog;

  ArthurConanDoyleExtractor({http.Client? client}) {
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
      throw HttpException('Failed to load $url from Arthur Conan Doyle Online.');
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

  Future<List<Novel>> _loadCatalog() async {
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      return _cachedCatalog!;
    }
    final html = await _fetchHtml('$baseUrl/wiki/Sir_Arthur_Conan_Doyle:Complete_Works');
    final doc = html_parser.parse(html);
    final ficHeading = doc.querySelector('#Fictions');
    final wrapper = ficHeading?.parent;
    final novels = <Novel>[];
    final seen = <String>{};

    if (wrapper != null) {
      var sib = wrapper.nextElementSibling;
      while (sib != null) {
        if (sib.classes.contains('mw-heading2') || sib.localName == 'h2') break;
        for (final li in sib.querySelectorAll('li')) {
          final a = li.querySelector('a[href*="/wiki/"]');
          if (a == null) continue;
          final href = a.attributes['href'] ?? '';
          if (href.isEmpty || href.contains(':') || href.endsWith('_(film)')) continue;

          final workUrl = _cleanUrl(href);
          if (seen.contains(workUrl)) continue;
          seen.add(workUrl);

          final title = TextCleaner.cleanNovelTitle(a.text.trim());
          if (title.isEmpty) continue;

          novels.add(Novel(
            id: '${id}_${workUrl.hashCode.abs()}',
            sourceId: id,
            title: title,
            author: 'Arthur Conan Doyle',
            coverUrl: '',
            sourceUrl: workUrl,
            genres: const ['Mystery', 'Detective', 'Classic'],
            status: 'Completed',
          ));
        }
        sib = sib.nextElementSibling;
      }
    }

    _cachedCatalog = novels;
    return novels;
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final all = await _loadCatalog();
    const pageSize = 30;
    final start = (page - 1) * pageSize;
    if (start >= all.length) return [];
    return all.skip(start).take(pageSize).toList();
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => getPopular(page: page);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final all = await _loadCatalog();
    final qLower = query.toLowerCase();
    return all.where((n) => n.title.toLowerCase().contains(qLower)).toList();
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final html = await _fetchHtml(novelUrl);
    final doc = html_parser.parse(html);

    final title = TextCleaner.cleanNovelTitle(
      doc.querySelector('#firstHeading, h1')?.text.trim() ?? 'Story',
    );
    var coverUrl = '';
    final img = doc.querySelector('#mw-content-text img.mw-file-element, #mw-content-text .thumbimage');
    if (img != null) {
      final src = img.attributes['src'] ?? '';
      if (src.isNotEmpty && !src.startsWith('data:')) coverUrl = _cleanUrl(src);
    }

    final firstP = doc.querySelector('#mw-content-text p')?.text.trim() ?? '';

    return Novel(
      id: '${id}_${novelUrl.hashCode.abs()}',
      sourceId: id,
      title: title,
      author: 'Arthur Conan Doyle',
      coverUrl: coverUrl,
      sourceUrl: novelUrl,
      description: firstP,
      genres: const ['Mystery', 'Detective', 'Classic'],
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
        title: 'Full Text',
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

    final title = doc.querySelector('#firstHeading, h1')?.text.trim() ?? 'Story';
    final container = doc.querySelector('#mw-content-text');
    if (container == null) {
      throw Exception('Content not found on $chapterUrl');
    }

    container
        .querySelectorAll('script, style, #toc, .toc, .infobox, .navbox, .mw-editsection, .catlinks, table')
        .forEach((e) => e.remove());

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
