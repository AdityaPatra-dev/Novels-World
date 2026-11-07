import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/models/reading_progress.dart';
import '../core/services/cloud_sync_service.dart';
import '../core/models/reader_settings.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _libraryKey = 'novels_world_library';
  static const String _settingsKey = 'novels_world_reader_settings';
  static const String _downloadedNovelsKey = 'novels_world_downloaded_novels';

  SharedPreferences? _prefs;
  Directory? _appDir;

  SharedPreferences get _safePrefs => _prefs!;
  Directory get _safeAppDir => _appDir!;

  String get chaptersDirectoryPath => '${_safeAppDir.path}/chapters';
  String get appDocumentsDirectoryPath => _safeAppDir.path;

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
    try {
      CloudSyncService.instance.syncNovel(updatedNovel);
    } catch (_) {}
  }

  Future<void> removeNovelFromLibrary(String novelId) async {
    final list = getLibraryNovels();
    list.removeWhere((n) => n.id == novelId);
    final rawList = list.map((n) => jsonEncode(n.toJson())).toList();
    await _safePrefs.setStringList(_libraryKey, rawList);
    try {
      CloudSyncService.instance.deleteNovel(novelId);
    } catch (_) {}
  }

  bool isNovelInLibrary(String novelId) {
    return getLibraryNovels().any((n) => n.id == novelId);
  }

  // --- Reading Progress & Chapter History ---

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

    // Record chapter as read in novel's read-history set
    await markChapterAsRead(progress.novelId, progress.chapterId);

    // Sync to Cloud
    try {
      CloudSyncService.instance.syncProgress(progress);
    } catch (_) {}

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

  Set<String> getReadChapterIds(String novelId) {
    final list = _safePrefs.getStringList('read_chapters_$novelId') ?? [];
    return list.toSet();
  }

  Future<void> markChapterAsRead(String novelId, String chapterId) async {
    final set = getReadChapterIds(novelId);
    if (set.add(chapterId)) {
      await _safePrefs.setStringList('read_chapters_$novelId', set.toList());
      try {
        CloudSyncService.instance.syncReadChapters(novelId, set);
      } catch (_) {}
    }
  }

  Future<void> markChapterAsUnread(String novelId, String chapterId) async {
    final set = getReadChapterIds(novelId);
    if (set.remove(chapterId)) {
      await _safePrefs.setStringList('read_chapters_$novelId', set.toList());
      try {
        CloudSyncService.instance.syncReadChapters(novelId, set);
      } catch (_) {}
    }
  }

  Future<void> markChaptersAsRead(String novelId, Iterable<String> chapterIds) async {
    final set = getReadChapterIds(novelId);
    set.addAll(chapterIds);
    await _safePrefs.setStringList('read_chapters_$novelId', set.toList());
    try {
      CloudSyncService.instance.syncReadChapters(novelId, set);
    } catch (_) {}
  }

  Future<void> clearReadChapters(String novelId) async {
    await _safePrefs.remove('read_chapters_$novelId');
    await _safePrefs.remove('progress_$novelId');
    try {
      CloudSyncService.instance.deleteProgress(novelId);
    } catch (_) {}
  }

  bool isChapterRead(String novelId, String chapterId) {
    return getReadChapterIds(novelId).contains(chapterId);
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
    await removeDownloadedNovel(novel.id);
  }

  // --- Downloaded Novels Index & Management ---

  // --- Novel Chapter List & Details Caching ---

  File _getNovelChaptersCacheFile(String novelId) {
    final safeName = novelId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${_safeAppDir.path}/novel_cache/chapters_$safeName.json');
  }

  Future<void> cacheChapterList(String novelId, List<Chapter> chapters) async {
    await init();
    try {
      final dir = Directory('${_safeAppDir.path}/novel_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = _getNovelChaptersCacheFile(novelId);
      final rawList = chapters.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(rawList));
    } catch (_) {}
  }

  Future<List<Chapter>?> getCachedChapters(String novelId) async {
    await init();
    final file = _getNovelChaptersCacheFile(novelId);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => Chapter.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  File _getNovelDetailsCacheFile(String novelId) {
    final safeName = novelId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${_safeAppDir.path}/novel_cache/details_$safeName.json');
  }

  Future<void> cacheNovelDetails(Novel novel) async {
    await init();
    try {
      final dir = Directory('${_safeAppDir.path}/novel_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = _getNovelDetailsCacheFile(novel.id);
      await file.writeAsString(jsonEncode(novel.toJson()));
    } catch (_) {}
  }

  Future<Novel?> getCachedNovelDetails(String novelId) async {
    await init();
    final file = _getNovelDetailsCacheFile(novelId);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return Novel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> recordDownloadedNovel(Novel novel, String chapterId) async {
    await init();
    // Track downloaded chapter ID
    final chSet = getDownloadedChapterIds(novel.id);
    chSet.add(chapterId);
    await _safePrefs.setStringList('downloaded_chapters_${novel.id}', chSet.toList());

    // Track novel metadata
    final list = _getDownloadedNovelsList();
    final idx = list.indexWhere((n) => n.id == novel.id);
    if (idx >= 0) {
      list[idx] = novel;
    } else {
      list.insert(0, novel);
    }
    final rawList = list.map((n) => jsonEncode(n.toJson())).toList();
    await _safePrefs.setStringList(_downloadedNovelsKey, rawList);
  }

  Set<String> getDownloadedChapterIds(String novelId) {
    if (_prefs == null) return {};
    final list = _safePrefs.getStringList('downloaded_chapters_$novelId') ?? [];
    return list.toSet();
  }

  List<Novel> _getDownloadedNovelsList() {
    if (_prefs == null) return [];
    final rawList = _safePrefs.getStringList(_downloadedNovelsKey) ?? [];
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

  Future<List<Novel>> getDownloadedNovels() async {
    await init();
    final downloadedList = _getDownloadedNovelsList();
    final novelMap = <String, Novel>{};
    for (final n in downloadedList) {
      novelMap[n.id] = n;
    }

    // Also include any library novels that are local_epub or have downloaded chapters
    for (final n in getLibraryNovels()) {
      if (n.sourceId == 'local_epub') {
        novelMap[n.id] = n;
      } else {
        final chs = getDownloadedChapterIds(n.id);
        if (chs.isNotEmpty) {
          novelMap[n.id] = n;
        }
      }
    }

    return novelMap.values.toList();
  }

  Future<void> removeDownloadedNovel(String novelId) async {
    await init();
    final list = _getDownloadedNovelsList()..removeWhere((n) => n.id == novelId);
    final rawList = list.map((n) => jsonEncode(n.toJson())).toList();
    await _safePrefs.setStringList(_downloadedNovelsKey, rawList);
    await _safePrefs.remove('downloaded_chapters_$novelId');
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
