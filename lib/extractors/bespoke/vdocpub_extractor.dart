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

/// Bespoke extractor for VDoc.pub (https://vdoc.pub)
/// Major document, novel, and digital book repository hosting millions of publications.
class VdocPubExtractor implements NovelSource {
  @override
  final String id = 'vdocpub';
  @override
  final String name = 'VDoc.pub';
  @override
  final String baseUrl = 'https://vdoc.pub';
  @override
  final String lang = 'en';
  @override
  final String iconUrl = 'https://vdoc.pub/favicon.ico';
  @override
  final int estimatedNovelCount = 95000;

  late final http.Client _client;

  VdocPubExtractor({http.Client? client}) {
    if (client != null) {
      _client = client;
    } else {
      final nativeHttpClient = HttpClient();
      nativeHttpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      nativeHttpClient.connectionTimeout = const Duration(seconds: 15);
      _client = IOClient(nativeHttpClient);
    }
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': baseUrl,
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

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final encodedQuery = Uri.encodeComponent(query);
    // VDoc.pub routes searches via /search?q= or /search/[query]
    final targetUrl = page <= 1
        ? '$baseUrl/search?q=$encodedQuery'
        : '$baseUrl/search?q=$encodedQuery&page=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      // Fallback path query
      final fallbackUrl = '$baseUrl/search/$encodedQuery';
      final fbResponse = await _client.get(Uri.parse(fallbackUrl), headers: _headers);
      if (fbResponse.statusCode == 200) {
        return _parseDocumentList(fbResponse.body);
      }
      return [];
    }

    return _parseDocumentList(response.body);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    final targetUrl = page <= 1
        ? '$baseUrl/search?q=novel'
        : '$baseUrl/search?q=novel&page=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      final homeResponse = await _client.get(Uri.parse(baseUrl), headers: _headers);
      if (homeResponse.statusCode == 200) {
        return _parseDocumentList(homeResponse.body);
      }
      return [];
    }

    return _parseDocumentList(response.body);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    final targetUrl = page <= 1
        ? '$baseUrl/'
        : '$baseUrl/?page=$page';

    final response = await _client.get(Uri.parse(targetUrl), headers: _headers);
    if (response.statusCode != 200) {
      return [];
    }

    return _parseDocumentList(response.body);
  }

  List<Novel> _parseDocumentList(String html) {
    final document = html_parser.parse(html);
    final List<Novel> novels = [];

    // Match document result cards or links pointing to /documents/
    final docLinks = document.querySelectorAll('a[href*="/documents/"]');
    final Set<String> seenUrls = {};

    for (final link in docLinks) {
      final href = link.attributes['href'] ?? '';
      final fullUrl = _cleanUrl(href);
      if (seenUrls.contains(fullUrl) || !fullUrl.contains('/documents/')) continue;
      seenUrls.add(fullUrl);

      // Title
      String title = link.text.trim();
      var parent = link.parent;
      var card = parent ?? link;
      while (parent != null && parent.localName != 'body') {
        final classes = parent.className;
        if (classes.contains('card') ||
            classes.contains('document-item') ||
            classes.contains('result-item') ||
            classes.contains('list-item')) {
          card = parent;
          break;
        }
        parent = parent.parent;
      }

      final heading = card.querySelector('h2, h3, h4, .title');
      if (heading != null && heading.text.trim().isNotEmpty) {
        title = heading.text.trim();
      }

      if (title.isEmpty || title.toLowerCase() == 'download' || title.toLowerCase() == 'view') {
        continue;
      }

      // Cover
      String coverUrl = '';
      final img = card.querySelector('img');
      if (img != null) {
        coverUrl = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        coverUrl = _cleanUrl(coverUrl);
      }

      // Author / metadata
      String author = 'Unknown Author';
      final authorElem = card.querySelector('.author, .meta, span.text-muted');
      if (authorElem != null && authorElem.text.trim().isNotEmpty) {
        author = authorElem.text.trim().replaceAll(RegExp(r'^(by|author):\s*', caseSensitive: false), '');
      }

      novels.add(Novel(
        id: fullUrl,
        sourceId: id,
        title: title,
        author: author,
        coverUrl: coverUrl,
        sourceUrl: fullUrl,
        genres: ['Fiction', 'Literature'],
        status: 'COMPLETED',
      ));
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load VDoc.pub details from $novelUrl (status ${response.statusCode})');
    }

    final document = html_parser.parse(response.body);

    // Title
    final titleElem = document.querySelector('h1, .document-title, title');
    String title = titleElem?.text.trim() ?? 'Unknown Document';
    title = title.replaceAll(RegExp(r'\s*\[PDF\].*|\s*\[EPUB\].*|- VDoc\.pub.*', caseSensitive: false), '').trim();

    // Author
    String author = 'Unknown Author';
    final metaRows = document.querySelectorAll('tr, .meta-item, .detail-item, p');
    for (final row in metaRows) {
      final text = row.text.trim();
      if (text.toLowerCase().contains('author:') || text.toLowerCase().contains('author')) {
        final parts = text.split(':');
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          author = parts[1].trim();
          break;
        }
      }
    }

    // Cover
    String coverUrl = '';
    final coverImg = document.querySelector('.cover img, .document-cover img, img[src*="cover"], article img');
    if (coverImg != null) {
      coverUrl = coverImg.attributes['data-src'] ?? coverImg.attributes['src'] ?? '';
      coverUrl = _cleanUrl(coverUrl);
    }

    // Synopsis / Description
    final descElem = document.querySelector('.description, .summary, .document-description, #description');
    String description = descElem?.text.trim() ?? '';
    if (description.isEmpty) {
      final paragraphs = document.querySelectorAll('p');
      final descList = paragraphs
          .map((p) => p.text.trim())
          .where((t) => t.length > 40 && !t.toLowerCase().contains('download'))
          .take(4)
          .toList();
      description = descList.join('\n\n');
    }

    return Novel(
      id: novelUrl,
      sourceId: id,
      title: title,
      author: author,
      description: description,
      coverUrl: coverUrl,
      genres: ['Literature', 'Document'],
      status: 'COMPLETED',
      sourceUrl: novelUrl,
    );
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    final response = await _client.get(Uri.parse(novelUrl), headers: _headers);
    if (response.statusCode != 200) {
      return [];
    }

    final document = html_parser.parse(response.body);
    final titleElem = document.querySelector('h1, .document-title');
    final title = titleElem?.text.trim() ?? 'Document';

    final List<Chapter> chapters = [];

    // Check for TOC / Table of Contents items if structured
    final tocLinks = document.querySelectorAll('.toc a, .chapters a, a[href*="#page-"]');
    if (tocLinks.isNotEmpty) {
      int index = 1;
      for (final link in tocLinks) {
        final chUrl = _cleanUrl(link.attributes['href'] ?? '');
        final chTitle = link.text.trim();
        if (chTitle.isNotEmpty) {
          chapters.add(Chapter(
            id: chUrl.isNotEmpty ? chUrl : '$novelUrl#section-$index',
            novelId: novelUrl,
            title: chTitle,
            chapterNumber: index.toDouble(),
            url: chUrl.isNotEmpty ? chUrl : novelUrl,
          ));
          index++;
        }
      }
    }

    if (chapters.isEmpty) {
      chapters.add(Chapter(
        id: novelUrl,
        novelId: novelUrl,
        title: '$title - Full Reading View',
        chapterNumber: 1.0,
        url: novelUrl,
      ));
    }

    return chapters;
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final response = await _client.get(Uri.parse(chapterUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load VDoc.pub content from $chapterUrl (status ${response.statusCode})');
    }

    final document = html_parser.parse(response.body);
    final titleElem = document.querySelector('h1, .document-title');
    final title = titleElem?.text.trim() ?? 'Document Content';

    final List<String> rawParagraphs = [];

    // Extract text paragraphs from preview or document content
    final contentElem = document.querySelector('.preview, .document-content, .text-preview, article, .content');
    if (contentElem != null) {
      for (final p in contentElem.querySelectorAll('p, div.paragraph')) {
        final text = p.text.trim();
        if (text.length > 10) {
          rawParagraphs.add(text);
        }
      }
    }

    // Fallback to general page text if preview container was not matched
    if (rawParagraphs.isEmpty) {
      for (final p in document.querySelectorAll('p')) {
        final text = p.text.trim();
        if (text.length > 50 && !text.toLowerCase().contains('cookie') && !text.toLowerCase().contains('download')) {
          rawParagraphs.add(text);
        }
      }
    }

    final paragraphs = TextCleaner.cleanParagraphs(rawParagraphs);
    final rawText = paragraphs.join('\n\n');

    return ChapterContent(
      chapterId: chapterUrl,
      novelId: chapterUrl,
      title: title,
      rawText: rawText,
      paragraphs: paragraphs,
    );
  }
}
