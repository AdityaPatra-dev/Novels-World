import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../../data/storage_service.dart';

enum BackupMode {
  monolithic,
  splitBatches,
}

enum RestoreMode {
  safeMerge,
  replaceAll,
}

class BackupFileItem {
  final File file;
  final String relativeZipPath;
  final int byteSize;

  const BackupFileItem({
    required this.file,
    required this.relativeZipPath,
    required this.byteSize,
  });
}

class BackupManifestNovel {
  final Novel novel;
  final List<Chapter> chapters;
  final List<String> downloadedChapterIds;
  final List<String> audiobookFiles;
  final List<String> translationFiles;
  final ReadingProgress? progress;
  final List<String> readChapterIds;

  const BackupManifestNovel({
    required this.novel,
    required this.chapters,
    required this.downloadedChapterIds,
    required this.audiobookFiles,
    required this.translationFiles,
    this.progress,
    required this.readChapterIds,
  });

  Map<String, dynamic> toJson() => {
    'novel': novel.toJson(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'downloadedChapterIds': downloadedChapterIds,
    'audiobookFiles': audiobookFiles,
    'translationFiles': translationFiles,
    'progress': progress?.toJson(),
    'readChapterIds': readChapterIds,
  };

  factory BackupManifestNovel.fromJson(Map<String, dynamic> json) {
    return BackupManifestNovel(
      novel: Novel.fromJson(json['novel'] as Map<String, dynamic>),
      chapters: (json['chapters'] as List? ?? [])
          .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
          .toList(),
      downloadedChapterIds: (json['downloadedChapterIds'] as List? ?? []).map((e) => e.toString()).toList(),
      audiobookFiles: (json['audiobookFiles'] as List? ?? []).map((e) => e.toString()).toList(),
      translationFiles: (json['translationFiles'] as List? ?? []).map((e) => e.toString()).toList(),
      progress: json['progress'] != null
          ? ReadingProgress.fromJson(json['progress'] as Map<String, dynamic>)
          : null,
      readChapterIds: (json['readChapterIds'] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }
}

class BackupManifest {
  final String app;
  final int schemaVersion;
  final int exportTimestamp;
  final int batchIndex;
  final int totalBatches;
  final List<BackupManifestNovel> novels;
  final int fileCount;
  final int totalBytes;

  const BackupManifest({
    required this.app,
    required this.schemaVersion,
    required this.exportTimestamp,
    required this.batchIndex,
    required this.totalBatches,
    required this.novels,
    required this.fileCount,
    required this.totalBytes,
  });

  Map<String, dynamic> toJson() => {
    'app': app,
    'schemaVersion': schemaVersion,
    'exportTimestamp': exportTimestamp,
    'batchIndex': batchIndex,
    'totalBatches': totalBatches,
    'novels': novels.map((n) => n.toJson()).toList(),
    'fileCount': fileCount,
    'totalBytes': totalBytes,
  };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    return BackupManifest(
      app: json['app'] as String? ?? 'NovelsWorld',
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      exportTimestamp: json['exportTimestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      batchIndex: json['batchIndex'] as int? ?? 1,
      totalBatches: json['totalBatches'] as int? ?? 1,
      novels: (json['novels'] as List? ?? [])
          .map((n) => BackupManifestNovel.fromJson(n as Map<String, dynamic>))
          .toList(),
      fileCount: json['fileCount'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int? ?? 0,
    );
  }
}

class BackupExportResult {
  final bool success;
  final List<File> backupFiles;
  final String directoryPath;
  final int totalFiles;
  final int totalBytes;
  final String? errorMessage;

  const BackupExportResult({
    required this.success,
    required this.backupFiles,
    required this.directoryPath,
    required this.totalFiles,
    required this.totalBytes,
    this.errorMessage,
  });

  String get formattedTotalSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) return '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class BackupManifestSummary {
  final int totalNovels;
  final int totalChapters;
  final int totalAudiobooks;
  final int totalBytes;
  final int totalBatches;
  final List<String> novelTitles;

  const BackupManifestSummary({
    required this.totalNovels,
    required this.totalChapters,
    required this.totalAudiobooks,
    required this.totalBytes,
    required this.totalBatches,
    required this.novelTitles,
  });

  String get formattedTotalSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) return '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class BackupImportResult {
  final bool success;
  final int restoredNovelsCount;
  final int restoredChaptersCount;
  final int restoredAudiobooksCount;
  final String? errorMessage;

  const BackupImportResult({
    required this.success,
    required this.restoredNovelsCount,
    required this.restoredChaptersCount,
    required this.restoredAudiobooksCount,
    this.errorMessage,
  });
}

class BackupService {
  final StorageService _storageService;

  // 1.5 GB limit per batch in bytes (1.5 * 1024 * 1024 * 1024 = 1,610,612,736 bytes)
  static const int defaultBatchSizeBytes = 1610612736;

  BackupService({StorageService? storageService})
      : _storageService = storageService ?? StorageService();

  /// Gets the directory where export files are saved.
  Future<Directory> getBackupDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Backup export is not supported on web platform');
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${appDocDir.path}/NovelsWorld_Backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Exports all downloaded novels, chapters, audiobooks, translations, and metadata.
  Future<BackupExportResult> exportBackup({
    BackupMode mode = BackupMode.monolithic,
    int maxBatchSizeBytes = defaultBatchSizeBytes,
    Directory? customDestinationDir,
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      await _storageService.init();
      final destinationDir = customDestinationDir ?? await getBackupDirectory();
      if (!await destinationDir.exists()) {
        await destinationDir.create(recursive: true);
      }

      onProgress?.call(0.05, 'Scanning downloaded library content...');

      final novels = await _storageService.getDownloadedNovels();
      if (novels.isEmpty) {
        return BackupExportResult(
          success: true,
          backupFiles: [],
          directoryPath: destinationDir.path,
          totalFiles: 0,
          totalBytes: 0,
        );
      }

      // Collect novel items
      final novelItems = <BackupManifestNovel>[];
      final novelFileMap = <String, List<BackupFileItem>>{};

      int grandTotalFiles = 0;
      int grandTotalBytes = 0;

      for (int i = 0; i < novels.length; i++) {
        final novel = novels[i];
        final chapters = await _storageService.getCachedChapters(novel.id) ?? [];
        final downloadedChapterIds = _storageService.getDownloadedChapterIds(novel.id).toList();
        final progress = _storageService.getProgress(novel.id);
        final readChapterIds = _storageService.getReadChapterIds(novel.id).toList();

        final fileItems = <BackupFileItem>[];
        final audiobookPaths = <String>[];
        final translationPaths = <String>[];

        // 1. Text chapters
        for (final chId in downloadedChapterIds) {
          final safeName = chId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
          final chFile = File('${_storageService.chaptersDirectoryPath}/$safeName.json');
          if (chFile.existsSync()) {
            final len = chFile.lengthSync();
            fileItems.add(BackupFileItem(
              file: chFile,
              relativeZipPath: 'chapters/$safeName.json',
              byteSize: len,
            ));
          }
        }

        // 2. Audiobooks
        final novelAudioDir = _storageService.getNovelAudiobookDirectory(novel.id);
        if (novelAudioDir.existsSync()) {
          final audioEntities = novelAudioDir.listSync().whereType<File>();
          for (final f in audioEntities) {
            if (f.path.endsWith('.mp3')) {
              final fileName = f.uri.pathSegments.last;
              final relPath = 'audiobooks/${novel.id}/$fileName';
              audiobookPaths.add(relPath);
              fileItems.add(BackupFileItem(
                file: f,
                relativeZipPath: relPath,
                byteSize: f.lengthSync(),
              ));
            }
          }
        }

        // 3. Translations
        final novelTransDir = Directory('${_storageService.translationsDirectoryPath}/${novel.id}');
        if (novelTransDir.existsSync()) {
          final transEntities = novelTransDir.listSync().whereType<File>();
          for (final f in transEntities) {
            if (f.path.endsWith('.json')) {
              final fileName = f.uri.pathSegments.last;
              final relPath = 'translations/${novel.id}/$fileName';
              translationPaths.add(relPath);
              fileItems.add(BackupFileItem(
                file: f,
                relativeZipPath: relPath,
                byteSize: f.lengthSync(),
              ));
            }
          }
        }

        // 4. Imported novel folder if EPUB / full book
        final importedNovelDir = Directory('${_storageService.appDirectoryPath}/imported_novels/${novel.id}');
        if (importedNovelDir.existsSync()) {
          final importedFiles = importedNovelDir.listSync(recursive: true).whereType<File>();
          for (final f in importedFiles) {
            final relSub = f.path.substring(importedNovelDir.path.length + 1);
            final relPath = 'imported_novels/${novel.id}/$relSub';
            fileItems.add(BackupFileItem(
              file: f,
              relativeZipPath: relPath,
              byteSize: f.lengthSync(),
            ));
          }
        }

        novelItems.add(BackupManifestNovel(
          novel: novel,
          chapters: chapters,
          downloadedChapterIds: downloadedChapterIds,
          audiobookFiles: audiobookPaths,
          translationFiles: translationPaths,
          progress: progress,
          readChapterIds: readChapterIds,
        ));

        novelFileMap[novel.id] = fileItems;
        grandTotalFiles += fileItems.length;
        for (final item in fileItems) {
          grandTotalBytes += item.byteSize;
        }
      }

      onProgress?.call(0.15, 'Grouping archive volumes...');

      // Slicing into batches
      final batches = <_BackupBatchPlan>[];
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      if (mode == BackupMode.monolithic) {
        final allItems = <BackupFileItem>[];
        for (final n in novelItems) {
          allItems.addAll(novelFileMap[n.novel.id] ?? []);
        }
        batches.add(_BackupBatchPlan(
          index: 1,
          novels: List.from(novelItems),
          files: allItems,
        ));
      } else {
        // Split Batches (1.5 GB limit with atomic chapter integrity)
        int currentBatchIdx = 1;
        var currentBatchFiles = <BackupFileItem>[];
        var currentBatchNovels = <BackupManifestNovel>[];
        int currentBatchBytes = 0;

        for (final n in novelItems) {
          final nFiles = novelFileMap[n.novel.id] ?? [];
          final nBytes = nFiles.fold<int>(0, (sum, f) => sum + f.byteSize);

          // If adding this novel exceeds batch limit and batch already has content, seal current batch
          if (currentBatchBytes + nBytes > maxBatchSizeBytes && currentBatchFiles.isNotEmpty) {
            batches.add(_BackupBatchPlan(
              index: currentBatchIdx,
              novels: currentBatchNovels,
              files: currentBatchFiles,
            ));
            currentBatchIdx++;
            currentBatchFiles = <BackupFileItem>[];
            currentBatchNovels = <BackupManifestNovel>[];
            currentBatchBytes = 0;
          }

          currentBatchNovels.add(n);
          currentBatchFiles.addAll(nFiles);
          currentBatchBytes += nBytes;
        }

        if (currentBatchFiles.isNotEmpty || currentBatchNovels.isNotEmpty) {
          batches.add(_BackupBatchPlan(
            index: currentBatchIdx,
            novels: currentBatchNovels,
            files: currentBatchFiles,
          ));
        }
      }

      final totalBatches = batches.length;
      final createdFiles = <File>[];
      final dateStr = DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '');

      // Encode batches to disk
      int processedFilesCount = 0;

      for (int b = 0; b < totalBatches; b++) {
        final batch = batches[b];
        final zipName = totalBatches == 1
            ? 'NovelsWorld_Backup_$dateStr.zip'
            : 'NovelsWorld_Backup_${dateStr}_Part${b + 1}.zip';
        final zipFile = File('${destinationDir.path}/$zipName');
        if (zipFile.existsSync()) {
          zipFile.deleteSync();
        }

        final encoder = ZipFileEncoder();
        encoder.create(zipFile.path);

        // Add files
        for (final item in batch.files) {
          if (item.file.existsSync()) {
            await encoder.addFile(item.file, item.relativeZipPath);
          }
          processedFilesCount++;
          final pct = 0.20 + (0.75 * (processedFilesCount / (grandTotalFiles > 0 ? grandTotalFiles : 1)));
          onProgress?.call(
            pct.clamp(0.0, 0.95),
            'Archiving Part ${b + 1}/$totalBatches: ${item.relativeZipPath}',
          );
        }

        // Generate manifest for this batch
        final batchManifest = BackupManifest(
          app: 'NovelsWorld',
          schemaVersion: 1,
          exportTimestamp: timestamp,
          batchIndex: b + 1,
          totalBatches: totalBatches,
          novels: batch.novels,
          fileCount: batch.files.length,
          totalBytes: batch.files.fold<int>(0, (sum, f) => sum + f.byteSize),
        );

        final manifestTmp = File('${destinationDir.path}/.tmp_manifest_${b + 1}.json');
        await manifestTmp.writeAsString(jsonEncode(batchManifest.toJson()));
        await encoder.addFile(manifestTmp, 'manifest.json');
        encoder.close();

        if (manifestTmp.existsSync()) {
          manifestTmp.deleteSync();
        }

        createdFiles.add(zipFile);
      }

      onProgress?.call(1.0, 'Export complete!');

      return BackupExportResult(
        success: true,
        backupFiles: createdFiles,
        directoryPath: destinationDir.path,
        totalFiles: grandTotalFiles,
        totalBytes: grandTotalBytes,
      );
    } catch (e) {
      return BackupExportResult(
        success: false,
        backupFiles: [],
        directoryPath: customDestinationDir?.path ?? '',
        totalFiles: 0,
        totalBytes: 0,
        errorMessage: e.toString(),
      );
    }
  }

  /// Inspects selected backup zip files and returns a summary of their contents.
  Future<BackupManifestSummary> inspectBackup(List<String> zipPaths) async {
    int totalChapters = 0;
    int totalAudiobooks = 0;
    int totalBytes = 0;
    int totalBatches = zipPaths.length;
    final novelTitles = <String>{};

    for (final zipPath in zipPaths) {
      final zipFile = File(zipPath);
      if (!zipFile.existsSync()) continue;

      totalBytes += zipFile.lengthSync();

      try {
        final inputStream = InputFileStream(zipPath);
        final archive = ZipDecoder().decodeStream(inputStream);
        final manifestEntry = archive.findFile('manifest.json');
        if (manifestEntry != null) {
          final content = utf8.decode(manifestEntry.content as List<int>);
          final manifest = BackupManifest.fromJson(jsonDecode(content) as Map<String, dynamic>);
          totalBatches = manifest.totalBatches;
          for (final n in manifest.novels) {
            novelTitles.add(n.novel.title);
            totalChapters += n.downloadedChapterIds.length;
            totalAudiobooks += n.audiobookFiles.length;
          }
        }
      } catch (_) {}
    }

    return BackupManifestSummary(
      totalNovels: novelTitles.length,
      totalChapters: totalChapters,
      totalAudiobooks: totalAudiobooks,
      totalBytes: totalBytes,
      totalBatches: totalBatches,
      novelTitles: novelTitles.toList(),
    );
  }

  /// Restores downloaded novels, chapters, and audiobooks from selected zip archives.
  Future<BackupImportResult> restoreBackup({
    required List<String> zipPaths,
    RestoreMode mode = RestoreMode.safeMerge,
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      await _storageService.init();

      if (zipPaths.isEmpty) {
        return const BackupImportResult(
          success: false,
          restoredNovelsCount: 0,
          restoredChaptersCount: 0,
          restoredAudiobooksCount: 0,
          errorMessage: 'No backup zip files selected.',
        );
      }

      onProgress?.call(0.05, 'Preparing restore environment...');

      // Replace All: Wipe existing downloaded caches
      if (mode == RestoreMode.replaceAll) {
        await _storageService.clearAllDownloadedContent();
      }

      final stagingDir = Directory(
        '${_storageService.appDirectoryPath}/.staging_restore_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!await stagingDir.exists()) {
        await stagingDir.create(recursive: true);
      }

      int restoredNovelsCount = 0;
      int restoredChaptersCount = 0;
      int restoredAudiobooksCount = 0;

      for (int i = 0; i < zipPaths.length; i++) {
        final zipPath = zipPaths[i];
        final file = File(zipPath);
        if (!file.existsSync()) continue;

        onProgress?.call(
          0.10 + (0.40 * (i / zipPaths.length)),
          'Unpacking archive ${i + 1}/${zipPaths.length}...',
        );

        final partStagingDir = Directory('${stagingDir.path}/part_$i');
        await partStagingDir.create(recursive: true);
        await extractFileToDisk(zipPath, partStagingDir.path);

        // Read manifest.json
        final manifestFile = File('${partStagingDir.path}/manifest.json');
        if (!manifestFile.existsSync()) {
          continue;
        }

        final manifestRaw = await manifestFile.readAsString();
        final manifest = BackupManifest.fromJson(jsonDecode(manifestRaw) as Map<String, dynamic>);

        onProgress?.call(
          0.50 + (0.45 * (i / zipPaths.length)),
          'Merging chapters & audiobooks for ${manifest.novels.length} novels...',
        );

        // Commit extracted files into target app directories
        for (final manifestNovel in manifest.novels) {
          final novel = manifestNovel.novel;

          // 1. Move text chapters
          final targetChaptersDir = Directory(_storageService.chaptersDirectoryPath);
          for (final chId in manifestNovel.downloadedChapterIds) {
            final safeName = chId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
            final src = File('${partStagingDir.path}/chapters/$safeName.json');
            final dst = File('${targetChaptersDir.path}/$safeName.json');
            if (src.existsSync()) {
              if (mode == RestoreMode.replaceAll || !dst.existsSync()) {
                await src.copy(dst.path);
              }
            }
          }

          // 2. Move audiobooks
          final targetAudioNovelDir = _storageService.getNovelAudiobookDirectory(novel.id);
          if (!await targetAudioNovelDir.exists()) {
            await targetAudioNovelDir.create(recursive: true);
          }
          final srcAudioNovelDir = Directory('${partStagingDir.path}/audiobooks/${novel.id}');
          if (srcAudioNovelDir.existsSync()) {
            final audioFiles = srcAudioNovelDir.listSync().whereType<File>();
            for (final src in audioFiles) {
              final dst = File('${targetAudioNovelDir.path}/${src.uri.pathSegments.last}');
              if (mode == RestoreMode.replaceAll || !dst.existsSync()) {
                await src.copy(dst.path);
              }
            }
          }

          // 3. Move translations
          final targetTransNovelDir = Directory('${_storageService.translationsDirectoryPath}/${novel.id}');
          if (!await targetTransNovelDir.exists()) {
            await targetTransNovelDir.create(recursive: true);
          }
          final srcTransNovelDir = Directory('${partStagingDir.path}/translations/${novel.id}');
          if (srcTransNovelDir.existsSync()) {
            final transFiles = srcTransNovelDir.listSync().whereType<File>();
            for (final src in transFiles) {
              final dst = File('${targetTransNovelDir.path}/${src.uri.pathSegments.last}');
              if (mode == RestoreMode.replaceAll || !dst.existsSync()) {
                await src.copy(dst.path);
              }
            }
          }

          // 4. Move imported novels folder (if any)
          final srcImportedDir = Directory('${partStagingDir.path}/imported_novels/${novel.id}');
          if (srcImportedDir.existsSync()) {
            final targetImportedDir = Directory('${_storageService.appDirectoryPath}/imported_novels/${novel.id}');
            if (!await targetImportedDir.exists()) {
              await targetImportedDir.create(recursive: true);
            }
            final importedFiles = srcImportedDir.listSync(recursive: true).whereType<File>();
            for (final src in importedFiles) {
              final relSub = src.path.substring(srcImportedDir.path.length + 1);
              final dst = File('${targetImportedDir.path}/$relSub');
              if (!await dst.parent.exists()) {
                await dst.parent.create(recursive: true);
              }
              if (mode == RestoreMode.replaceAll || !dst.existsSync()) {
                await src.copy(dst.path);
              }
            }
          }

          // 5. Restore database metadata in StorageService
          await _storageService.restoreDownloadedNovelData(
            novel: novel,
            chapters: manifestNovel.chapters,
            downloadedChapterIds: manifestNovel.downloadedChapterIds.toSet(),
            progress: manifestNovel.progress,
            readChapterIds: manifestNovel.readChapterIds.toSet(),
          );

          restoredNovelsCount++;
          restoredChaptersCount += manifestNovel.downloadedChapterIds.length;
          restoredAudiobooksCount += manifestNovel.audiobookFiles.length;
        }
      }

      // Cleanup staging directory
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }

      onProgress?.call(1.0, 'Restore complete!');

      return BackupImportResult(
        success: true,
        restoredNovelsCount: restoredNovelsCount,
        restoredChaptersCount: restoredChaptersCount,
        restoredAudiobooksCount: restoredAudiobooksCount,
      );
    } catch (e) {
      return BackupImportResult(
        success: false,
        restoredNovelsCount: 0,
        restoredChaptersCount: 0,
        restoredAudiobooksCount: 0,
        errorMessage: e.toString(),
      );
    }
  }
}

class _BackupBatchPlan {
  final int index;
  final List<BackupManifestNovel> novels;
  final List<BackupFileItem> files;

  const _BackupBatchPlan({
    required this.index,
    required this.novels,
    required this.files,
  });
}
