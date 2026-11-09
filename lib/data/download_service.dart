import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/services/epub_service.dart';
import '../core/services/webview_session_manager.dart';
import '../core/utils/chapter_range_parser.dart';
import '../extractors/source_registry.dart';
import 'storage_service.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
}

class DownloadTask {
  final Novel novel;
  final Chapter chapter;
  DownloadStatus status;
  int retryCount;
  String? error;

  DownloadTask({
    required this.novel,
    required this.chapter,
    this.status = DownloadStatus.queued,
    this.retryCount = 0,
    this.error,
  });
}

class BookDownloadTask {
  final Novel novel;
  final String downloadUrl;
  DownloadStatus status;
  double progress; // 0.0 to 1.0
  int receivedBytes;
  int totalBytes;
  String? error;
  String stage; // 'Connecting', 'Downloading', 'Verifying', 'Extracting', 'Completed'

  BookDownloadTask({
    required this.novel,
    required this.downloadUrl,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.stage = 'Connecting',
  });
}

class DownloadService extends ChangeNotifier {
  final StorageService _storage;
  final List<DownloadTask> _queue = [];
  final List<BookDownloadTask> _bookTasks = [];
  bool _isProcessing = false;
  bool _isPaused = false;

  final Set<String> _downloadedChapterIds = {};

  DownloadService(this._storage) {
    _initDownloadedSet();
  }

  bool get isProcessing => _isProcessing;
  bool get isPaused => _isPaused;
  List<DownloadTask> get queue => _queue;
  List<BookDownloadTask> get bookTasks => _bookTasks;

  int get activeQueueCount =>
      _queue.where((t) => t.status == DownloadStatus.queued || t.status == DownloadStatus.downloading).length +
      _bookTasks.where((t) => t.status == DownloadStatus.queued || t.status == DownloadStatus.downloading).length;

  int get completedInCurrentBatch => _queue.where((t) => t.status == DownloadStatus.completed).length;
  int get totalInCurrentBatch => _queue.length;

  double get batchProgress =>
      totalInCurrentBatch > 0 ? (completedInCurrentBatch / totalInCurrentBatch).clamp(0.0, 1.0) : 0.0;

  DownloadTask? get currentTask =>
      _queue.cast<DownloadTask?>().firstWhere(
            (t) => t?.status == DownloadStatus.downloading,
            orElse: () => null,
          );

  BookDownloadTask? get currentBookTask =>
      _bookTasks.cast<BookDownloadTask?>().firstWhere(
            (t) => t?.status == DownloadStatus.downloading,
            orElse: () => null,
          );

  Future<void> _initDownloadedSet() async {
    notifyListeners();
  }

  bool isChapterDownloaded(String chapterId) {
    return _downloadedChapterIds.contains(chapterId);
  }

  bool isBookDownloaded(String novelId) {
    // Check if book exists in downloaded tasks or library
    if (_bookTasks.any((t) => t.novel.id == novelId && t.status == DownloadStatus.completed)) {
      return true;
    }
    return _storage.isNovelInLibrary(novelId);
  }

  bool isDownloadingBook(String novelId) =>
      _bookTasks.any((t) => t.novel.id == novelId && t.status == DownloadStatus.downloading);

  Map<String, BookDownloadTask> get activeBookDownloads {
    final map = <String, BookDownloadTask>{};
    for (final t in _bookTasks) {
      if (t.status == DownloadStatus.downloading) {
        map[t.novel.id] = t;
      }
    }
    return map;
  }

  BookDownloadTask? getBookTask(String novelId) {
    return _bookTasks.cast<BookDownloadTask?>().firstWhere(
          (t) => t?.novel.id == novelId,
          orElse: () => null,
        );
  }

  Future<void> checkChaptersDownloaded(List<Chapter> chapters) async {
    for (final ch in chapters) {
      if (await _storage.isChapterDownloaded(ch.id)) {
        _downloadedChapterIds.add(ch.id);
      }
    }
    notifyListeners();
  }

  Future<void> enqueueChapters(Novel novel, List<Chapter> chapters) async {
    for (final ch in chapters) {
      // Don't enqueue if already downloaded or already in active queue
      if (_downloadedChapterIds.contains(ch.id)) continue;
      if (_queue.any((t) => t.chapter.id == ch.id && t.status != DownloadStatus.failed)) continue;

      _queue.add(
        DownloadTask(
          novel: novel,
          chapter: ch,
          status: DownloadStatus.queued,
        ),
      );
    }
    notifyListeners();
    _processQueue();
  }

  Future<void> enqueueNextUnread(Novel novel, List<Chapter> allChapters, int count) async {
    final List<Chapter> toDownload = [];
    for (final ch in allChapters) {
      if (!_downloadedChapterIds.contains(ch.id) && !_queue.any((t) => t.chapter.id == ch.id)) {
        toDownload.add(ch);
        if (toDownload.length >= count) break;
      }
    }
    await enqueueChapters(novel, toDownload);
  }

  Future<void> enqueueAllUnread(Novel novel, List<Chapter> allChapters) async {
    final List<Chapter> toDownload = allChapters
        .where((ch) => !_downloadedChapterIds.contains(ch.id) && !_queue.any((t) => t.chapter.id == ch.id))
        .toList();
    await enqueueChapters(novel, toDownload);
  }

  /// Parses ranges like "1-40", "1-30,40-50", "1,2", "30" and enqueues matched chapters
  Future<int> enqueueRange(Novel novel, List<Chapter> allChapters, String rangeText) async {
    final requestedNumbers = ChapterRangeParser.parseRange(rangeText);
    final matchingChapters = ChapterRangeParser.filterChapters(allChapters, requestedNumbers);
    await enqueueChapters(novel, matchingChapters);
    return matchingChapters.length;
  }

  /// Downloads an entire book in a single atomic stream and automatically unpacks it.
  Future<Novel> downloadEntireBook({
    required Novel novel,
    String? downloadUrl,
    void Function(double progress, String stage)? onProgress,
  }) async {
    final effectiveUrl = downloadUrl ?? novel.bookDownloadUrl ?? novel.sourceUrl;
    if (effectiveUrl.isEmpty) {
      throw ArgumentError('No valid download URL provided for complete book');
    }

    // Check if task already exists
    BookDownloadTask task;
    final existingIndex = _bookTasks.indexWhere((t) => t.novel.id == novel.id);
    if (existingIndex >= 0) {
      task = _bookTasks[existingIndex];
      if (task.status == DownloadStatus.downloading) {
        throw StateError('Book is already downloading');
      }
      task.status = DownloadStatus.downloading;
      task.error = null;
      task.progress = 0.0;
      task.stage = 'Connecting';
    } else {
      task = BookDownloadTask(
        novel: novel,
        downloadUrl: effectiveUrl,
        status: DownloadStatus.downloading,
        stage: 'Connecting',
      );
      _bookTasks.insert(0, task);
    }
    notifyListeners();

    try {
      final headers = <String, String>{
        'User-Agent': WebViewSessionManager.defaultUserAgent,
        'Accept': '*/*',
      };

      final cookie = WebViewSessionManager.instance.getCookieHeader(effectiveUrl);
      if (cookie != null && cookie.isNotEmpty) {
        headers['Cookie'] = cookie;
      }

      final importedNovel = await EpubService().importEpubFromUrl(
        effectiveUrl,
        headers: headers,
        originalNovel: novel,
        onProgress: (p, stage) {
          task.progress = p;
          task.stage = stage;
          onProgress?.call(p, stage);
          notifyListeners();
        },
      );

      // Save to library and record download
      await _storage.saveNovelToLibrary(importedNovel);
      await _storage.recordDownloadedNovel(importedNovel, 'complete_book');

      try {
        final localExtractor = SourceRegistry.getSource('local_epub');
        if (localExtractor != null) {
          final chapters = await localExtractor.getChapterList(importedNovel.sourceUrl);
          if (chapters.isNotEmpty) {
            await _storage.cacheChapterList(importedNovel.id, chapters);
            await _storage.cacheNovelDetails(importedNovel);
            for (final ch in chapters) {
              _downloadedChapterIds.add(ch.id);
            }
          }
        }
      } catch (_) {}

      task.status = DownloadStatus.completed;
      task.stage = 'Completed';
      task.progress = 1.0;
      notifyListeners();

      return importedNovel;
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      task.stage = 'Failed';
      notifyListeners();
      rethrow;
    }
  }

  void cancelBookDownload(String novelId) {
    _bookTasks.removeWhere((t) => t.novel.id == novelId && t.status != DownloadStatus.completed);
    notifyListeners();
  }

  void pause() {
    _isPaused = true;
    notifyListeners();
  }

  void resume() {
    if (_isPaused) {
      _isPaused = false;
      notifyListeners();
      _processQueue();
    }
  }

  void cancelAll() {
    _queue.clear();
    _bookTasks.removeWhere((t) => t.status != DownloadStatus.completed);
    _isProcessing = false;
    _isPaused = false;
    notifyListeners();
  }

  Future<void> deleteNovelDownloads(String novelId, List<Chapter> chapters) async {
    for (final ch in chapters) {
      await _storage.deleteDownloadedChapter(ch.id);
      _downloadedChapterIds.remove(ch.id);
    }
    _queue.removeWhere((t) => t.novel.id == novelId);
    _bookTasks.removeWhere((t) => t.novel.id == novelId);
    await _storage.removeDownloadedNovel(novelId);
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _isPaused) return;
    _isProcessing = true;
    notifyListeners();

    while (_queue.any((t) => t.status == DownloadStatus.queued) && !_isPaused) {
      final task = _queue.firstWhere((t) => t.status == DownloadStatus.queued);
      task.status = DownloadStatus.downloading;
      notifyListeners();

      try {
        final source = SourceRegistry.getSource(task.novel.sourceId) ?? SourceRegistry.getDefaultSource();
        final content = await source.getChapterContent(task.chapter.url);
        final populated = ChapterContent(
          chapterId: task.chapter.id,
          novelId: task.novel.id,
          title: content.title.isNotEmpty ? content.title : task.chapter.title,
          rawText: content.rawText,
          paragraphs: content.paragraphs,
        );
        await _storage.cacheChapterContent(populated);

        task.status = DownloadStatus.completed;
        _downloadedChapterIds.add(task.chapter.id);
        await _storage.recordDownloadedNovel(task.novel, task.chapter.id);
      } catch (e) {
        if (task.retryCount < 2) {
          task.retryCount++;
          task.status = DownloadStatus.queued; // Re-queue for retry
        } else {
          task.status = DownloadStatus.failed;
          task.error = e.toString();
        }
      }

      notifyListeners();

      // Gentle rate-limiting between chapter downloads (400ms delay) to avoid 429 rate limits
      await Future.delayed(const Duration(milliseconds: 400));
    }

    _isProcessing = false;
    notifyListeners();
  }
}
