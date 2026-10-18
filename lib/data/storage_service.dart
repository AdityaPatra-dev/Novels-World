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
}
