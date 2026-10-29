import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/reading_progress.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/extractors/novel_source.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/data/download_service.dart';
import 'package:novels_world/providers/library_provider.dart';
import 'package:novels_world/providers/reader_provider.dart';
import 'package:novels_world/ui/novel/novel_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadingProgress Model Tests', () {
    test('ReadingProgress serialization round-trip with chapterTitle', () {
      final now = DateTime.now();
      final progress = ReadingProgress(
        novelId: 'royalroad_12345',
        chapterId: 'royalroad_ch_4',
        chapterTitle: 'Chapter 4: The Ancient Trial',
        scrollOffset: 340.5,
        activeSentenceIndex: 12,
        lastReadAt: now,
      );

      final json = progress.toJson();
      expect(json['novelId'], 'royalroad_12345');
      expect(json['chapterId'], 'royalroad_ch_4');
      expect(json['chapterTitle'], 'Chapter 4: The Ancient Trial');
      expect(json['scrollOffset'], 340.5);
      expect(json['activeSentenceIndex'], 12);

      final restored = ReadingProgress.fromJson(json);
      expect(restored.novelId, progress.novelId);
      expect(restored.chapterId, progress.chapterId);
      expect(restored.chapterTitle, progress.chapterTitle);
      expect(restored.scrollOffset, progress.scrollOffset);
      expect(restored.activeSentenceIndex, progress.activeSentenceIndex);
    });

    test('ReadingProgress backwards compatibility with null chapterTitle', () {
      final json = {
        'novelId': 'novelfull_coiling_dragon',
        'chapterId': 'ch_1',
        'scrollOffset': 0.0,
        'activeSentenceIndex': 0,
        'lastReadAt': DateTime.now().toIso8601String(),
      };

      final restored = ReadingProgress.fromJson(json);
      expect(restored.chapterTitle, isNull);
      expect(restored.novelId, 'novelfull_coiling_dragon');
      expect(restored.chapterId, 'ch_1');
    });
  });

  group('StorageService Reading Progress & History Tests', () {
    late StorageService storage;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('reading_progress_test_');
      storage = StorageService();
      await storage.init(appDir: tempDir);
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('Saving progress persists ReadingProgress and auto-records read chapter', () async {
      final progress = ReadingProgress(
        novelId: 'source_novel_42',
        chapterId: 'ch_4',
        chapterTitle: 'Chapter 4',
        lastReadAt: DateTime.now(),
      );

      await storage.saveProgress(progress);

      final fetchedProgress = storage.getProgress('source_novel_42');
      expect(fetchedProgress, isNotNull);
      expect(fetchedProgress!.chapterId, 'ch_4');
      expect(fetchedProgress.chapterTitle, 'Chapter 4');

      // Verify that saving progress automatically marked the chapter as read
      expect(storage.isChapterRead('source_novel_42', 'ch_4'), isTrue);
      expect(storage.getReadChapterIds('source_novel_42'), contains('ch_4'));
    });

    test('Marking multiple chapters as read and unread', () async {
      const novelId = 'allfreenovel_test_novel';
      final chapters = ['ch_1', 'ch_2', 'ch_3', 'ch_4'];

      await storage.markChaptersAsRead(novelId, chapters);

      final readIds = storage.getReadChapterIds(novelId);
      expect(readIds.length, 4);
      expect(readIds.contains('ch_1'), isTrue);
      expect(readIds.contains('ch_2'), isTrue);
      expect(readIds.contains('ch_3'), isTrue);
      expect(readIds.contains('ch_4'), isTrue);

      // Mark single chapter as unread
      await storage.markChapterAsUnread(novelId, 'ch_2');
      expect(storage.isChapterRead(novelId, 'ch_2'), isFalse);
      expect(storage.getReadChapterIds(novelId).length, 3);
    });

    test('Clearing reading progress and history', () async {
      const novelId = 'lightnovelwp_reverend_insanity';
      await storage.saveProgress(
        ReadingProgress(
          novelId: novelId,
          chapterId: 'ch_10',
          chapterTitle: 'Chapter 10',
          lastReadAt: DateTime.now(),
        ),
      );
      await storage.markChapterAsRead(novelId, 'ch_9');

      expect(storage.getProgress(novelId), isNotNull);
      expect(storage.getReadChapterIds(novelId).length, 2);

      await storage.clearReadChapters(novelId);

      expect(storage.getProgress(novelId), isNull);
      expect(storage.getReadChapterIds(novelId), isEmpty);
    });

    test('Updating novel in library preserves lastReadChapterId and timestamp', () async {
      final novel = Novel(
        id: 'library_novel_1',
        title: 'Solo Leveling',
        author: 'Chugong',
        description: 'Hunter Sung Jin-woo',
        coverUrl: 'https://example.com/cover.jpg',
        genres: ['Action'],
        status: 'COMPLETED',
        sourceId: 'asurascans',
        sourceUrl: 'https://asurascans.com/solo-leveling',
        inLibrary: true,
      );

      await storage.saveNovelToLibrary(novel);

      await storage.saveProgress(
        ReadingProgress(
          novelId: 'library_novel_1',
          chapterId: 'ch_50',
          chapterTitle: 'Chapter 50',
          lastReadAt: DateTime.now(),
        ),
      );

      final inLibraryNovels = storage.getLibraryNovels();
      final updated = inLibraryNovels.firstWhere((n) => n.id == 'library_novel_1');
      expect(updated.lastReadChapterId, 'ch_50');
      expect(updated.lastReadAt, isNotNull);
    });
  });

  group('NovelDetailScreen Reading Progress UI Tests', () {
    late StorageService storage;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('reading_ui_test_');
      storage = StorageService();
      await storage.init(appDir: tempDir);
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('Displays Continue button, Left Off Here badge, and progress ratio', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockChapters = List.generate(
        7,
        (i) => Chapter(
          id: 'test_ch_${i + 1}',
          novelId: 'test_novel_42',
          title: 'Chapter ${i + 1}',
          chapterNumber: (i + 1).toDouble(),
          url: 'https://mock.com/ch-${i + 1}',
        ),
      );

      final mockNovel = Novel(
        id: 'test_novel_42',
        title: 'Lord of Mysteries',
        author: 'Cuttlefish',
        sourceId: 'mock_progress_src',
        sourceUrl: 'https://mock.com/lotm',
      );

      // Pre-save reading progress at Chapter 4
      await storage.saveProgress(
        ReadingProgress(
          novelId: 'test_novel_42',
          chapterId: 'test_ch_4',
          chapterTitle: 'Chapter 4',
          lastReadAt: DateTime.now(),
        ),
      );

      SourceRegistry.registerSource(_MockProgressSource(mockNovel, mockChapters));

      final libraryProvider = LibraryProvider(storage);
      final readerProvider = ReaderProvider(storage);
      final downloadService = DownloadService(storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storage),
            ChangeNotifierProvider.value(value: libraryProvider),
            ChangeNotifierProvider.value(value: readerProvider),
            ChangeNotifierProvider.value(value: downloadService),
          ],
          child: MaterialApp(
            home: NovelDetailScreen(novel: mockNovel),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify Continue Reading button displays "Continue: Chapter 4"
      expect(find.text('Continue: Chapter 4'), findsOneWidget);

      // 2. Verify "Left off here" badge is visible
      expect(find.text('Left off here'), findsOneWidget);

      // 3. Verify progress ratio "Read 4 of 7 (57%)"
      expect(find.textContaining('Read 4 of 7 (57%)'), findsOneWidget);
    });
  });
}

class _MockProgressSource implements NovelSource {
  final Novel _novel;
  final List<Chapter> _chapters;

  _MockProgressSource(this._novel, this._chapters);

  @override
  String get id => 'mock_progress_src';
  @override
  String get name => 'Mock Progress Source';
  @override
  String get baseUrl => 'https://mock.com';
  @override
  String get lang => 'en';
  @override
  String get iconUrl => '';
  @override
  int get estimatedNovelCount => 10;

  @override
  Future<List<Novel>> getPopular({int page = 1}) async => [_novel];
  @override
  Future<List<Novel>> getLatest({int page = 1}) async => [_novel];
  @override
  Future<List<Novel>> search(String query, {int page = 1}) async => [_novel];
  @override
  Future<Novel> getNovelDetails(String novelUrl) async => _novel;
  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async => _chapters;
  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async => ChapterContent(
        chapterId: 'test_ch_1',
        novelId: _novel.id,
        title: 'Chapter 1',
        rawText: 'Text',
        paragraphs: ['Text'],
      );
}
