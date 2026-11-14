import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/services/audiobook_assembler_service.dart';
import '../core/services/translation_service.dart';
import '../extractors/source_registry.dart';
import '../tts/services/edge_tts_client.dart';
import 'storage_service.dart';

enum AudiobookDownloadMode {
  textOnly,
  audiobookOnly,
  both,
}

enum AudiobookTaskStatus {
  queued,
  translating,
  synthesizing,
  completed,
  failed,
}

class AudiobookDownloadTask {
  final Novel novel;
  final Chapter chapter;
  final AudiobookDownloadMode mode;
  final String targetLang;
  final String voice;
  AudiobookTaskStatus status;
  double sentenceProgress; // 0.0 to 1.0
  String? error;
  int retryCount;

  AudiobookDownloadTask({
    required this.novel,
    required this.chapter,
    required this.mode,
    required this.targetLang,
    required this.voice,
    this.status = AudiobookTaskStatus.queued,
    this.sentenceProgress = 0.0,
    this.error,
    this.retryCount = 0,
  });
}

class AudiobookDownloadService extends ChangeNotifier {
  static final AudiobookDownloadService _instance = AudiobookDownloadService._internal();
  factory AudiobookDownloadService({
    StorageService? storage,
    AudiobookAssemblerService? assembler,
    TranslationService? translationService,
  }) {
    if (storage != null) _instance._storage = storage;
    if (assembler != null) _instance._assembler = assembler;
    if (translationService != null) _instance._translationService = translationService;
    return _instance;
  }
  AudiobookDownloadService._internal()
      : _storage = StorageService(),
        _assembler = AudiobookAssemblerService(),
        _translationService = TranslationService();

  StorageService _storage;
  AudiobookAssemblerService _assembler;
  TranslationService _translationService;

  final List<AudiobookDownloadTask> _queue = [];
  bool _isProcessing = false;
  bool _isPaused = false;

  bool get isProcessing => _isProcessing;
  bool get isPaused => _isPaused;
  List<AudiobookDownloadTask> get queue => _queue;

  int get queuedCount => _queue.where((t) => t.status == AudiobookTaskStatus.queued).length;
  int get completedCount => _queue.where((t) => t.status == AudiobookTaskStatus.completed).length;

  /// Enqueues a batch of chapters for dual-track text & audiobook downloading.
  void enqueueChapters({
    required Novel novel,
    required List<Chapter> chapters,
    required AudiobookDownloadMode mode,
    required String targetLang,
    required String voice,
  }) {
    for (final chapter in chapters) {
      // Avoid duplicate queued tasks
      final exists = _queue.any((t) =>
          t.novel.id == novel.id &&
          t.chapter.id == chapter.id &&
          (t.status == AudiobookTaskStatus.queued || t.status == AudiobookTaskStatus.synthesizing));
      if (!exists) {
        _queue.add(AudiobookDownloadTask(
          novel: novel,
          chapter: chapter,
          mode: mode,
          targetLang: targetLang,
          voice: voice,
        ));
      }
    }
    notifyListeners();
    _processQueue();
  }

  void pause() {
    _isPaused = true;
    notifyListeners();
  }

  void resume() {
    _isPaused = false;
    notifyListeners();
    _processQueue();
  }

  void clearCompleted() {
    _queue.removeWhere((t) => t.status == AudiobookTaskStatus.completed);
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _isPaused) return;
    _isProcessing = true;
    notifyListeners();

    while (_queue.any((t) => t.status == AudiobookTaskStatus.queued) && !_isPaused) {
      final task = _queue.firstWhere((t) => t.status == AudiobookTaskStatus.queued);
      try {
        await _downloadSingleTask(task);
        task.status = AudiobookTaskStatus.completed;
        await _storage.recordDownloadedNovel(task.novel, task.chapter.id);
      } catch (e) {
        debugPrint('[AudiobookDownloadService] Task failed: $e');
        if (task.retryCount < 2) {
          task.retryCount++;
          task.status = AudiobookTaskStatus.queued;
        } else {
          task.status = AudiobookTaskStatus.failed;
          task.error = e.toString();
        }
      }
      notifyListeners();
      // Rate-limiting delay between chapters to avoid 429
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _isProcessing = false;
    notifyListeners();
  }

  Future<void> _downloadSingleTask(AudiobookDownloadTask task) async {
    // 1. Fetch or load ChapterContent
    ChapterContent? content = await _storage.getCachedChapterContent(task.chapter.id);
    if (content == null || content.paragraphs.isEmpty) {
      final source = SourceRegistry.getSource(task.novel.sourceId) ?? SourceRegistry.getDefaultSource();
      final fetched = await source.getChapterContent(task.chapter.url);
      content = ChapterContent(
        chapterId: task.chapter.id,
        novelId: task.novel.id,
        title: fetched.title.isNotEmpty ? fetched.title : task.chapter.title,
        rawText: fetched.rawText,
        paragraphs: fetched.paragraphs,
      );
      if (task.mode != AudiobookDownloadMode.audiobookOnly && content.paragraphs.isNotEmpty) {
        await _storage.cacheChapterContent(content);
      }
    }

    // If textOnly, we are done
    if (task.mode == AudiobookDownloadMode.textOnly) {
      return;
    }

    // 2. Sentence Slicing & Translation
    var sentences = content.toSentences();
    if (sentences.isEmpty) return;

    if (task.targetLang.toLowerCase() != 'en') {
      task.status = AudiobookTaskStatus.translating;
      notifyListeners();
      sentences = await _translationService.translateSentences(
        sentences,
        targetLang: task.targetLang,
        novelId: task.novel.id,
        chapterId: task.chapter.id,
      );
    }

    // 3. Synthesize sentences with concurrency control (max 2 parallel chunks)
    task.status = AudiobookTaskStatus.synthesizing;
    task.sentenceProgress = 0.0;
    notifyListeners();

    final tempDir = await Directory.systemTemp.createTemp('tts_dl_${task.chapter.id}_');
    final chunkPaths = <String>[];

    try {
      final cleanVoice = task.voice.split(' ').first.trim();
      const concurrency = 2;

      for (int i = 0; i < sentences.length; i += concurrency) {
        final end = (i + concurrency < sentences.length) ? i + concurrency : sentences.length;
        final slice = sentences.sublist(i, end);

        final futures = slice.asMap().entries.map((entry) async {
          final idx = i + entry.key;
          final sentence = entry.value.trim();
          if (sentence.isEmpty || sentence.startsWith('[IMAGE:')) return null;

          final chunkFile = File('${tempDir.path}/chunk_$idx.mp3');
          final bytes = await EdgeTtsClient.synthesizeToBytes(
            sentence,
            voice: cleanVoice,
            rate: '+0%',
            pitch: '+0Hz',
          );
          if (bytes != null && bytes.isNotEmpty) {
            await chunkFile.writeAsBytes(bytes);
            return chunkFile.path;
          }
          return null;
        }).toList();

        final results = await Future.wait(futures);
        for (final p in results) {
          if (p != null) chunkPaths.add(p);
        }

        task.sentenceProgress = (end / sentences.length).clamp(0.0, 1.0);
        notifyListeners();

        // 120ms gentle delay between sentence pairs
        await Future.delayed(const Duration(milliseconds: 120));
      }

      // 4. Assemble into permanent chapter MP3
      if (chunkPaths.isNotEmpty) {
        await _assembler.assembleChapterAudiobook(
          novelId: task.novel.id,
          chapterId: task.chapter.id,
          lang: task.targetLang,
          chunkFilePaths: chunkPaths,
          novel: task.novel,
          chapterTitle: task.chapter.title,
        );
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}
