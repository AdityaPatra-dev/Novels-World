import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/data/download_service.dart';
import 'package:novels_world/extractors/novel_source.dart';
import 'package:novels_world/extractors/source_registry.dart';

class MockDownloadNovelSource implements NovelSource {
  @override
  String get id => 'test_source';
  @override
  String get name => 'Mock Source';
  @override
  String get baseUrl => 'https://mock.com';
  @override
  String get lang => 'en';
  @override
  String get iconUrl => '';
  @override
  int get estimatedNovelCount => 100;

  @override
  Future<List<Novel>> getPopular({int page = 1}) async => [];

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => [];

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async => [];

  @override
  Future<Novel> getNovelDetails(String novelUrl) async => const Novel(
        id: 'mock_novel_1',
        sourceId: 'test_source',
        title: 'Mock Novel',
        sourceUrl: 'https://mock.com/novel/1',
      );

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async => [];

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    return ChapterContent(
      chapterId: chapterUrl.split('/').last,
      novelId: 'mock_novel_1',
      title: 'Chapter ${chapterUrl.split('/').last}',
      rawText: 'This is offline downloaded text.',
      paragraphs: ['This is offline downloaded text.'],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late DownloadService downloadService;
  late Directory tempDir;

  const testNovel = Novel(
    id: 'mock_novel_1',
    sourceId: 'test_source',
    title: 'Mock Novel',
    sourceUrl: 'https://mock.com/novel/1',
  );

  final testChapters = List.generate(
    10,
    (i) => Chapter(
      id: 'mock_ch_$i',
      novelId: 'mock_novel_1',
      title: 'Chapter $i',
      chapterNumber: i.toDouble(),
      url: 'https://mock.com/novel/1/ch-$i',
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('novels_world_dl_test');
    storage = StorageService();
    await storage.init(appDir: tempDir);

    SourceRegistry.registerSource(MockDownloadNovelSource());
    downloadService = DownloadService(storage);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 3: Offline Library & Chapter Batch Downloader', () {
    test('Enqueues next N unread chapters correctly', () async {
      await downloadService.enqueueNextUnread(testNovel, testChapters, 5);

      expect(downloadService.queue.length, 5);
      expect(downloadService.queue.first.chapter.id, 'mock_ch_0');
      expect(downloadService.queue.last.chapter.id, 'mock_ch_4');
    });

    test('Downloads chapters in background and caches to disk', () async {
      // Enqueue 2 chapters
      await downloadService.enqueueChapters(testNovel, [testChapters[0], testChapters[1]]);

      // Wait for the background queue processor to complete downloads
      int checks = 0;
      while (downloadService.isProcessing && checks < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        checks++;
      }

      // Check both chapters are now downloaded
      expect(downloadService.isChapterDownloaded('mock_ch_0'), true);
      expect(downloadService.isChapterDownloaded('mock_ch_1'), true);

      // Verify cached content exists on disk
      final cachedContent = await storage.getCachedChapterContent('mock_ch_0');
      expect(cachedContent, isNotNull);
      expect(cachedContent?.rawText, contains('This is offline downloaded text.'));

      // Check cache stats
      final count = await storage.getTotalCachedChapterCount();
      expect(count, greaterThanOrEqualTo(2));
      final sizeMb = await storage.getCacheSizeMb();
      expect(sizeMb, greaterThan(0.0));
    });

    test('Deletes downloaded chapters cleanly from disk', () async {
      await downloadService.enqueueChapters(testNovel, [testChapters[0]]);

      while (downloadService.isProcessing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(downloadService.isChapterDownloaded('mock_ch_0'), true);

      // Delete downloads
      await downloadService.deleteNovelDownloads(testNovel.id, [testChapters[0]]);

      expect(downloadService.isChapterDownloaded('mock_ch_0'), false);
    });
  });
}

