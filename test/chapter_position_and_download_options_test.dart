import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/reading_progress.dart';
import 'package:novels_world/data/download_service.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/extractors/novel_source.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/providers/reader_provider.dart';

class _MockTestNovelSource implements NovelSource {
  @override
  final String id = 'test_source';
  @override
  final String name = 'Test Source';
  @override
  final String baseUrl = 'https://testsource.org';
  @override
  final String lang = 'en';
  @override
  final String iconUrl = '';
  @override
  final int estimatedNovelCount = 50;

  @override
  Future<List<Novel>> getPopular({int page = 1}) async => [];

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => [];

  @override
  Future<Novel> getNovelDetails(String novelUrl) async => throw UnimplementedError();

  @override
  Future<List<Chapter>> getChapterList(String novelUrl, {int page = 1, void Function(List<Chapter> batch)? onBatchLoaded}) async => [];

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    return ChapterContent(
      novelId: 'novel_1',
      chapterId: chapterUrl,
      title: 'Chapter for $chapterUrl',
      rawText: 'First sentence of chapter. Second sentence here. Third sentence follows.',
      paragraphs: ['First sentence of chapter.', 'Second sentence here.', 'Third sentence follows.'],
    );
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late Directory tempDir;
  late Novel testNovel;
  late List<Chapter> testChapters;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('chapter_pos_test_');
    storage = StorageService();
    await storage.init(appDir: tempDir);

    SourceRegistry.registerSource(_MockTestNovelSource());

    testNovel = const Novel(
      id: 'novel_1',
      title: 'Legend of the Dragon',
      author: 'Author Nim',
      coverUrl: 'https://example.com/cover.jpg',
      sourceId: 'test_source',
      sourceUrl: 'https://testsource.org/novel_1',
    );

    testChapters = List.generate(
      50,
      (i) => Chapter(
        id: 'ch_${i + 1}',
        title: 'Chapter ${i + 1}',
        url: 'ch_${i + 1}',
        novelId: 'novel_1',
      ),
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Reading Position Protection Tests', () {
    test('Checking out earlier chapter 2 does NOT overwrite reading position at chapter 37', () async {
      // 1. Establish reading position at chapter 37
      await storage.saveProgress(
        ReadingProgress(
          novelId: testNovel.id,
          chapterId: 'ch_37',
          chapterTitle: 'Chapter 37',
          activeSentenceIndex: 5,
          lastReadAt: DateTime.now(),
        ),
      );

      expect(storage.getProgress(testNovel.id)?.chapterId, equals('ch_37'));

      // 2. User checks out chapter 2
      final reader = ReaderProvider(storage);
      await reader.initializeNovelReader(
        novel: testNovel,
        chapters: testChapters,
        initialChapter: testChapters[1], // Chapter 2
      );

      // Verify that the reader loaded chapter 2 for reading/inspection
      expect(reader.currentChapter?.id, equals('ch_2'));

      // Verify that novel's canonical saved position in storage REMAINS chapter 37!
      final progressAfterInspect = storage.getProgress(testNovel.id);
      expect(progressAfterInspect, isNotNull);
      expect(progressAfterInspect!.chapterId, equals('ch_37'));

      // 3. User scrolls inside chapter 2
      reader.saveScrollProgress(150.0);
      reader.setActiveSentence(1);

      // Still chapter 37!
      expect(storage.getProgress(testNovel.id)?.chapterId, equals('ch_37'));
    });

    test('Advancing forward within novel via nextChapter() from position updates reading position', () async {
      // 1. Establish reading position at chapter 37
      await storage.saveProgress(
        ReadingProgress(
          novelId: testNovel.id,
          chapterId: 'ch_37',
          chapterTitle: 'Chapter 37',
          activeSentenceIndex: 0,
          lastReadAt: DateTime.now(),
        ),
      );

      final reader = ReaderProvider(storage);
      await reader.initializeNovelReader(
        novel: testNovel,
        chapters: testChapters,
        initialChapter: testChapters[36], // Chapter 37
      );

      expect(reader.currentChapter?.id, equals('ch_37'));

      // 2. User reads and clicks Next Chapter -> Chapter 38
      await reader.nextChapter();
      expect(reader.currentChapter?.id, equals('ch_38'));

      // Verify progress advanced to chapter 38
      final progressAfterNext = storage.getProgress(testNovel.id);
      expect(progressAfterNext?.chapterId, equals('ch_38'));
    });

    test('Explicitly setting reading position via 3-dots sets reading position to any chapter', () async {
      // 1. Establish reading position at chapter 37
      await storage.saveProgress(
        ReadingProgress(
          novelId: testNovel.id,
          chapterId: 'ch_37',
          chapterTitle: 'Chapter 37',
          lastReadAt: DateTime.now(),
        ),
      );

      expect(storage.getProgress(testNovel.id)?.chapterId, equals('ch_37'));

      // 2. User explicitly chooses "Set as current position" on Chapter 2
      await storage.saveProgress(
        ReadingProgress(
          novelId: testNovel.id,
          chapterId: 'ch_2',
          chapterTitle: 'Chapter 2',
          lastReadAt: DateTime.now(),
        ),
      );

      expect(storage.getProgress(testNovel.id)?.chapterId, equals('ch_2'));
    });
  });

  group('Download Single Chapter Deletion Tests', () {
    test('Deleting single chapter text removes it from disk and DownloadService', () async {
      final downloadService = DownloadService(storage);

      // Cache a chapter content to disk
      await storage.cacheChapterContent(
        const ChapterContent(
          novelId: 'novel_1',
          chapterId: 'ch_5',
          title: 'Chapter 5',
          rawText: 'Some offline text content',
          paragraphs: ['Some offline text content'],
        ),
      );

      expect(await storage.isChapterDownloaded('ch_5'), isTrue);

      // Delete chapter 5 from downloads
      await downloadService.deleteSingleChapterDownload('ch_5');

      expect(await storage.isChapterDownloaded('ch_5'), isFalse);
      expect(downloadService.isChapterDownloaded('ch_5'), isFalse);
    });

    test('Deleting chapter audiobook removes mp3 file from storage', () async {
      // Create a simulated audiobook mp3 file for chapter 10
      final audiobookFile = storage.getAudiobookFile('novel_1', 'ch_10', 'en');
      await audiobookFile.parent.create(recursive: true);
      await audiobookFile.writeAsBytes([0, 1, 2, 3]);

      expect(storage.hasOfflineAudiobook('novel_1', 'ch_10'), isTrue);

      // Delete the audiobook
      await storage.deleteAudiobookChapter('novel_1', 'ch_10', 'en');

      expect(storage.hasOfflineAudiobook('novel_1', 'ch_10'), isFalse);
    });
  });

  group('Audio-Only Chapter List Filtering Tests', () {
    test('Filtering chapters by offline audiobook returns only chapters with audio', () async {
      // Create audio for chapters 3 and 7
      final file3 = storage.getAudiobookFile('novel_1', 'ch_3', 'en');
      await file3.parent.create(recursive: true);
      await file3.writeAsBytes([1, 2, 3]);

      final file7 = storage.getAudiobookFile('novel_1', 'ch_7', 'en');
      await file7.parent.create(recursive: true);
      await file7.writeAsBytes([4, 5, 6]);

      // Filter chapters that have offline audio
      final audioOnlyChapters = testChapters.where((c) => storage.hasOfflineAudiobook('novel_1', c.id)).toList();

      expect(audioOnlyChapters.length, equals(2));
      expect(audioOnlyChapters.map((c) => c.id).toList(), equals(['ch_3', 'ch_7']));
    });
  });
}
