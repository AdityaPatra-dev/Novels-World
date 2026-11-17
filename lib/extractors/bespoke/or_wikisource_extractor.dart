import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/utils/http_client_factory.dart';
import '../novel_source.dart';

/// Bespoke extractor for Odia Wikisource (https://or.wikisource.org).
/// The open digital library containing canonical classical Odia literature,
/// historical chronicles, and masterpieces (Fakir Mohan Senapati, Radhanath Ray,
/// Gangadhar Meher, Sarala Dasa, Upendra Bhanja).
class OdiaWikisourceExtractor implements NovelSource {
  @override
  final String id = 'or_wikisource';

  @override
  final String name = 'Odia Wikisource (ଓଡ଼ିଆ ଉଇକିପାଠାଗାର)';

  @override
  final String baseUrl = 'https://or.wikisource.org';

  @override
  final String lang = 'or';

  @override
  final String iconUrl = 'https://or.wikisource.org/favicon.ico';

  @override
  final int estimatedNovelCount = 5000;

  late final http.Client _client;

  OdiaWikisourceExtractor({http.Client? client}) {
    _client = client ?? createPlatformHttpClient();
  }

  Map<String, String> get _headers => {
    'User-Agent': 'NovelsWorldApp/2.0 (https://github.com/adityapatra/Novels-World; contact: app@novelsworld.org)',
    'Accept': 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'or,en-US,en;q=0.9',
  };

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    const popularQueries = [
      'ଛମାଣ ଆଠଗୁଣ୍ଠ',
      'ତପସ୍ଵିନୀ',
      'ଅର୍ଘ୍ୟଥାଳୀ',
      'ଚିଲିକା',
      'ଦରବାର',
      'ମାଟିର ମଣିଷ',
    ];
    final query = popularQueries[(page - 1) % popularQueries.length];
    return search(query, page: 1);
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    const latestQueries = [
      'ଉପନ୍ୟାସ',
      'ଗଳ୍ପ',
      'କଥାଲହରୀ',
      'କବିତା',
      'ପ୍ରବନ୍ଧ',
    ];
    final query = latestQueries[(page - 1) % latestQueries.length];
    return search(query, page: 1);
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final offset = (page - 1) * 25;
    // Normalize Odia Va variants (ୱ U+0B71 vs ଵ U+0B35) for search resiliency
    final searchTerms = <String>[cleanQuery];
    if (cleanQuery.contains('\u0B71')) {
      searchTerms.add(cleanQuery.replaceAll('\u0B71', '\u0B35'));
    } else if (cleanQuery.contains('\u0B35')) {
      searchTerms.add(cleanQuery.replaceAll('\u0B35', '\u0B71'));
    }

    final List<Novel> combined = [];
    final seenIds = <String>{};

    for (final term in searchTerms) {
      final encodedQuery = Uri.encodeComponent(term);
      final url = '$baseUrl/w/api.php?action=query&list=search&srsearch=$encodedQuery&srlimit=25&sroffset=$offset&srnamespace=0&format=json';

      try {
        final response = await _client.get(Uri.parse(url), headers: _headers);
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final searchResults = data['query']?['search'] as List<dynamic>? ?? [];

        final parsed = parseSearchResults(searchResults);
        for (final n in parsed) {
          if (seenIds.add(n.id)) {
            combined.add(n);
          }
        }
      } catch (_) {}
    }

    return combined;
  }

  List<Novel> parseSearchResults(List<dynamic> results) {
    final List<Novel> novels = [];
    final seenRootTitles = <String>{};

    for (final item in results) {
      final rawTitle = item['title']?.toString() ?? '';
      if (rawTitle.isEmpty) continue;

      // Ignore MediaWiki internal, author index, and user namespaces
      if (rawTitle.startsWith('ଶ୍ରେଣୀ:') ||
          rawTitle.startsWith('ବ୍ୟବହାରକାରୀ:') ||
          rawTitle.startsWith('ଉଇକିପାଠାଗାର:') ||
          rawTitle.startsWith('ମିଡ଼ିଆ:') ||
          rawTitle.startsWith('ମିଡ଼ିଆଉଇକି:') ||
          rawTitle.startsWith('ଲେଖକ:') ||
          rawTitle.startsWith('ପୃଷ୍ଠା:') ||
          rawTitle.startsWith('ସୂଚୀ:') ||
          rawTitle.startsWith('ଫାଇଲ:') ||
          rawTitle.startsWith('Special:') ||
          rawTitle.startsWith('Help:')) {
        continue;
      }

      // Group subchapters under their root work title to prevent duplicate novel cards
      final rootTitle = rawTitle.contains('/') ? rawTitle.split('/').first.trim() : rawTitle.trim();
      if (!seenRootTitles.add(rootTitle)) {
        continue;
      }

      final snippetRaw = item['snippet']?.toString() ?? '';
      final snippet = snippetRaw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

      final pageId = item['pageid']?.toString() ?? '';
      final novelUrl = rawTitle.contains('/')
          ? '$baseUrl/wiki/${Uri.encodeComponent(rootTitle.replaceAll(' ', '_'))}'
          : (pageId.isNotEmpty
              ? '$baseUrl/?curid=$pageId'
              : '$baseUrl/wiki/${Uri.encodeComponent(rootTitle.replaceAll(' ', '_'))}');

      novels.add(Novel(
        id: '${id}_${rootTitle.hashCode.abs()}',
        sourceId: id,
        title: rootTitle,
        author: 'ଓଡ଼ିଆ କ୍ଲାସିକ (Odia Classic)',
        description: snippet.isNotEmpty ? snippet : 'ଓଡ଼ିଆ ଉଇକିପାଠାଗାର ସାହିତ୍ୟ କୃତି।',
        coverUrl: 'https://or.wikisource.org/static/images/project-logos/orwikisource.png',
        genres: const ['Odia', 'Classics', 'Sahitya'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      ));
    }

    return novels;
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    try {
      final pageId = _extractPageIdFromUrl(novelUrl);
      final pageTitle = _extractPageTitleFromUrl(novelUrl);

      final apiUrl = pageId.isNotEmpty
          ? '$baseUrl/w/api.php?action=parse&pageid=$pageId&format=json&prop=text|properties'
          : '$baseUrl/w/api.php?action=parse&page=${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}&format=json&prop=text|properties';

      final response = await _client.get(Uri.parse(apiUrl), headers: _headers);

      String title = pageTitle;
      String author = 'ଓଡ଼ିଆ କ୍ଲାସିକ (Odia Classic)';
      String description = '';
      String coverUrl = 'https://or.wikisource.org/static/images/project-logos/orwikisource.png';

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parseData = data['parse'];
        if (parseData != null) {
          title = parseData['title']?.toString() ?? pageTitle;
          final htmlText = parseData['text']?['*']?.toString() ?? '';
          final doc = html_parser.parse(htmlText);

          final headerTitle = doc.querySelector('#header_title_text')?.text.trim();
          final headerAuthor = doc.querySelector('#header_author_text')?.text.trim();
          final authorLink = doc.querySelector('a[href*="/wiki/%E0%AC%B2%E0%AD%87%E0%AC%96%E0%AC%95:"], a[href*="ଲେଖକ:"]')?.text.trim();

          if (headerTitle != null && headerTitle.isNotEmpty) {
            title = headerTitle;
          }
          if (headerAuthor != null && headerAuthor.isNotEmpty) {
            author = headerAuthor;
          } else if (authorLink != null && authorLink.isNotEmpty) {
            author = authorLink;
          }

          final img = doc.querySelector('.infobox img, #mw-content-text img, .thumbimage, img');
          if (img != null) {
            final src = img.attributes['src'] ?? '';
            if (src.isNotEmpty && !src.contains('wikimedia-button') && !src.contains('poweredby')) {
              coverUrl = src.startsWith('//') ? 'https:$src' : (src.startsWith('http') ? src : '$baseUrl$src');
            }
          }

          // Extract first narrative description
          for (final p in doc.querySelectorAll('p')) {
            final t = p.text.trim();
            if (t.length > 25 && !t.contains('ଲେଖକ/କବି')) {
              description = t;
              break;
            }
          }

          if (description.isEmpty) {
            description = '$title - $author ଙ୍କ ଦ୍ୱାରା ରଚିତ ଓଡ଼ିଆ କ୍ଲାସିକ ସାହିତ୍ୟ କୃତି।';
          }
        }
      }

      return Novel(
        id: '${id}_${title.hashCode.abs()}',
        sourceId: id,
        title: title,
        author: author,
        description: description,
        coverUrl: coverUrl,
        genres: const ['Odia', 'Classics', 'Sahitya'],
        status: 'COMPLETED',
        sourceUrl: novelUrl,
      );
    } catch (_) {
      final fallbackTitle = _extractPageTitleFromUrl(novelUrl);
      return Novel(
        id: '${id}_${fallbackTitle.hashCode.abs()}',
        sourceId: id,
        title: fallbackTitle.isNotEmpty ? fallbackTitle : 'Odia Literature',
        author: 'ଓଡ଼ିଆ ଲେଖକ',
        coverUrl: 'https://or.wikisource.org/static/images/project-logos/orwikisource.png',
        sourceUrl: novelUrl,
      );
    }
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    try {
      final pageId = _extractPageIdFromUrl(novelUrl);
      final pageTitle = _extractPageTitleFromUrl(novelUrl);
      final novelId = '${id}_${pageTitle.hashCode.abs()}';

      final apiUrl = pageId.isNotEmpty
          ? '$baseUrl/w/api.php?action=parse&pageid=$pageId&format=json&prop=text'
          : '$baseUrl/w/api.php?action=parse&page=${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}&format=json&prop=text';

      final response = await _client.get(Uri.parse(apiUrl), headers: _headers);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final html = data['parse']?['text']?['*']?.toString() ?? '';
      if (html.isEmpty) return [];

      final doc = html_parser.parse(html);

      // Clean out headers, author infoboxes, and navigation elements before parsing chapters
      for (final bad in doc.querySelectorAll(
        '#headertemplate, .headertemplate, .ws-noexport, #ws-data, .catlinks, .printfooter, .mw-jump-link, .thumb, figure, #toc',
      )) {
        bad.remove();
      }

      final List<Chapter> chapters = [];
      final seenUrls = <String>{};

      const ignoredPrefixes = [
        'ଶ୍ରେଣୀ:',
        'ବ୍ୟବହାରକାରୀ:',
        'ଉଇକିପାଠାଗାର:',
        'ଲେଖକ:',
        'ପୃଷ୍ଠା:',
        'ସୂଚୀ:',
        'ଫାଇଲ:',
        'Help:',
        'Special:',
        'MediaWiki:',
        'Wikipedia:',
        'portal:',
      ];

      // 1. Look for chapters in ordered list (<ol><li>) or subpage links
      final links = doc.querySelectorAll('ol li a, ul li a, p a[href*="/wiki/"], a[href*="/wiki/"]');
      for (final a in links) {
        final text = a.text.trim();
        final href = a.attributes['href'] ?? '';
        if (text.isEmpty || href.isEmpty) continue;

        final decodedHref = Uri.decodeComponent(href);

        // Filter out redlinks / non-existent stub pages
        if (a.classes.contains('new') || href.contains('redlink=1')) {
          continue;
        }

        // Filter out non-chapter namespaces
        if (ignoredPrefixes.any((p) => decodedHref.contains(p))) {
          continue;
        }

        // Filter out metadata and navigation links
        if (text.startsWith('(') && text.endsWith(')')) continue;
        if (text.contains('ରଚନାଗୁଡ଼ିକ ମୋଟା ଅକ୍ଷରରେ') ||
            text.contains('ପ୍ରମୁଖ ରଚନା') ||
            text.contains('ସମ୍ପାଦନା') ||
            text.contains('sister projects') ||
            text.contains('Wikipedia article') ||
            text.contains('Author Index')) {
          continue;
        }

        final chapterUrl = href.startsWith('http') ? href : '$baseUrl$href';
        if (chapterUrl == novelUrl || !seenUrls.add(chapterUrl)) continue;

        chapters.add(Chapter(
          id: '${id}_${chapterUrl.hashCode.abs()}',
          novelId: novelId,
          title: text,
          url: chapterUrl,
          chapterNumber: (chapters.length + 1).toDouble(),
        ));
      }

      // 2. If no chapters were found from page HTML, query MediaWiki subpages API
      if (chapters.isEmpty) {
        final subpages = await _queryMediaWikiSubpages(pageTitle);
        for (final sp in subpages) {
          final spTitle = sp['title']?.toString() ?? '';
          if (spTitle.isEmpty) continue;

          final chapterTitle = spTitle.contains('/') ? spTitle.split('/').last.trim() : spTitle;
          final chapterUrl = '$baseUrl/wiki/${Uri.encodeComponent(spTitle.replaceAll(' ', '_'))}';
          if (!seenUrls.add(chapterUrl)) continue;

          chapters.add(Chapter(
            id: '${id}_${chapterUrl.hashCode.abs()}',
            novelId: novelId,
            title: chapterTitle,
            url: chapterUrl,
            chapterNumber: (chapters.length + 1).toDouble(),
          ));
        }
      }

      // 3. If still no chapters, the page itself is a complete standalone work or poem!
      if (chapters.isEmpty) {
        final mainTitle = doc.querySelector('#header_title_text')?.text.trim() ?? pageTitle;
        chapters.add(Chapter(
          id: '${id}_${novelUrl.hashCode.abs()}',
          novelId: novelId,
          title: mainTitle.isNotEmpty ? mainTitle : 'ସମ୍ପୂର୍ଣ୍ଣ ରଚନା (Full Work)',
          url: novelUrl,
          chapterNumber: 1.0,
        ));
      }

      onBatchLoaded?.call(chapters);
      return chapters;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _queryMediaWikiSubpages(String pageTitle) async {
    final clean = pageTitle.trim();
    if (clean.isEmpty) return [];

    final variants = <String>[clean];
    if (clean.contains('\u0B71')) {
      variants.add(clean.replaceAll('\u0B71', '\u0B35'));
    } else if (clean.contains('\u0B35')) {
      variants.add(clean.replaceAll('\u0B35', '\u0B71'));
    }

    for (final v in variants) {
      try {
        final encodedPrefix = Uri.encodeComponent('$v/');
        final url = '$baseUrl/w/api.php?action=query&list=allpages&apprefix=$encodedPrefix&aplimit=100&format=json';
        final resp = await _client.get(Uri.parse(url), headers: _headers);
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final list = (data['query']?['allpages'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList();
          if (list != null && list.isNotEmpty) {
            return list;
          }
        }
      } catch (_) {}
    }

    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    final pageId = _extractPageIdFromUrl(chapterUrl);
    final pageTitle = _extractPageTitleFromUrl(chapterUrl);

    final apiUrl = pageId.isNotEmpty
        ? '$baseUrl/w/api.php?action=parse&pageid=$pageId&format=json&prop=text'
        : '$baseUrl/w/api.php?action=parse&page=${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}&format=json&prop=text';

    final response = await _client.get(Uri.parse(apiUrl), headers: _headers);

    String html = '';
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      html = data['parse']?['text']?['*']?.toString() ?? '';
    }

    if (html.isEmpty) {
      final directResp = await _client.get(Uri.parse(chapterUrl), headers: _headers);
      if (directResp.statusCode == 200) {
        html = directResp.body;
      }
    }

    if (html.isEmpty) {
      return ChapterContent(
        chapterId: '${id}_${chapterUrl.hashCode.abs()}',
        novelId: '${id}_${pageTitle.hashCode.abs()}',
        title: pageTitle,
        rawText: '$pageTitle\n\nଏହି ଅଧ୍ୟାୟର ପାଠ୍ୟ ଉଇକିପାଠାଗାରରେ ଏପର୍ଯ୍ୟନ୍ତ ସମ୍ପୂର୍ଣ୍ଣ ହୋଇନାହିଁ।',
        paragraphs: [
          pageTitle,
          'ଏହି ଅଧ୍ୟାୟର ପାଠ୍ୟ ଉଇକିପାଠାଗାରରେ ଏପର୍ଯ୍ୟନ୍ତ ସମ୍ପୂର୍ଣ୍ଣ ହୋଇନାହିଁ।',
        ],
      );
    }

    final doc = html_parser.parse(html);

    // Replace <br> tags with newlines so line breaks in poems are preserved
    for (final br in doc.querySelectorAll('br')) {
      br.replaceWith(dom.Text('\n'));
    }

    // Remove headers, navbars, metadata, and category footers
    for (final bad in doc.querySelectorAll(
      'script, style, nav, table, .catlinks, #toc, .ws-header, .printfooter, .mw-jump-link, #headertemplate, .headertemplate, .ws-noexport, #ws-data, .pagenum, .ws-pagenum',
    )) {
      bad.remove();
    }

    final List<String> paragraphs = [];

    // 1. Extract from <div class="poem"> blocks if present
    final poemElements = doc.querySelectorAll('div.poem');
    if (poemElements.isNotEmpty) {
      for (final poem in poemElements) {
        final text = poem.text.trim();
        if (text.isEmpty) continue;

        // Split poem by double newlines into distinct stanzas
        final stanzas = text.split(RegExp(r'\n\s*\n+'));
        for (final stanza in stanzas) {
          final cleanStanza = stanza
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty && !line.startsWith('•••'))
              .join('\n');
          if (cleanStanza.length >= 3) {
            paragraphs.add(cleanStanza);
          }
        }
      }
    }

    // 2. If no poem blocks, extract standard paragraphs
    if (paragraphs.isEmpty) {
      final pElements = doc.querySelectorAll('p');
      for (final p in pElements) {
        final t = p.text.trim();
        if (t.length >= 2 &&
            !t.startsWith('(ପ୍ରମୁଖ ରଚନା') &&
            !t.startsWith('•••') &&
            !t.contains('ଲେଖକ/କବି')) {
          paragraphs.add(t);
        }
      }
    }

    // 3. Fallback: extract line-by-line from main content container
    if (paragraphs.isEmpty) {
      final container = doc.querySelector('#mw-content-text') ?? doc.body;
      if (container != null) {
        final lines = container.text.split('\n');
        for (final line in lines) {
          final t = line.trim();
          if (t.length >= 5 &&
              !t.startsWith('(ପ୍ରମୁଖ ରଚନା') &&
              !t.startsWith('•••')) {
            paragraphs.add(t);
          }
        }
      }
    }

    final displayTitle = doc.querySelector('#header_title_text')?.text.trim() ?? pageTitle;

    return ChapterContent(
      chapterId: '${id}_${chapterUrl.hashCode.abs()}',
      novelId: '${id}_${pageTitle.hashCode.abs()}',
      title: displayTitle,
      rawText: paragraphs.join('\n\n'),
      paragraphs: paragraphs,
    );
  }

  String _extractPageIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final curid = uri.queryParameters['curid'];
      if (curid != null && curid.isNotEmpty) {
        return curid;
      }
    } catch (_) {}
    return '';
  }

  String _extractPageTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.path.startsWith('/wiki/')) {
        return Uri.decodeComponent(uri.path.replaceFirst('/wiki/', '')).replaceAll('_', ' ');
      }
      final titleParam = uri.queryParameters['title'];
      if (titleParam != null && titleParam.isNotEmpty) {
        return Uri.decodeComponent(titleParam).replaceAll('_', ' ');
      }
    } catch (_) {}
    return url;
  }
}
