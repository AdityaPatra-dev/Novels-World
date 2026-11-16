import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';

class SourceAuditResult {
  final String id;
  final String name;
  final String lang;
  final bool isFullBookSource;
  
  // Popular test
  bool popularSuccess = false;
  int popularCount = 0;
  String popularError = '';

  // Latest test
  bool latestSuccess = false;
  int latestCount = 0;
  String latestError = '';

  // Search test
  bool searchSuccess = false;
  int searchCount = 0;
  String searchError = '';

  // Detail test
  bool detailSuccess = false;
  String detailTitle = '';
  String detailAuthor = '';
  String detailCover = '';
  bool coverValid = false;
  bool genericTitleDetected = false;
  String detailError = '';

  // Chapters test
  bool chaptersSuccess = false;
  int chaptersCount = 0;
  String chaptersError = '';

  // Content test
  bool contentSuccess = false;
  int paragraphCount = 0;
  String contentError = '';

  // Flaws detected
  final List<String> flaws = [];

  SourceAuditResult({
    required this.id,
    required this.name,
    required this.lang,
    required this.isFullBookSource,
  });
}

void main() {
  test('Deep and true audit of newly added and bespoke sources', () async {
    final targets = <String>[
      // Indic Sources
      'hindisamay',
      'epustakalay',
      'kavitakosh',
      'gadyakosh',
      'odiabibhaba',
      'or_wikisource',
      // Book Repositories
      'gutenberg',
      'openlibrary',
      'internet_archive',
      'libgen',
      'standard_ebooks',
      'oceanofpdf',
      'vdocpub',
      'fadedpage',
      'allfreenovel',
      // Bespoke Fiction & Magazines
      'novelcool',
      'roliascan',
      'asurascans',
      'royalroad',
      'scribblehub',
      'woopread',
      'relibrary',
      'clarkesworld',
      'lightspeed',
      'eastoftheweb',
      'uncannymagazine',
      'strangehorizons',
      // International New Sources
      'kakuyomu',
      'kolnovel',
      'riwyat',
      'hizomanga',
      'turkcelightnovels',
      'vanovel',
      'webnoveloku',
      'novellucky',
      'novelpdf',
      'anslid',
    ];

    print('================================================================');
    print('🔍 EXECUTING DEEP & UNBIASED SOURCE AUDIT ON ${targets.length} SOURCES');
    print('================================================================');

    final results = <SourceAuditResult>[];

    for (final sourceId in targets) {
      final source = SourceRegistry.getSource(sourceId);
      if (source == null) {
        print('⚠️ Source "$sourceId" not registered in SourceRegistry!');
        continue;
      }

      final audit = SourceAuditResult(
        id: source.id,
        name: source.name,
        lang: source.lang,
        isFullBookSource: false,
      );

      print('\nAuditing [${source.id}] ${source.name} (${source.lang})...');

      // 1. POPULAR TEST
      List<Novel> popularNovels = [];
      try {
        popularNovels = await source.getPopular(page: 1).timeout(const Duration(seconds: 10));
        audit.popularCount = popularNovels.length;
        audit.popularSuccess = popularNovels.isNotEmpty;
        if (popularNovels.isEmpty) {
          audit.flaws.add('getPopular(page: 1) returned 0 novels');
        }
      } catch (e) {
        audit.popularError = e.toString();
        audit.flaws.add('getPopular threw: ${e.toString().split('\n').first}');
      }

      // 2. LATEST TEST
      try {
        final latestNovels = await source.getLatest(page: 1).timeout(const Duration(seconds: 10));
        audit.latestCount = latestNovels.length;
        audit.latestSuccess = latestNovels.isNotEmpty;
        if (latestNovels.isEmpty && audit.popularSuccess) {
          audit.flaws.add('getLatest(page: 1) returned 0 novels');
        }
      } catch (e) {
        audit.latestError = e.toString();
        audit.flaws.add('getLatest threw: ${e.toString().split('\n').first}');
      }

      // 3. SEARCH TEST
      Novel? sampleNovel = popularNovels.isNotEmpty ? popularNovels.first : null;
      String searchQuery = 'the';
      if (source.lang == 'hi') searchQuery = 'प्रेमचंद';
      if (source.lang == 'or') searchQuery = 'ସାହିତ୍ୟ';
      if (source.lang == 'ar') searchQuery = 'رواية';
      if (source.lang == 'ja') searchQuery = 'の';
      if (source.lang == 'tr') searchQuery = 'bir';
      if (source.lang == 'th') searchQuery = 'รัก';
      if (source.lang == 'es') searchQuery = 'el';

      try {
        final searchResults = await source.search(searchQuery, page: 1).timeout(const Duration(seconds: 10));
        audit.searchCount = searchResults.length;
        audit.searchSuccess = searchResults.isNotEmpty;
        if (sampleNovel == null && searchResults.isNotEmpty) {
          sampleNovel = searchResults.first;
        }
        if (searchResults.isEmpty) {
          audit.flaws.add('search("$searchQuery") returned 0 results');
        }
      } catch (e) {
        audit.searchError = e.toString();
        audit.flaws.add('search("$searchQuery") threw: ${e.toString().split('\n').first}');
      }

      // 4. NOVEL DETAILS & COVER TEST
      if (sampleNovel != null) {
        try {
          final detail = await source.getNovelDetails(sampleNovel.sourceUrl).timeout(const Duration(seconds: 10));
          audit.detailSuccess = true;
          audit.detailTitle = detail.title;
          audit.detailAuthor = detail.author;
          audit.detailCover = detail.coverUrl;

          // Check generic/placeholder titles
          final lowerTitle = detail.title.toLowerCase();
          if (lowerTitle == 'hindi novel' ||
              lowerTitle == 'odia literature' ||
              lowerTitle == 'untitled' ||
              lowerTitle == 'unknown' ||
              lowerTitle.isEmpty) {
            audit.genericTitleDetected = true;
            audit.flaws.add('Generic title detected: "${detail.title}"');
          }

          // Check cover url
          if (detail.coverUrl.isEmpty) {
            audit.flaws.add('Empty cover URL');
          } else if (detail.coverUrl.startsWith('//')) {
            audit.flaws.add('Protocol-relative cover URL ("//") not normalized');
          } else if (!detail.coverUrl.startsWith('http')) {
            audit.flaws.add('Malformed cover URL: ${detail.coverUrl}');
          } else {
            audit.coverValid = true;
          }

          // Check author
          if (detail.author.isEmpty || detail.author == 'Unknown Author' || detail.author == 'Unknown') {
            audit.flaws.add('Generic or missing author: "${detail.author}"');
          }

          // Check full book format
          if (detail.isFullBook) {
            if (detail.bookDownloadUrl == null || detail.bookDownloadUrl!.isEmpty) {
              audit.flaws.add('isFullBook is true but bookDownloadUrl is null/empty');
            }
            if (detail.bookFormat == null || detail.bookFormat!.isEmpty) {
              audit.flaws.add('isFullBook is true but bookFormat is null/empty');
            }
          }

          // 5. CHAPTER LIST TEST
          List<Chapter> chapters = [];
          try {
            chapters = await source.getChapterList(sampleNovel.sourceUrl).timeout(const Duration(seconds: 10));
            audit.chaptersCount = chapters.length;
            audit.chaptersSuccess = chapters.isNotEmpty;
            if (chapters.isEmpty) {
              audit.flaws.add('getChapterList returned 0 chapters');
            }
          } catch (e) {
            audit.chaptersError = e.toString();
            audit.flaws.add('getChapterList threw: ${e.toString().split('\n').first}');
          }

          // 6. CHAPTER CONTENT TEST
          if (chapters.isNotEmpty) {
            final firstChap = chapters.first;
            try {
              final content = await source.getChapterContent(firstChap.url).timeout(const Duration(seconds: 10));
              audit.paragraphCount = content.paragraphs.length;
              audit.contentSuccess = content.paragraphs.isNotEmpty;
              if (content.paragraphs.isEmpty) {
                audit.flaws.add('getChapterContent returned 0 paragraphs');
              } else if (content.paragraphs.length == 1 && content.paragraphs.first.length < 50) {
                audit.flaws.add('Suspiciously short chapter content: "${content.paragraphs.first}"');
              }
            } catch (e) {
              audit.contentError = e.toString();
              audit.flaws.add('getChapterContent threw: ${e.toString().split('\n').first}');
            }
          }
        } catch (e) {
          audit.detailError = e.toString();
          audit.flaws.add('getNovelDetails threw: ${e.toString().split('\n').first}');
        }
      } else {
        audit.flaws.add('No sample novel could be discovered from popular or search');
      }

      results.add(audit);
    }

    print('\n================================================================');
    print('📊 AUDIT SUMMARY REPORT FOR ALL CHECKED SOURCES');
    print('================================================================');

    for (final a in results) {
      final statusIcon = a.flaws.isEmpty ? '✅' : (a.flaws.length <= 2 ? '⚠️' : '❌');
      print('$statusIcon [${a.id}] ${a.name} (${a.lang})');
      print('   Popular: ${a.popularCount} | Latest: ${a.latestCount} | Search: ${a.searchCount} | Ch: ${a.chaptersCount} | Paras: ${a.paragraphCount}');
      if (a.detailTitle.isNotEmpty) {
        print('   Sample: "${a.detailTitle}" by "${a.detailAuthor}"');
        print('   Cover: ${a.detailCover.isNotEmpty ? a.detailCover : "None"}');
      }
      if (a.flaws.isNotEmpty) {
        print('   FLAWS DETECTED (${a.flaws.length}):');
        for (final f in a.flaws) {
          print('     • $f');
        }
      }
      print('----------------------------------------------------------------');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
