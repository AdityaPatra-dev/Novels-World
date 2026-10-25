import 'novel_source.dart';
import 'madara_extractor.dart';
import 'lightnovelwp_extractor.dart';
import 'novelfull_extractor.dart';
import 'readwn_extractor.dart';
import 'fictioneer_extractor.dart';
import 'bespoke/royalroad_extractor.dart';
import 'bespoke/scribblehub_extractor.dart';

/// Comprehensive Source Registry cataloging verified novel websites from
/// NOVEL_SOURCES_AND_TEMPLATES.md across WordPress Madara, LightNovelWP,
/// NovelFull, ReadWN/EmpireCMS, and Bespoke platforms.
///
/// Sources are automatically sorted:
/// 1. English novels always at top (lang == 'en').
/// 2. Followed by other languages (grouped).
/// 3. Within the same language, sources having more novels (catalog size) are placed first.
class SourceRegistry {
  static final Map<String, NovelSource> _sources = {
    // ==========================================
    // 1. Bespoke Western Web Fiction
    // ==========================================
    'royalroad': RoyalRoadExtractor(),
    'scribblehub': ScribbleHubExtractor(),

    // ==========================================
    // 2. High-Capacity NovelFull Aggregators
    // ==========================================
    'readnovelfull': NovelFullExtractor(
      id: 'readnovelfull',
      name: 'ReadNovelFull',
      baseUrl: 'https://readnovelfull.com',
      popularPath: '/novel-list/most-popular-novel',
      latestPath: '/novel-list/latest-release-novel',
      lang: 'en',
      estimatedNovelCount: 55000,
    ),
    'novelfull': NovelFullExtractor(
      id: 'novelfull',
      name: 'NovelFull',
      baseUrl: 'https://novelfull.com',
      popularPath: '/most-popular',
      latestPath: '/latest-release-novel',
      lang: 'en',
      estimatedNovelCount: 50000,
    ),
    'freewebnovel': NovelFullExtractor(
      id: 'freewebnovel',
      name: 'FreeWebNovel',
      baseUrl: 'https://freewebnovel.com',
      popularPath: '/sort/most-popular',
      latestPath: '/sort/latest-release',
      lang: 'en',
      estimatedNovelCount: 45000,
    ),
    'libread': NovelFullExtractor(
      id: 'libread',
      name: 'LibRead',
      baseUrl: 'https://libread.com',
      popularPath: '/sort/most-popular',
      latestPath: '/sort/latest-release',
      lang: 'en',
      estimatedNovelCount: 40000,
    ),
    'novelfire': NovelFullExtractor(
      id: 'novelfire',
      name: 'NovelFire',
      baseUrl: 'https://novelfire.net',
      popularPath: '/genre-all/sort-popular/status-all/all-novel',
      latestPath: '/genre-all/sort-new/status-all/all-novel',
      lang: 'en',
      estimatedNovelCount: 38000,
    ),
    'allnovelfull': NovelFullExtractor(
      id: 'allnovelfull',
      name: 'AllNovelFull',
      baseUrl: 'https://allnovelfull.com',
      popularPath: '/most-popular',
      latestPath: '/latest-release-novel',
      lang: 'en',
      estimatedNovelCount: 35000,
    ),
    'novelping': NovelFullExtractor(
      id: 'novelping',
      name: 'Novel Ping',
      baseUrl: 'https://novelping.com',
      popularPath: '/sort/popular',
      latestPath: '/sort/updates',
      lang: 'en',
      estimatedNovelCount: 30000,
    ),
    'lightnovelplus': NovelFullExtractor(
      id: 'lightnovelplus',
      name: 'LightNovelPlus',
      baseUrl: 'https://lightnovelplus.com',
      popularPath: '/novel-list',
      latestPath: '/latest-release-novel',
      lang: 'en',
      estimatedNovelCount: 35000,
    ),

    // ==========================================
    // 3. ReadWN / WuxiaBox MTL Network
    // ==========================================
    'wuxiabox': ReadWnExtractor(
      id: 'wuxiabox',
      name: 'WuxiaBox',
      baseUrl: 'https://www.wuxiabox.com',
      lang: 'en',
      estimatedNovelCount: 45000,
    ),
    'wuxiaspace': ReadWnExtractor(
      id: 'wuxiaspace',
      name: 'Wuxia Space',
      baseUrl: 'https://www.wuxiaspot.com',
      lang: 'en',
      estimatedNovelCount: 30000,
    ),

    // ==========================================
    // 4. WordPress LightNovelWP & Fictioneer Engine
    // ==========================================
    'knoxt': LightNovelWpExtractor(
      id: 'knoxt',
      name: 'KnoxT',
      baseUrl: 'https://knoxt.space',
      lang: 'en',
      estimatedNovelCount: 20000,
    ),
    'novelib': FictioneerExtractor(
      id: 'novelib',
      name: 'Novelib',
      baseUrl: 'https://novelib.com',
      lang: 'en',
      estimatedNovelCount: 10000,
    ),

    // ==========================================
    // 5. WordPress Madara Engine (English)
    // ==========================================
    'sonicmtl': MadaraExtractor(
      id: 'sonicmtl',
      name: 'SonicMTL',
      baseUrl: 'https://www.sonicmtl.com',
      lang: 'en',
      estimatedNovelCount: 18000,
    ),
    'wuxiaworldsite': MadaraExtractor(
      id: 'wuxiaworldsite',
      name: 'WuxiaWorld.Site',
      baseUrl: 'https://wuxiaworld.site',
      lang: 'en',
      estimatedNovelCount: 15000,
    ),
    'boxnovel': MadaraExtractor(
      id: 'boxnovel',
      name: 'BoxNovel',
      baseUrl: 'https://boxnovel.com',
      lang: 'en',
      estimatedNovelCount: 9000,
    ),
    'firstkissnovel': MadaraExtractor(
      id: 'firstkissnovel',
      name: '1stKissNovel',
      baseUrl: 'https://1stkissnovel.org',
      lang: 'en',
      estimatedNovelCount: 8000,
    ),
    'lightnovelheaven': MadaraExtractor(
      id: 'lightnovelheaven',
      name: 'LightNovelHeaven',
      baseUrl: 'https://lightnovelheaven.com',
      lang: 'en',
      estimatedNovelCount: 6000,
    ),
    'srankmanga': MadaraExtractor(
      id: 'srankmanga',
      name: 'Srank Manga',
      baseUrl: 'https://srankmanga.com',
      lang: 'en',
      estimatedNovelCount: 4000,
    ),
    'hiraethtranslation': MadaraExtractor(
      id: 'hiraethtranslation',
      name: 'Hiraeth Translation',
      baseUrl: 'https://hiraethtranslation.com',
      lang: 'en',
      estimatedNovelCount: 1500,
    ),
    'sleepytranslations': MadaraExtractor(
      id: 'sleepytranslations',
      name: 'SleepyTranslations',
      baseUrl: 'https://sleepytranslations.com',
      lang: 'en',
      estimatedNovelCount: 1500,
    ),
    'translatinotaku': MadaraExtractor(
      id: 'translatinotaku',
      name: 'TranslatinOtaku',
      baseUrl: 'https://translatinotaku.net',
      lang: 'en',
      estimatedNovelCount: 1000,
    ),

    // ==========================================
    // 6. International Sources: Arabic (ar)
    // ==========================================
    'kolnovel': LightNovelWpExtractor(
      id: 'kolnovel',
      name: 'Kol Novel',
      baseUrl: 'https://kolnovel.com',
      lang: 'ar',
      estimatedNovelCount: 8000,
    ),
    'arnovel': MadaraExtractor(
      id: 'arnovel',
      name: 'ArNovel',
      baseUrl: 'https://ar-no.com',
      lang: 'ar',
      estimatedNovelCount: 5000,
    ),
    'hizomanga': MadaraExtractor(
      id: 'hizomanga',
      name: 'HizoManga',
      baseUrl: 'https://hizomanga.net',
      lang: 'ar',
      customPopularPath: '/mangas/?m_orderby=views',
      estimatedNovelCount: 4000,
    ),

    // ==========================================
    // 7. International Sources: Portuguese (pt)
    // ==========================================
    'meionovel': MadaraExtractor(
      id: 'meionovel',
      name: 'MeioNovel',
      baseUrl: 'https://meionovels.com',
      lang: 'pt',
      estimatedNovelCount: 5000,
    ),

    // ==========================================
    // 8. International Sources: Turkish (tr)
    // ==========================================
    'turkcelightnovels': MadaraExtractor(
      id: 'turkcelightnovels',
      name: 'TurkceLightNovels',
      baseUrl: 'https://turkcelightnovels.com',
      lang: 'tr',
      estimatedNovelCount: 3000,
    ),
    'vanovel': MadaraExtractor(
      id: 'vanovel',
      name: 'Vanovel',
      baseUrl: 'https://vanovel.com',
      lang: 'tr',
      estimatedNovelCount: 3000,
    ),
    'webnoveloku': MadaraExtractor(
      id: 'webnoveloku',
      name: 'WebNovelOku',
      baseUrl: 'https://www.webnoveloku.com',
      lang: 'tr',
      estimatedNovelCount: 3000,
    ),

    // ==========================================
    // 9. International Sources: Thai (th)
    // ==========================================
    'novelpdf': MadaraExtractor(
      id: 'novelpdf',
      name: 'NovelPDF',
      baseUrl: 'https://novelpdf.xyz',
      lang: 'th',
      estimatedNovelCount: 2500,
    ),
  };

  static String _defaultSourceId = 'royalroad';

  /// Returns all registered sources sorted according to:
  /// 1. English novels always at top (lang == 'en').
  /// 2. Followed by other languages (grouped).
  /// 3. Within the same language, sources having more novels (catalog volume) are placed first.
  static List<NovelSource> getAllSources() {
    final list = _sources.values.toList();
    list.sort((a, b) {
      final aIsEn = a.lang.toLowerCase() == 'en';
      final bIsEn = b.lang.toLowerCase() == 'en';

      // 1. English novels always at top
      if (aIsEn && !bIsEn) return -1;
      if (!aIsEn && bIsEn) return 1;

      // 2. If both are non-English and have different languages, group by language
      if (!aIsEn && !bIsEn && a.lang != b.lang) {
        return a.lang.compareTo(b.lang);
      }

      // 3. Within the same language: more novels first (descending count)
      final countCompare = b.estimatedNovelCount.compareTo(a.estimatedNovelCount);
      if (countCompare != 0) return countCompare;

      // 4. Alphabetical tie-break
      return a.name.compareTo(b.name);
    });
    return list;
  }

  static NovelSource? getSource(String id) => _sources[id];

  static NovelSource getDefaultSource() =>
      _sources[_defaultSourceId] ?? getAllSources().first;

  static void setDefaultSourceId(String id) {
    _defaultSourceId = id;
  }

  static void registerSource(NovelSource source) {
    _sources[source.id] = source;
  }
}
