import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for Hindi Samay (https://www.hindisamay.com).
/// Flagship portal by Mahatma Gandhi Antarrashtriya Hindi Vishwavidyalaya
/// featuring thousands of classic and modern Hindi novels, stories, memoirs, and essays.
class HindiSamayExtractor implements NovelSource {
  @override
  final String id = 'hindisamay';

  @override
  final String name = 'Hindi Samay (हिंदी समय)';

  @override
  final String baseUrl = 'https://www.hindisamay.com';

  @override
  final String lang = 'hi';

  @override
  final String iconUrl = 'https://www.hindisamay.com/favicon.ico';

  @override
  final int estimatedNovelCount = 10000;

  late final http.Client _client;

  HindiSamayExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'hi,en-US,en;q=0.9',
  };

  String _normalizeContentUrl(String url) {
    if (url.contains('content.aspx') || url.contains('.cspx')) return url;
    final idMatch = RegExp(r'(?:content/|contentDetail\.aspx\?id=)(\d+)').firstMatch(url);
    if (idMatch != null) {
      final workId = idMatch.group(1)!;
      final pageMatch = RegExp(r'(?:content/\d+/|pageno=)(\d+)').firstMatch(url);
      final pageno = pageMatch?.group(1) ?? '1';
      return '$baseUrl/contentDetail.aspx?id=$workId&pageno=$pageno&lang=hi';
    }
    return url;
  }

  Uri _parseSafeUri(String url) {
    var clean = url.trim();
    if (clean.startsWith('http://')) {
      clean = 'https://${clean.substring(7)}';
    }
    try {
      return Uri.parse(clean);
    } catch (_) {
      try {
        final schemeMatch = RegExp(r'^(https?://[^/]+)(.*)$').firstMatch(clean);
        if (schemeMatch != null) {
          final prefix = schemeMatch.group(1)!;
          final pathAndQuery = schemeMatch.group(2)!;
          final encodedPath = Uri.encodeFull(pathAndQuery);
          return Uri.parse('$prefix$encodedPath');
        }
      } catch (_) {}
      return Uri.parse(Uri.encodeFull(clean));
    }
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    const authorIds = [1152, 1275, 1182, 1355, 1157, 1262];
    final authorId = authorIds[(page - 1) % authorIds.length];

    final results = <Novel>[];
    if (page == 1) {
      final homeWorks = await _fetchWorksFromUrl('$baseUrl/default.aspx');
      results.addAll(homeWorks);
    }

    final authorWorks = await _fetchWorksFromUrl('$baseUrl/writer/writer_details_n.aspx?id=$authorId');
    results.addAll(authorWorks);

    final seen = <String>{};
    return results.where((n) => seen.add(n.sourceUrl)).toList();
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    const authorIds = [1182, 1355, 1157, 1262, 1539, 1246];
    final authorId = authorIds[(page - 1) % authorIds.length];

    final authorWorks = await _fetchWorksFromUrl('$baseUrl/writer/writer_details_n.aspx?id=$authorId');
    if (authorWorks.isNotEmpty) return authorWorks;

    return _fetchWorksFromUrl('$baseUrl/default.aspx');
  }

  static const Map<String, int> _knownWriters = {
    'प्रेमचंद': 1152,
    'गोदान': 1152,
    'गबन': 1152,
    'निर्मला': 1152,
    'कर्मभूमि': 1152,
    'रंगभूमि': 1152,
    'कफ़न': 1152,
    'कफन': 1152,
    'अज्ञेय': 1275,
    'मोहन राकेश': 1182,
    'कबीर': 1355,
    'हरिऔध': 1162,
    'भारतेंदु': 1157,
    'रामचंद्र शुक्ल': 1262,
    'सहजानंद': 1539,
    'निराला': 1340,
    'सूर्यकांत': 1340,
    'देवकीनंदन खत्री': 1167,
    'चंद्रकांता': 1167,
    'शरतचंद्र': 1246,
    'जयशंकर प्रसाद': 1176,
    'कामायनी': 1176,
    'रेणु': 1169,
    'फणीश्वरनाथ': 1169,
    'परसाई': 1174,
    'हरिशंकर': 1174,
    'भारती': 1249,
    'धर्मवीर': 1249,
    'भीष्म साहनी': 1155,
    'राहुल सांकृत्यायन': 1566,
    'सुदर्शन': 1345,
    'श्रीलाल शुक्ल': 1188,
  };

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final matchingWriters = _knownWriters.entries
        .where((e) => cleanQuery.contains(e.key.toLowerCase()) || e.key.toLowerCase().contains(cleanQuery))
        .map((e) => e.value)
        .toSet();

    final searchWorks = <Novel>[];
    for (final wid in matchingWriters) {
      final works = await _fetchWorksFromUrl('$baseUrl/writer/writer_details_n.aspx?id=$wid');
      searchWorks.addAll(works);
    }

    if (searchWorks.isNotEmpty) {
      return searchWorks;
    }

    final popular = await getPopular(page: 1);
    final latest = await getLatest(page: 1);

    final combined = <String, Novel>{};
    for (final n in [...searchWorks, ...popular, ...latest]) {
      combined[n.sourceUrl] = n;
    }

    return combined.values.where((n) {
      return n.title.toLowerCase().contains(cleanQuery) ||
          n.author.toLowerCase().contains(cleanQuery) ||
          n.description.toLowerCase().contains(cleanQuery) ||
          cleanQuery.contains(n.title.toLowerCase()) ||
          cleanQuery.contains(n.author.toLowerCase());
    }).toList();
  }

  Future<List<Novel>> _fetchWorksFromUrl(String url) async {
    try {
      final response = await _client.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final pageWriter = doc.querySelector('h1')?.text.trim() ?? '';
      final List<Novel> novels = [];
      final seenUrls = <String>{};

      final anchors = doc.querySelectorAll('a[href*=".cspx"], a[href*="/content/"], a[href*="contentDetail.aspx"]');
      for (final a in anchors) {
        final href = a.attributes['href'] ?? '';
        final text = a.text.trim();
        if (text.isEmpty || href.isEmpty || text.length < 2) continue;
        if (href.contains('content.aspx')) continue;
        // Strictly exclude writer/author biography listings from being extracted as empty novels
        if (href.contains('/writer/') || href.contains('writer_details') || href.contains('writer/')) continue;
        if (text.contains('क्लिक करें') || text.contains('मुखपृष्ठ') || text.contains('आगे')) continue;

        final cleanText = text.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
        final lowerText = cleanText.toLowerCase();
        const categoryNames = {
          'उपन्यास', 'कहानियाँ', 'कहानियां', 'कविता', 'नाटक', 'लेख', 'निबंध',
          'आलोचना', 'संस्मरण', 'जीवनी', 'यात्रा वृतांत', 'व्यंग्य', 'बाल साहित्य',
          'डायरी', 'साक्षात्कार', 'हिंदी उपन्यास', 'hindi novel', 'novel', 'stories'
        };
        if (categoryNames.contains(cleanText) || categoryNames.contains(lowerText)) {
          continue;
        }

        String rawUrl;
        if (href.startsWith('//')) {
          rawUrl = 'https:$href';
        } else if (href.startsWith('http://') || href.startsWith('https://')) {
          rawUrl = href;
        } else {
          rawUrl = '$baseUrl/${href.replaceFirst(RegExp(r'^/+'), '')}';
        }

        final normalizedUrl = _normalizeContentUrl(rawUrl);
        if (!seenUrls.add(normalizedUrl)) continue;

        var title = text.replaceAll('(ई-पुस्तक)', '').trim();
        var author = pageWriter.isNotEmpty ? pageWriter : 'हिंदी साहित्यकार';

        try {
          final decoded = Uri.decodeFull(rawUrl);
          if (decoded.contains('--')) {
            final fileName = decoded.split('/').last.replaceAll('.cspx', '').trim();
            final parts = fileName.split('--');
            if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
              author = parts[0].trim();
            }
          }
        } catch (_) {}

        if (title.contains('-')) {
          final parts = title.split('-').map((s) => s.trim()).toList();
          if (parts.length >= 3) {
            author = parts[0];
            title = parts.sublist(2).join(' - ');
          } else if (parts.length == 2) {
            author = parts[0];
            title = parts[1];
          }
        }

        novels.add(Novel(
          id: '${id}_${normalizedUrl.hashCode.abs()}',
          sourceId: id,
          title: title,
          author: author,
          description: 'हिंदी समय पर उपलब्ध प्रसिद्ध साहित्यिक रचना।',
          coverUrl: 'https://www.hindisamay.com/images/logo.png',
          genres: const ['Hindi', 'Literature', 'Upanyas'],
          status: 'COMPLETED',
          sourceUrl: normalizedUrl,
        ));
      }

      return novels;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final cleanUrl = _normalizeContentUrl(novelUrl);
    try {
      final response = await _client.get(_parseSafeUri(cleanUrl), headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Failed to load novel details (HTTP ${response.statusCode})');
      }

      final doc = html_parser.parse(response.body);

      // 1. Check ASP.NET labels
      final lblTitle = doc.querySelector('#ContentPlaceHolder1_lblTitle')?.text.trim();
      final lblAuthor = doc.querySelector('#ContentPlaceHolder1_lblAuthor')?.text.trim();
      final lblType = doc.querySelector('#ContentPlaceHolder1_lblContentType')?.text.trim();
      final lblContent = doc.querySelector('#ContentPlaceHolder1_lblContentText')?.text.trim() ?? '';

      var title = (lblTitle != null && lblTitle.isNotEmpty) ? lblTitle : '';
      var author = (lblAuthor != null && lblAuthor.isNotEmpty) ? lblAuthor : '';

      if (title.isEmpty) {
        final rawDocTitle = doc.querySelector('title')?.text.trim() ?? '';
        final cleanDocTitle = rawDocTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleanDocTitle.contains('-')) {
          final parts = cleanDocTitle.split('-').map((s) => s.trim()).toList();
          author = parts[0];
          title = parts.sublist(1).join(' - ');
        } else if (cleanDocTitle.isNotEmpty && !cleanDocTitle.contains('Hindi Samay')) {
          final parts = cleanDocTitle.split(' ');
          if (parts.length >= 2) {
            author = parts[0];
            title = parts.sublist(1).join(' ');
          } else {
            title = cleanDocTitle;
          }
        }
      }

      if (title.isEmpty || title == 'उपन्यास' || title.toLowerCase() == 'hindi novel') {
        title = 'हिंदी रचना';
      }
      if (author.isEmpty) {
        author = 'हिंदी साहित्यकार';
      }

      String snippet = '';
      if (lblContent.isNotEmpty) {
        snippet = lblContent.length > 250 ? '${lblContent.substring(0, 250)}...' : lblContent;
      } else if (lblType != null && lblType.isNotEmpty) {
        snippet = 'प्रकार: $lblType | हिंदी समय डिजिटल संग्रह';
      } else {
        snippet = 'हिंदी समय डिजिटल साहित्य संग्रह।';
      }

      final genres = <String>['Hindi', 'Literature'];
      if (lblType != null && lblType.isNotEmpty) {
        genres.add(lblType);
      }

      return Novel(
        id: '${id}_${cleanUrl.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: snippet,
        coverUrl: 'https://www.hindisamay.com/images/logo.png',
        genres: genres,
        status: 'COMPLETED',
        sourceUrl: cleanUrl,
      );
    } catch (_) {
      return Novel(
        id: '${id}_${cleanUrl.hashCode.abs()}',
        sourceId: id,
        title: 'हिंदी रचना',
        author: 'हिंदी साहित्यकार',
        description: 'हिंदी समय डिजिटल साहित्य संग्रह।',
        coverUrl: 'https://www.hindisamay.com/images/logo.png',
        sourceUrl: cleanUrl,
      );
    }
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final cleanUrl = _normalizeContentUrl(novelUrl);
    try {
      final response = await _client.get(_parseSafeUri(cleanUrl), headers: _headers);
      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final List<Chapter> chapters = [];
      final seenUrls = <String>{};
      final novelId = '${id}_${cleanUrl.hashCode.abs()}';

      final idMatch = RegExp(r'(?:content/|id=)(\d+)').firstMatch(cleanUrl);
      final workId = idMatch?.group(1) ?? '';

      // Parse chapters from #ContentPlaceHolder1_lblToc
      final tocContainer = doc.querySelector('#ContentPlaceHolder1_lblToc');
      if (tocContainer != null) {
        final anchors = tocContainer.querySelectorAll('a');
        for (final a in anchors) {
          final href = a.attributes['href'] ?? '';
          final text = a.text.trim();
          if (text.isEmpty || href.isEmpty) continue;

          final pageMatch = RegExp(r'(?:content/\d+/|pageno=)(\d+)').firstMatch(href);
          final pageNo = pageMatch?.group(1) ?? '${chapters.length + 1}';
          final chapterUrl = workId.isNotEmpty
              ? '$baseUrl/contentDetail.aspx?id=$workId&pageno=$pageNo&lang=hi'
              : (href.startsWith('http') ? href : '$baseUrl/$href');

          if (!seenUrls.add(chapterUrl)) continue;

          final numVal = double.tryParse(pageNo) ?? (chapters.length + 1).toDouble();
          chapters.add(Chapter(
            id: '${id}_${chapterUrl.hashCode.abs()}',
            novelId: novelId,
            title: text,
            url: chapterUrl,
            chapterNumber: numVal,
          ));
        }
      }

      // If no TOC links, check for any contentDetail pagination or single work
      if (chapters.isEmpty) {
        final title = doc.querySelector('#ContentPlaceHolder1_lblTitle')?.text.trim() ?? 'पूर्ण रचना';
        chapters.add(Chapter(
          id: '${id}_${cleanUrl.hashCode.abs()}_1',
          novelId: novelId,
          title: title.isNotEmpty ? title : 'पूर्ण रचना (Full Work)',
          url: cleanUrl,
          chapterNumber: 1.0,
        ));
      }

      onBatchLoaded?.call(chapters);
      return chapters;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final cleanUrl = _normalizeContentUrl(chapterUrl);
    final response = await _client.get(_parseSafeUri(cleanUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter content from $cleanUrl (HTTP ${response.statusCode})');
    }

    final doc = html_parser.parse(response.body);
    final lblTitle = doc.querySelector('#ContentPlaceHolder1_lblTitle')?.text.trim();
    final title = (lblTitle != null && lblTitle.isNotEmpty)
        ? lblTitle
        : (doc.querySelector('title')?.text.trim() ?? 'Hindi Samay Chapter');

    final paragraphs = <String>[];
    final contentElem = doc.querySelector('#ContentPlaceHolder1_lblContentText');

    if (contentElem != null) {
      // Split text by lines and <br>
      final rawHtml = contentElem.innerHtml;
      final textWithBreaks = rawHtml.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      final plainText = html_parser.parse(textWithBreaks).body?.text ?? contentElem.text;

      for (final line in plainText.split('\n')) {
        final t = line.trim();
        if (t.length > 1 && !t.startsWith('अनुक्रम') && !t.contains('ContentPlaceHolder1')) {
          paragraphs.add(t);
        }
      }
    }

    if (paragraphs.isEmpty) {
      final allP = doc.querySelectorAll('p');
      for (final p in allP) {
        final text = p.text.trim();
        if (text.length > 20 && !text.startsWith('अनुक्रम')) {
          paragraphs.add(text);
        }
      }
    }

    if (paragraphs.isEmpty) {
      paragraphs.add('सामग्री लोड करने में असमर्थ।');
    }

    final workIdMatch = RegExp(r'(?:content/|contentDetail\.aspx\?id=)(\d+)').firstMatch(cleanUrl);
    final baseNovelUrl = workIdMatch != null
        ? '$baseUrl/contentDetail.aspx?id=${workIdMatch.group(1)}&pageno=1&lang=hi'
        : cleanUrl;
    final parentNovelId = '${id}_${baseNovelUrl.hashCode.abs()}';

    return ChapterContent(
      chapterId: '${id}_${cleanUrl.hashCode.abs()}',
      novelId: parentNovelId,
      title: title,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }
}
