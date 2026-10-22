import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/novel.dart';
import '../core/models/chapter_content.dart';
import '../core/models/reading_progress.dart';
import '../core/models/reader_settings.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _libraryKey = 'novels_world_library';
  static const String _settingsKey = 'novels_world_reader_settings';

  SharedPreferences? _prefs;
  Directory? _appDir;

  SharedPreferences get _safePrefs => _prefs!;
  Directory get _safeAppDir => _appDir!;

  Future<void> init({Directory? appDir}) async {
    if (_prefs != null && _appDir != null && appDir == null) return;
    _prefs = await SharedPreferences.getInstance();
    _appDir = appDir ?? _appDir ?? await getApplicationDocumentsDirectory();
    final chaptersDir = Directory('${_safeAppDir.path}/chapters');
    if (!await chaptersDir.exists()) {
      await chaptersDir.create(recursive: true);
    }
  }

  // --- Library Management ---

  List<Novel> getLibraryNovels() {
    final rawList = _safePrefs.getStringList(_libraryKey) ?? [];
    return rawList
        .map((str) {
          try {
            return Novel.fromJson(jsonDecode(str) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Novel>()
        .toList();
  }

  Future<void> saveNovelToLibrary(Novel novel) async {
    final list = getLibraryNovels();
    final index = list.indexWhere((n) => n.id == novel.id);
    final updatedNovel = novel.copyWith(inLibrary: true);

    if (index >= 0) {
      list[index] = updatedNovel;
    } else {
      list.insert(0, updatedNovel);
    }

    final rawList = list.map((n) => jsonEncode(n.toJson())).toList();
    await _safePrefs.setStringList(_libraryKey, rawList);
  }

  Future<void> removeNovelFromLibrary(String novelId) async {
    final list = getLibraryNovels();
    list.removeWhere((n) => n.id == novelId);
    final rawList = list.map((n) => jsonEncode(n.toJson())).toList();
    await _safePrefs.setStringList(_libraryKey, rawList);
  }

  bool isNovelInLibrary(String novelId) {
    return getLibraryNovels().any((n) => n.id == novelId);
  }

  // --- Reading Progress ---

  ReadingProgress? getProgress(String novelId) {
    final raw = _safePrefs.getString('progress_$novelId');
    if (raw == null) return null;
    try {
      return ReadingProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    await _safePrefs.setString('progress_${progress.novelId}', jsonEncode(progress.toJson()));

    // Also update novel in library last read info
    final library = getLibraryNovels();
    final idx = library.indexWhere((n) => n.id == progress.novelId);
    if (idx >= 0) {
      final updated = library[idx].copyWith(
        lastReadChapterId: progress.chapterId,
        lastReadAt: progress.lastReadAt,
      );
      library[idx] = updated;
      await _safePrefs.setStringList(
        _libraryKey,
        library.map((n) => jsonEncode(n.toJson())).toList(),
      );
    }
  }

  // --- Offline Chapter Caching ---

  File _getChapterFile(String chapterId) {
    final safeName = chapterId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${_safeAppDir.path}/chapters/$safeName.json');
  }

  Future<void> cacheChapterContent(ChapterContent content) async {
    final file = _getChapterFile(content.chapterId);
    await file.writeAsString(jsonEncode(content.toJson()));
  }

  Future<ChapterContent?> getCachedChapterContent(String chapterId) async {
    final file = _getChapterFile(chapterId);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return ChapterContent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isChapterDownloaded(String chapterId) async {
    final file = _getChapterFile(chapterId);
    return file.exists();
  }

  Future<void> deleteDownloadedChapter(String chapterId) async {
    final file = _getChapterFile(chapterId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteNovelChapters(List<String> chapterIds) async {
    for (final id in chapterIds) {
      await deleteDownloadedChapter(id);
    }
  }

  Future<double> getCacheSizeMb() async {
    final chaptersDir = Directory('${_safeAppDir.path}/chapters');
    if (!await chaptersDir.exists()) return 0.0;
    int totalBytes = 0;
    try {
      final files = chaptersDir.listSync().whereType<File>();
      for (final f in files) {
        totalBytes += await f.length();
      }
    } catch (_) {}
    return totalBytes / (1024 * 1024);
  }

  Future<int> getTotalCachedChapterCount() async {
    final chaptersDir = Directory('${_safeAppDir.path}/chapters');
    if (!await chaptersDir.exists()) return 0;
    try {
      return chaptersDir.listSync().whereType<File>().length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearAllChapterCache() async {
    final chaptersDir = Directory('${_safeAppDir.path}/chapters');
    if (await chaptersDir.exists()) {
      final files = chaptersDir.listSync().whereType<File>();
      for (final f in files) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  // --- Settings Persistence ---

  ReaderSettings getSettings() {
    final raw = _safePrefs.getString(_settingsKey);
    if (raw == null) return const ReaderSettings();
    try {
      return ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReaderSettings();
    }
  }

  Future<void> saveSettings(ReaderSettings settings) async {
    await _safePrefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  // --- Novel Specific Storage & Folder Inspector ---

  Future<NovelStorageInfo> getNovelStorageInfo(Novel novel) async {
    await init();
    if (novel.sourceId == 'local_epub') {
      String path = '';
      if (novel.sourceUrl.isNotEmpty) {
        final uri = Uri.tryParse(novel.sourceUrl);
        if (uri != null && uri.scheme == 'file') {
          path = uri.toFilePath();
        } else {
          path = novel.sourceUrl;
        }
      }
      if (path.isEmpty || !Directory(path).existsSync()) {
        path = '${_safeAppDir.path}/imported_novels/${novel.id}';
      }

      final dir = Directory(path);
      if (await dir.exists()) {
        final files = <File>[];
        int totalBytes = 0;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            files.add(entity);
            totalBytes += await entity.length();
          }
        }

        // Count chapters from metadata.json if available
        int chapterCount = 0;
        final metaFile = File('${dir.path}/metadata.json');
        if (await metaFile.exists()) {
          try {
            final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
            final chs = json['chapters'] as List?;
            chapterCount = chs?.length ?? 0;
          } catch (_) {}
        }
        if (chapterCount == 0) {
          chapterCount = files.where((f) => f.path.endsWith('.xhtml') || f.path.endsWith('.html')).length;
        }

        return NovelStorageInfo(
          directoryPath: dir.path,
          storageType: 'Local EPUB Container',
          chapterCount: chapterCount,
          totalSizeBytes: totalBytes,
          fileNames: files.map((f) => f.uri.pathSegments.last).toList(),
        );
      } else {
        return NovelStorageInfo(
          directoryPath: path,
          storageType: 'Local EPUB Container',
          chapterCount: 0,
          totalSizeBytes: 0,
          fileNames: const [],
        );
      }
    } else {
      // Scraped web novel chapters stored in chapters/ directory
      final chaptersDir = Directory('${_safeAppDir.path}/chapters');
      final matchingFiles = <File>[];
      int totalBytes = 0;
      if (await chaptersDir.exists()) {
        await for (final entity in chaptersDir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final raw = await entity.readAsString();
              if (raw.contains('"novelId":"${novel.id}"')) {
                matchingFiles.add(entity);
                totalBytes += await entity.length();
              }
            } catch (_) {}
          }
        }
      }

      return NovelStorageInfo(
        directoryPath: chaptersDir.path,
        storageType: 'Offline Web Chapter Cache',
        chapterCount: matchingFiles.length,
        totalSizeBytes: totalBytes,
        fileNames: matchingFiles.map((f) => f.uri.pathSegments.last).toList(),
      );
    }
  }

  Future<void> deleteNovelStorage(Novel novel) async {
    await init();
    if (novel.sourceId == 'local_epub') {
      String path = '';
      if (novel.sourceUrl.isNotEmpty) {
        final uri = Uri.tryParse(novel.sourceUrl);
        if (uri != null && uri.scheme == 'file') {
          path = uri.toFilePath();
        } else {
          path = novel.sourceUrl;
        }
      }
      if (path.isEmpty || !Directory(path).existsSync()) {
        path = '${_safeAppDir.path}/imported_novels/${novel.id}';
      }
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } else {
      final chaptersDir = Directory('${_safeAppDir.path}/chapters');
      if (await chaptersDir.exists()) {
        await for (final entity in chaptersDir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final raw = await entity.readAsString();
              if (raw.contains('"novelId":"${novel.id}"')) {
                await entity.delete();
              }
            } catch (_) {}
          }
        }
      }
    }
  }
}

class NovelStorageInfo {
  final String directoryPath;
  final String storageType;
  final int chapterCount;
  final int totalSizeBytes;
  final List<String> fileNames;

  const NovelStorageInfo({
    required this.directoryPath,
    required this.storageType,
    required this.chapterCount,
    required this.totalSizeBytes,
    required this.fileNames,
  });

  String get formattedSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
