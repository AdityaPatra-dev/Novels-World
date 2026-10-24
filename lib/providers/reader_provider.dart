import 'package:flutter/material.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/models/reading_progress.dart';
import '../data/storage_service.dart';
import '../extractors/source_registry.dart';
import '../tts/ring_buffer_manager.dart';

class ReaderProvider extends ChangeNotifier {
  final StorageService _storage;
  final RingBufferManager ttsManager = RingBufferManager();

  Novel? _novel;
  List<Chapter> _chapters = [];
  int _currentChapterIndex = -1;

  ChapterContent? _content;
  List<String> _sentences = [];
  int _activeSentenceIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;

  ReaderProvider(this._storage) {
    final saved = _storage.getSettings();
    ttsManager.switchEngine(saved.ttsEngine);
    ttsManager.setVoice(saved.ttsVoice);
    ttsManager.setSpeed(saved.ttsSpeed);

    ttsManager.addListener(() {
      notifyListeners();
    });

    ttsManager.onSentenceStarted = (idx) {
      setActiveSentence(idx);
    };

    ttsManager.onChapterFinished = () {
      if (hasNextChapter) {
        nextChapter();
      }
    };
  }

  void syncSettings(dynamic settings) {
    if (settings == null) return;
    if (ttsManager.activeEngine.id != settings.ttsEngine) {
      ttsManager.switchEngine(settings.ttsEngine);
    }
    if (ttsManager.activeVoice != settings.ttsVoice) {
      ttsManager.setVoice(settings.ttsVoice);
    }
  }

  Novel? get novel => _novel;
  Chapter? get currentChapter =>
      _currentChapterIndex >= 0 && _currentChapterIndex < _chapters.length
          ? _chapters[_currentChapterIndex]
          : null;
  ChapterContent? get content => _content;
  List<String> get sentences => _sentences;
  int get activeSentenceIndex => _activeSentenceIndex;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTtsPlaying => ttsManager.isPlaying;

  bool get hasPreviousChapter => _currentChapterIndex > 0;
  bool get hasNextChapter => _currentChapterIndex < _chapters.length - 1;

  Future<void> initializeNovelReader({
    required Novel novel,
    required List<Chapter> chapters,
    required Chapter initialChapter,
  }) async {
    _novel = novel;
    _chapters = chapters;
    _currentChapterIndex = chapters.indexWhere((c) => c.id == initialChapter.id);
    if (_currentChapterIndex == -1 && chapters.isNotEmpty) {
      _currentChapterIndex = 0;
    }
    await loadCurrentChapter();
  }

  Future<void> loadCurrentChapter() async {
    final chapter = currentChapter;
    if (chapter == null || _novel == null) return;

    await ttsManager.stop();

    _isLoading = true;
    _errorMessage = null;
    _content = null;
    _sentences = [];
    _activeSentenceIndex = 0;
    notifyListeners();

    try {
      // 1. Check local offline cache
      ChapterContent? loadedContent = await _storage.getCachedChapterContent(chapter.id);

      if (loadedContent == null) {
        final source = SourceRegistry.getSource(_novel!.sourceId) ?? SourceRegistry.getDefaultSource();
        final fetched = await source.getChapterContent(chapter.url);
        final populated = ChapterContent(
          chapterId: chapter.id,
          novelId: _novel!.id,
          title: fetched.title.isNotEmpty ? fetched.title : chapter.title,
          rawText: fetched.rawText,
          paragraphs: fetched.paragraphs,
        );
        loadedContent = populated;
        await _storage.cacheChapterContent(populated);
      }

      _content = loadedContent;
      _sentences = loadedContent.toSentences();

      // Restore saved progress if available
      final progress = _storage.getProgress(_novel!.id);
      if (progress != null && progress.chapterId == chapter.id) {
        _activeSentenceIndex = progress.activeSentenceIndex.clamp(0, _sentences.length - 1);
      }

      // Load sentences into the real-time TTS streaming ring-buffer
      ttsManager.loadSentences(_sentences, startIndex: _activeSentenceIndex);

      _isLoading = false;
      notifyListeners();

      // Record last read
      await _storage.saveProgress(
        ReadingProgress(
          novelId: _novel!.id,
          chapterId: chapter.id,
          activeSentenceIndex: _activeSentenceIndex,
          lastReadAt: DateTime.now(),
        ),
      );
    } catch (e) {
      _errorMessage = 'Failed to load chapter content: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> nextChapter() async {
    if (hasNextChapter) {
      _currentChapterIndex++;
      await loadCurrentChapter();
    }
  }

  Future<void> previousChapter() async {
    if (hasPreviousChapter) {
      _currentChapterIndex--;
      await loadCurrentChapter();
    }
  }

  void setActiveSentence(int index) {
    if (index >= 0 && index < _sentences.length) {
      _activeSentenceIndex = index;
      notifyListeners();
      if (_novel != null && currentChapter != null) {
        _storage.saveProgress(
          ReadingProgress(
            novelId: _novel!.id,
            chapterId: currentChapter!.id,
            activeSentenceIndex: index,
            lastReadAt: DateTime.now(),
          ),
        );
      }
    }
  }

  void toggleTtsPlayback() {
    if (ttsManager.isPlaying) {
      ttsManager.pause();
    } else {
      ttsManager.resume();
    }
  }

  void playFromSentence(int index) {
    setActiveSentence(index);
    ttsManager.playFrom(index);
  }

  void stopTts() {
    ttsManager.stop();
  }

  @override
  void dispose() {
    ttsManager.dispose();
    super.dispose();
  }
}
