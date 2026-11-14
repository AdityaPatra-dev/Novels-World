import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/core/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storageService;
  late BackupService backupService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('backup_test_');
    storageService = StorageService();
    await storageService.init(appDir: tempDir);
    backupService = BackupService(storageService: storageService);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('Export Monolithic Backup creates valid .zip archive and manifest', () async {
    final novel = Novel(
      id: 'novel_123',
      title: 'Shadow Slave',
      author: 'Guiltythree',
      coverUrl: 'https://example.com/cover.jpg',
      description: 'Growing up in poverty...',
      sourceId: 'novelpub',
      sourceUrl: 'https://novelpub.com/shadow-slave',
    );

    // Save chapter content
    final content1 = ChapterContent(
      chapterId: 'ch_1',
      novelId: 'novel_123',
      title: 'Chapter 1: Nightmare Begins',
      paragraphs: ['Paragraph 1', 'Paragraph 2'],
      rawText: 'Paragraph 1\n\nParagraph 2',
    );
    await storageService.cacheChapterContent(content1);
    await storageService.recordDownloadedNovel(novel, 'ch_1');

    // Create fake audiobook file
    final audioDir = storageService.getNovelAudiobookDirectory('novel_123');
    await audioDir.create(recursive: true);
    final audioFile = File('${audioDir.path}/ch_1_hi.mp3');
    await audioFile.writeAsBytes([0xFF, 0xFB, 0x90, 0x44, 0x00, 0x01]);

    // Export monolithic
    final exportDir = Directory('${tempDir.path}/backups');
    await exportDir.create(recursive: true);

    final result = await backupService.exportBackup(
      mode: BackupMode.monolithic,
      customDestinationDir: exportDir,
    );

    expect(result.success, isTrue);
    expect(result.backupFiles.length, 1);
    expect(result.backupFiles.first.existsSync(), isTrue);
    expect(result.totalFiles, 2); // 1 chapter json + 1 mp3

    // Inspect archive
    final summary = await backupService.inspectBackup([result.backupFiles.first.path]);
    expect(summary.totalNovels, 1);
    expect(summary.novelTitles.first, 'Shadow Slave');
    expect(summary.totalChapters, 1);
    expect(summary.totalAudiobooks, 1);
  });

  test('Export Split Batches partitions files when exceeding maxBatchSizeBytes', () async {
    final novel1 = Novel(
      id: 'novel_1',
      title: 'Novel One',
      author: 'Author One',
      coverUrl: '',
      description: '',
      sourceId: 'src1',
      sourceUrl: '',
    );
    final novel2 = Novel(
      id: 'novel_2',
      title: 'Novel Two',
      author: 'Author Two',
      coverUrl: '',
      description: '',
      sourceId: 'src2',
      sourceUrl: '',
    );

    await storageService.cacheChapterContent(ChapterContent(
      chapterId: 'n1_c1',
      novelId: 'novel_1',
      title: 'Ch 1',
      paragraphs: List.filled(50, 'Some long paragraph text to take up bytes in the backup file.'),
      rawText: 'Long text 1',
    ));
    await storageService.recordDownloadedNovel(novel1, 'n1_c1');

    await storageService.cacheChapterContent(ChapterContent(
      chapterId: 'n2_c1',
      novelId: 'novel_2',
      title: 'Ch 2',
      paragraphs: List.filled(50, 'Some other long paragraph text taking up bytes in the backup file.'),
      rawText: 'Long text 2',
    ));
    await storageService.recordDownloadedNovel(novel2, 'n2_c1');

    final exportDir = Directory('${tempDir.path}/split_backups');
    await exportDir.create(recursive: true);

    // Set maxBatchSizeBytes very small (100 bytes) so each novel creates its own batch volume
    final result = await backupService.exportBackup(
      mode: BackupMode.splitBatches,
      maxBatchSizeBytes: 200,
      customDestinationDir: exportDir,
    );

    expect(result.success, isTrue);
    expect(result.backupFiles.length, 2);
    expect(result.backupFiles[0].path.contains('Part1.zip'), isTrue);
    expect(result.backupFiles[1].path.contains('Part2.zip'), isTrue);

    // Inspect all batches
    final summary = await backupService.inspectBackup(
      result.backupFiles.map((f) => f.path).toList(),
    );
    expect(summary.totalNovels, 2);
    expect(summary.totalChapters, 2);
    expect(summary.totalBatches, 2);
  });

  test('Restore Backup reconstitutes chapters, audiobooks, and StorageService records', () async {
    final novel = Novel(
      id: 'shadow_slave',
      title: 'Shadow Slave',
      author: 'Guiltythree',
      coverUrl: 'https://example.com/ss.jpg',
      description: 'Sunny awakens...',
      sourceId: 'novelpub',
      sourceUrl: 'https://novelpub.com/ss',
    );

    await storageService.cacheChapterContent(ChapterContent(
      chapterId: 'ss_ch1',
      novelId: 'shadow_slave',
      title: 'Chapter 1',
      paragraphs: ['Sunny was cold.'],
      rawText: 'Sunny was cold.',
    ));
    await storageService.recordDownloadedNovel(novel, 'ss_ch1');

    final audioDir = storageService.getNovelAudiobookDirectory('shadow_slave');
    await audioDir.create(recursive: true);
    final audioFile = File('${audioDir.path}/ss_ch1_hi.mp3');
    await audioFile.writeAsBytes([0x41, 0x55, 0x44, 0x49, 0x4F]);

    // Export
    final exportDir = Directory('${tempDir.path}/restore_export');
    await exportDir.create(recursive: true);
    final exportResult = await backupService.exportBackup(
      mode: BackupMode.monolithic,
      customDestinationDir: exportDir,
    );
    expect(exportResult.success, isTrue);

    // Simulate clean install in fresh storage directory
    final freshDir = Directory.systemTemp.createTempSync('fresh_app_');
    SharedPreferences.setMockInitialValues({});
    final freshStorage = StorageService();
    await freshStorage.init(appDir: freshDir);
    final freshBackupService = BackupService(storageService: freshStorage);

    expect(await freshStorage.getDownloadedNovels(), isEmpty);
    expect(await freshStorage.isChapterDownloaded('ss_ch1'), isFalse);
    expect(freshStorage.hasOfflineAudiobook('shadow_slave', 'ss_ch1', 'hi'), isFalse);

    // Import backup
    final restoreResult = await freshBackupService.restoreBackup(
      zipPaths: [exportResult.backupFiles.first.path],
      mode: RestoreMode.safeMerge,
    );

    expect(restoreResult.success, isTrue);
    expect(restoreResult.restoredNovelsCount, 1);
    expect(restoreResult.restoredChaptersCount, 1);
    expect(restoreResult.restoredAudiobooksCount, 1);

    // Verify freshStorage state
    final downloadedNovels = await freshStorage.getDownloadedNovels();
    expect(downloadedNovels.length, 1);
    expect(downloadedNovels.first.id, 'shadow_slave');
    expect(downloadedNovels.first.title, 'Shadow Slave');

    expect(await freshStorage.isChapterDownloaded('ss_ch1'), isTrue);
    final restoredContent = await freshStorage.getCachedChapterContent('ss_ch1');
    expect(restoredContent?.paragraphs.first, 'Sunny was cold.');

    expect(freshStorage.hasOfflineAudiobook('shadow_slave', 'ss_ch1', 'hi'), isTrue);
    final restoredAudio = freshStorage.getAudiobookFile('shadow_slave', 'ss_ch1', 'hi');
    expect(restoredAudio.existsSync(), isTrue);
    expect(await restoredAudio.readAsBytes(), [0x41, 0x55, 0x44, 0x49, 0x4F]);

    freshDir.deleteSync(recursive: true);
  });
}
