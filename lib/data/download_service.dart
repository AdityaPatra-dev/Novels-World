import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
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

class DownloadService extends ChangeNotifier {
  final StorageService _storage;
  final List<DownloadTask> _queue = [];
  bool _isProcessing = false;
  bool _isPaused = false;

  final Set<String> _downloadedChapterIds = {};

  DownloadService(this._storage) {
    _initDownloadedSet();
  }

  bool get isProcessing => _isProcessing;
  bool get isPaused => _isPaused;
  List<DownloadTask> get queue => _queue;
  int get activeQueueCount => _queue.where((t) => t.status == DownloadStatus.queued || t.status == DownloadStatus.downloading).length;

  int get completedInCurrentBatch => _queue.where((t) => t.status == DownloadStatus.completed).length;
  int get totalInCurrentBatch => _queue.length;

  double get batchProgress =>
      totalInCurrentBatch > 0 ? (completedInCurrentBatch / totalInCurrentBatch).clamp(0.0, 1.0) : 0.0;

  DownloadTask? get currentTask =>
      _queue.cast<DownloadTask?>().firstWhere(
            (t) => t?.status == DownloadStatus.downloading,
            orElse: () => null,
          );

  Future<void> _initDownloadedSet() async {
    // Initial check of downloaded items
    notifyListeners();
  }

  bool isChapterDownloaded(String chapterId) {
    return _downloadedChapterIds.contains(chapterId);
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

