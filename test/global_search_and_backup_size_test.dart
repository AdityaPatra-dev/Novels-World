import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/core/services/backup_service.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/data/download_service.dart';
import 'package:novels_world/providers/library_provider.dart';
import 'package:novels_world/ui/browse/browse_screen.dart';
import 'package:novels_world/ui/search/global_search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Backup Estimate & Parts Calculation Tests', () {
    test('estimateBackup returns 0 parts and 0 B when library has no downloads', () async {
      final tempDir = Directory.systemTemp.createTempSync('backup_estimate_empty');
      final storage = StorageService();
      await storage.init(appDir: tempDir);

      final backupService = BackupService(storageService: storage);
      final est = await backupService.estimateBackup();

      expect(est.totalBytes, equals(0));
      expect(est.totalFiles, equals(0));
      expect(est.novelCount, equals(0));
      expect(est.partCount, equals(0));
      expect(est.formattedSize, equals('0 B'));
    });

    test('estimateBackup correctly calculates data size and 1.5 GB split parts', () async {
      final tempDir = Directory.systemTemp.createTempSync('backup_estimate_populated');
      final storage = StorageService();
      await storage.init(appDir: tempDir);

      // Create fake downloaded novel 1 with 2 MB chapter
      final novel1 = const Novel(
        id: 'test_novel_1',
        title: 'Novel One',
        author: 'Author A',
        sourceId: 'readnovelfull',
        sourceUrl: 'https://test.com/novel/1',
      );
      final ch1 = const Chapter(id: 'ch1', novelId: 'test_novel_1', title: 'Chapter 1', url: 'https://test.com/ch1');
      await storage.restoreDownloadedNovelData(novel: novel1, chapters: [ch1], downloadedChapterIds: {'ch1'});
      await storage.cacheChapterContent(ChapterContent(
        chapterId: 'ch1',
        novelId: 'test_novel_1',
        title: 'Chapter 1',
        rawText: 'A' * 2000000,
        paragraphs: ['A' * 2000000],
      ));

      // Create fake novel 2 with chapter
      final novel2 = const Novel(
        id: 'test_novel_2',
        title: 'Novel Two',
        author: 'Author B',
        sourceId: 'novelfull',
        sourceUrl: 'https://test.com/novel/2',
      );
      final ch2 = const Chapter(id: 'ch2', novelId: 'test_novel_2', title: 'Chapter 2', url: 'https://test.com/ch2');
      await storage.restoreDownloadedNovelData(novel: novel2, chapters: [ch2], downloadedChapterIds: {'ch2'});
      await storage.cacheChapterContent(ChapterContent(
        chapterId: 'ch2',
        novelId: 'test_novel_2',
        title: 'Chapter 2',
        rawText: 'B' * 1000000,
        paragraphs: ['B' * 1000000],
      ));

      final backupService = BackupService(storageService: storage);

      // With default 1.5 GB limit, ~3 MB is 1 part
      final est = await backupService.estimateBackup();
      expect(est.novelCount, equals(2));
      expect(est.totalFiles, equals(2));
      expect(est.totalBytes, greaterThan(2900000));
      expect(est.partCount, equals(1));

      // With small 1.5 MB split limit, novel1 (2MB) + novel2 (1MB) will split into 2 parts
      final splitEst = await backupService.estimateBackup(maxBatchSizeBytes: 1500000);
      expect(splitEst.partCount, equals(2));
    });
  });

  group('Global Search & Browse Default Tests', () {
    testWidgets('GlobalSearchScreen does NOT contain "Popular Across All Sources" or "True Global Search"', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LibraryProvider(StorageService())),
            ChangeNotifierProvider(create: (_) => DownloadService(StorageService())),
          ],
          child: const MaterialApp(
            home: GlobalSearchScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Popular Across All Sources'), findsNothing);
      expect(find.text('True Global Search'), findsNothing);
      expect(find.byType(GlobalSearchScreen), findsOneWidget);
    });

    testWidgets('BrowseScreen defaults to Global Search', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('browse_default_test');
      final storage = StorageService();
      await tester.runAsync(() async {
        await storage.init(appDir: tempDir);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storage),
            ChangeNotifierProvider(create: (_) => LibraryProvider(storage)),
            ChangeNotifierProvider(create: (_) => DownloadService(storage)),
          ],
          child: const MaterialApp(
            home: BrowseScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // GlobalSearchScreen should be displayed inside BrowseScreen by default
      expect(find.byType(GlobalSearchScreen), findsOneWidget);
      // It should NOT display single source title "Browse Novels"
      expect(find.text('Browse Novels'), findsNothing);
    });
  });
}
