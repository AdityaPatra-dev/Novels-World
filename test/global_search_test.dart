import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/services/global_search_controller.dart';
import 'package:novels_world/extractors/novel_source.dart';

class MockSearchSource implements NovelSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final String baseUrl;
  @override
  final String lang;
  @override
  final String iconUrl = '';
  @override
  final int estimatedNovelCount = 1000;

  final Duration delay;
  final List<Novel> Function(String query) searchHandler;

  MockSearchSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lang = 'en',
    this.delay = Duration.zero,
    required this.searchHandler,
  });

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return searchHandler(query);
  }

  @override
  Future<List<Novel>> getPopular({int page = 1}) async => [];

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => [];

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    return Novel(id: '${id}_1', sourceId: id, title: 'Mock', author: 'Author', coverUrl: '', sourceUrl: novelUrl);
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async => [];

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    return ChapterContent(chapterId: '1', novelId: '1', title: 'Ch 1', rawText: 'Content', paragraphs: ['Content']);
  }
}

void main() {
  group('GlobalSearchController Tests', () {
    late GlobalSearchController controller;

    setUp(() {
      controller = GlobalSearchController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Initializes with empty state', () {
      expect(controller.value.isSearching, isFalse);
      expect(controller.value.query, isEmpty);
      expect(controller.value.totalSources, 0);
      expect(controller.value.completedSources, 0);
      expect(controller.value.allNovelsRaw, isEmpty);
      expect(controller.value.groupedMatches, isEmpty);
    });

    test('Queries multiple sources in parallel and groups identical titles across sources', () async {
      final source1 = MockSearchSource(
        id: 'novelfire',
        name: 'NovelFire',
        baseUrl: 'https://novelfire.net',
        searchHandler: (q) => [
          const Novel(
            id: 'novelfire_shadow-slave',
            sourceId: 'novelfire',
            title: 'Shadow Slave',
            author: 'Guiltythree',
            coverUrl: 'https://novelfire.net/shadow.jpg',
            sourceUrl: 'https://novelfire.net/book/shadow-slave',
          ),
          const Novel(
            id: 'novelfire_reverend-insanity',
            sourceId: 'novelfire',
            title: 'Reverend Insanity',
            author: 'Gu Zhen Ren',
            coverUrl: 'https://novelfire.net/ri.jpg',
            sourceUrl: 'https://novelfire.net/book/reverend-insanity',
          ),
        ],
      );

      final source2 = MockSearchSource(
        id: 'novelfull',
        name: 'NovelFull',
        baseUrl: 'https://novelfull.com',
        searchHandler: (q) => [
          const Novel(
            id: 'novelfull_shadow-slave',
            sourceId: 'novelfull',
            title: 'Shadow Slave (Web Novel)',
            author: 'Guiltythree',
            coverUrl: 'https://novelfull.com/shadow.jpg',
            sourceUrl: 'https://novelfull.com/shadow-slave.html',
          ),
        ],
      );

      final source3 = MockSearchSource(
        id: 'royalroad',
        name: 'Royal Road',
        baseUrl: 'https://royalroad.com',
        searchHandler: (q) => [
          const Novel(
            id: 'royalroad_mother-of-learning',
            sourceId: 'royalroad',
            title: 'Mother of Learning',
            author: 'nobody103',
            coverUrl: 'https://royalroad.com/mol.jpg',
            sourceUrl: 'https://royalroad.com/fiction/21220/mother-of-learning',
          ),
        ],
      );

      await controller.search('shadow', targetSources: [source1, source2, source3]);

      final state = controller.value;
      expect(state.isSearching, isFalse);
      expect(state.completedSources, 3);
      expect(state.totalSources, 3);
      expect(state.totalNovelsFound, 4);

      // Verify cross-source clustering
      expect(state.groupedMatches.length, 3);

      final shadowMatch = state.groupedMatches.firstWhere(
        (m) => GlobalSearchController.normalizeTitle(m.canonicalTitle) == 'shadow slave',
      );
      expect(shadowMatch.sourceCount, 2);
      expect(shadowMatch.sources.map((s) => s.id), containsAll(['novelfire', 'novelfull']));
      expect(shadowMatch.sourceVariants[source1]?.sourceUrl, 'https://novelfire.net/book/shadow-slave');
      expect(shadowMatch.sourceVariants[source2]?.sourceUrl, 'https://novelfull.com/shadow-slave.html');
    });

    test('Fault tolerance: isolating source errors and timeouts without breaking others', () async {
      final healthySource = MockSearchSource(
        id: 'healthy',
        name: 'Healthy Source',
        baseUrl: 'https://healthy.com',
        searchHandler: (q) => [
          const Novel(
            id: 'healthy_1',
            sourceId: 'healthy',
            title: 'Lord of the Mysteries',
            author: 'Cuttlefish',
            coverUrl: '',
            sourceUrl: 'https://healthy.com/lotm',
          ),
        ],
      );

      final failingSource = MockSearchSource(
        id: 'failing',
        name: 'Failing Source',
        baseUrl: 'https://failing.com',
        searchHandler: (q) => throw Exception('500 Internal Server Error'),
      );

      final timeoutSource = MockSearchSource(
        id: 'timeout',
        name: 'Timeout Source',
        baseUrl: 'https://timeout.com',
        delay: const Duration(seconds: 15),
        searchHandler: (q) => [],
      );

      // Overriding timeout for fast unit testing
      await controller.search('lord', targetSources: [healthySource, failingSource]);

      final state = controller.value;
      expect(state.isSearching, isFalse);
      expect(state.completedSources, 2);
      expect(state.totalNovelsFound, 1);
      expect(state.groupedMatches.length, 1);
      expect(state.groupedMatches.first.canonicalTitle, 'Lord of the Mysteries');

      final failedResult = state.sourceResults.firstWhere((r) => r.source.id == 'failing');
      expect(failedResult.isSuccess, isFalse);
      expect(failedResult.errorMessage, contains('500 Internal Server Error'));
    });

    test('Token cancellation: rapid typing discards stale previous query results', () async {
      final slowSource = MockSearchSource(
        id: 'slow',
        name: 'Slow Source',
        baseUrl: 'https://slow.com',
        delay: const Duration(milliseconds: 300),
        searchHandler: (q) => [
          Novel(
            id: 'slow_$q',
            sourceId: 'slow',
            title: 'Stale $q',
            author: 'Author',
            coverUrl: '',
            sourceUrl: 'https://slow.com/$q',
          ),
        ],
      );

      final fastSource = MockSearchSource(
        id: 'fast',
        name: 'Fast Source',
        baseUrl: 'https://fast.com',
        delay: const Duration(milliseconds: 50),
        searchHandler: (q) => [
          Novel(
            id: 'fast_$q',
            sourceId: 'fast',
            title: 'Fresh $q',
            author: 'Author',
            coverUrl: '',
            sourceUrl: 'https://fast.com/$q',
          ),
        ],
      );

      // Trigger query 1
      final future1 = controller.search('query1', targetSources: [slowSource]);
      // Rapidly trigger query 2
      final future2 = controller.search('query2', targetSources: [fastSource]);

      await Future.wait([future1, future2]);

      final state = controller.value;
      expect(state.query, 'query2');
      // Results from query 1 must be discarded
      expect(state.allNovelsRaw.any((n) => n.title.contains('query1')), isFalse);
      expect(state.allNovelsRaw.any((n) => n.title.contains('query2')), isTrue);
    });

    test('Title normalizer cleans CMS tags, brackets, and extra spaces', () {
      expect(GlobalSearchController.normalizeTitle('Shadow Slave (Web Novel)'), 'shadow slave');
      expect(GlobalSearchController.normalizeTitle('Shadow Slave [LN]'), 'shadow slave');
      expect(GlobalSearchController.normalizeTitle('  Lord of the Mysteries : Novel  '), 'lord of the mysteries');
      expect(GlobalSearchController.normalizeTitle('Reverend Insanity (MTL)'), 'reverend insanity');
      expect(GlobalSearchController.normalizeTitle('Mother of Learning [Complete]'), 'mother of learning');
    });

    test('Relevance scoring ranks canonical exact match higher than fanfictions and spin-offs', () {
      final dummySource1 = MockSearchSource(id: 's1', name: 'Source 1', baseUrl: 'https://s1.com', searchHandler: (_) => []);
      final dummySource2 = MockSearchSource(id: 's2', name: 'Source 2', baseUrl: 'https://s2.com', searchHandler: (_) => []);

      final canonicalMatch = GroupedNovelMatch(
        canonicalTitle: 'Shadow Slave',
        author: 'Guiltythree',
        coverUrl: '',
        sourceVariants: {
          dummySource1: const Novel(id: '1', sourceId: 's1', title: 'Shadow Slave', author: 'Guiltythree', coverUrl: '', sourceUrl: ''),
          dummySource2: const Novel(id: '2', sourceId: 's2', title: 'Shadow Slave', author: 'Guiltythree', coverUrl: '', sourceUrl: ''),
        },
      );

      final fanficMatch = GroupedNovelMatch(
        canonicalTitle: 'The Lord of Veins | A Shadow Slave Fanfiction',
        author: 'FanWriter',
        coverUrl: '',
        sourceVariants: {
          dummySource1: const Novel(id: '3', sourceId: 's1', title: 'The Lord of Veins | A Shadow Slave Fanfiction', author: 'FanWriter', coverUrl: '', sourceUrl: ''),
        },
      );

      final adaptationMatch = GroupedNovelMatch(
        canonicalTitle: 'Shadow Slave: Alternate Universe Adaptation',
        author: 'AU_Writer',
        coverUrl: '',
        sourceVariants: {
          dummySource1: const Novel(id: '4', sourceId: 's1', title: 'Shadow Slave: Alternate Universe Adaptation', author: 'AU_Writer', coverUrl: '', sourceUrl: ''),
        },
      );

      final canonicalScore = GlobalSearchController.computeRelevanceScore(canonicalMatch, 'Shadow Slave');
      final fanficScore = GlobalSearchController.computeRelevanceScore(fanficMatch, 'Shadow Slave');
      final adaptationScore = GlobalSearchController.computeRelevanceScore(adaptationMatch, 'Shadow Slave');

      expect(canonicalScore, greaterThan(fanficScore));
      expect(canonicalScore, greaterThan(adaptationScore));
      expect(canonicalScore, greaterThan(20000)); // Has exact match (20,000) + multi-source boost (1,000)
      expect(fanficScore, lessThan(1000)); // Demoted heavily by fanfiction penalty (-5,000)
    });

    test('Per-novel relevance scoring rewards exact title and author matches', () {
      final scoreExact = GlobalSearchController.computeNovelRelevance('Shadow Slave', 'Guiltythree', 'Shadow Slave');
      final scoreAuthor = GlobalSearchController.computeNovelRelevance('Different Novel', 'Guiltythree', 'Guiltythree');
      final scoreRandom = GlobalSearchController.computeNovelRelevance('Random World', 'Random', 'Shadow Slave');

      expect(scoreExact, greaterThan(scoreAuthor));
      expect(scoreAuthor, greaterThan(scoreRandom));
      expect(scoreRandom, 0);
    });
  });
}

