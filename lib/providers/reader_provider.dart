import 'package:flutter/foundation.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';
import '../core/models/reading_progress.dart';
import '../core/services/epub_service.dart';
import '../core/services/translation_service.dart';
import '../data/storage_service.dart';
import '../extractors/source_registry.dart';
import '../tts/language_voice_registry.dart';
import '../tts/ring_buffer_manager.dart';
import '../tts/services/odia_transliteration.dart';
import '../tts/tts_model_registry.dart';

class ReaderProvider extends ChangeNotifier {
  final StorageService _storage;
  final TranslationService _translationService = TranslationService();
  final RingBufferManager ttsManager = RingBufferManager();

  Novel? _novel;
  List<Chapter> _chapters = [];
  int _currentChapterIndex = -1;

  ChapterContent? _content;
  List<String> _sentences = [];
  int _activeSentenceIndex = 0;
  bool _isLoading = false;
  String? _errorMessage;

  String? _targetLanguageCode;
  List<String>? _translatedSentences;
  bool _isTranslating = false;

  ChapterContent? _preloadedNextContent;
  List<String> _preloadedNextSentences = [];
  bool _isPreloadingNextChapter = false;

  ReaderProvider(this._storage) {
    final saved = _storage.getSettings();
    final defaultEngine = kIsWeb ? TtsModelRegistry.systemId : saved.ttsEngine;
    ttsManager.switchEngine(defaultEngine);
    ttsManager.setVoice(saved.ttsVoice);
    ttsManager.setSpeed(saved.ttsSpeed);

    ttsManager.addListener(() {
      notifyListeners();
    });

    ttsManager.onSentenceStarted = (idx) {
      setActiveSentence(idx);
    };

    ttsManager.onApproachingEndOfChapter = () {
      if (hasNextChapter) {
        _preloadNextChapter();
      }
    };

    ttsManager.onCrossChapterTransition = () {
      if (hasNextChapter && _preloadedNextContent != null) {
        _currentChapterIndex++;
        _content = _preloadedNextContent;
        _sentences = List<String>.from(_preloadedNextSentences);
        _activeSentenceIndex = 0;
        _preloadedNextContent = null;
        _preloadedNextSentences = [];
        if (_novel != null && currentChapter != null) {
          final savedProgress = _storage.getProgress(_novel!.id);
          final savedIdx = savedProgress != null
              ? _chapters.indexWhere((c) => c.id == savedProgress.chapterId || c.url == savedProgress.chapterId)
              : -1;
          if (savedProgress == null || savedIdx == -1 || _currentChapterIndex >= savedIdx) {
            _storage.saveProgress(
              ReadingProgress(
                novelId: _novel!.id,
                chapterId: currentChapter!.id,
                chapterTitle: currentChapter!.title,
                activeSentenceIndex: 0,
                lastReadAt: DateTime.now(),
              ),
            );
          }
        }
        notifyListeners();
      }
    };

    ttsManager.onChapterFinished = () {
      if (hasNextChapter && !ttsManager.isPlaying) {
        nextChapter();
      }
    };
  }

  void syncSettings(dynamic settings) {
    if (settings == null) return;
    final targetEngine = kIsWeb ? TtsModelRegistry.systemId : settings.ttsEngine;
    if (ttsManager.activeEngine.id != targetEngine) {
      ttsManager.switchEngine(targetEngine);
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
  List<String> get displaySentences => _translatedSentences ?? _sentences;
  int get activeSentenceIndex => _activeSentenceIndex;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTtsPlaying => ttsManager.isPlaying;

  bool get isTranslationActive => _targetLanguageCode != null;
  String? get targetLanguageCode => _targetLanguageCode;
  bool get isTranslating => _isTranslating;

  Future<void> translateCurrentChapter(LanguageVoiceInfo lang) async {
    if (_sentences.isEmpty || _novel == null || currentChapter == null) return;
    _targetLanguageCode = lang.code;
    _isTranslating = true;
    notifyListeners();

    try {
      final translated = await _translationService.translateSentences(
        _sentences,
        targetLang: lang.code,
        novelId: _novel!.id,
        chapterId: currentChapter!.id,
      );
      _translatedSentences = translated;
      _isTranslating = false;

      // Update TTS with new translated sentences and appropriate localized voice
      ttsManager.loadSentences(
        _translatedSentences!,
        startIndex: _activeSentenceIndex,
        novelId: _novel!.id,
        chapterId: currentChapter!.id,
        lang: lang.code,
        novel: _novel,
        chapterTitle: currentChapter!.title,
        trackNumber: _currentChapterIndex + 1,
      );
      ttsManager.setVoice(lang.defaultFemaleVoice);

      notifyListeners();
    } catch (e) {
      debugPrint('[ReaderProvider] Translation failed: $e');
      _isTranslating = false;
      notifyListeners();
    }
  }

  void disableTranslation() {
    _targetLanguageCode = null;
    _translatedSentences = null;
    _isTranslating = false;
    if (_novel != null && currentChapter != null) {
      ttsManager.loadSentences(
        _sentences,
        startIndex: _activeSentenceIndex,
        novelId: _novel!.id,
        chapterId: currentChapter!.id,
        lang: 'en',
        novel: _novel,
        chapterTitle: currentChapter!.title,
        trackNumber: _currentChapterIndex + 1,
      );
    }
    notifyListeners();
  }

  bool get hasPreviousChapter => _currentChapterIndex > 0;
  bool get hasNextChapter => _currentChapterIndex < _chapters.length - 1;
  double get savedScrollOffset => _storage.getProgress(_novel?.id ?? '')?.scrollOffset ?? 0.0;

  Future<void> initializeNovelReader({
    required Novel novel,
    required List<Chapter> chapters,
    required Chapter initialChapter,
  }) async {
    final isSameNovel = _novel?.id == novel.id;
    final targetIdx = chapters.indexWhere((c) => c.id == initialChapter.id);
    final isSameChapter = isSameNovel &&
        _currentChapterIndex == targetIdx &&
        _content != null &&
        targetIdx != -1;

    _novel = novel;
    _chapters = chapters;
    _currentChapterIndex = targetIdx != -1 ? targetIdx : 0;

    // If re-entering the SAME chapter that is already loaded:
    // Do NOT stop TTS and do NOT reset sentence index!
    if (isSameChapter) {
      ttsManager.currentNovel = novel;
      ttsManager.currentChapterTitle = initialChapter.title;
      notifyListeners();
      return;
    }

    await loadCurrentChapter();
  }

  Future<void> loadCurrentChapter({bool isAdvancingForward = false}) async {
    final chapter = currentChapter;
    if (chapter == null || _novel == null) return;

    await ttsManager.stop();

    _isLoading = true;
    _errorMessage = null;
    _content = null;
    _sentences = [];
    _activeSentenceIndex = 0;
    _preloadedNextContent = null;
    _preloadedNextSentences = [];
    _isPreloadingNextChapter = false;
    notifyListeners();

    try {
      // 1. Check local offline cache
      ChapterContent? loadedContent = await _storage.getCachedChapterContent(chapter.id);
      if (loadedContent != null &&
          (loadedContent.paragraphs.isEmpty ||
              (loadedContent.paragraphs.length == 1 &&
                  (loadedContent.paragraphs.first.contains('contains no text content') ||
                      loadedContent.paragraphs.first.startsWith('[IMAGE:'))))) {
        loadedContent = null;
      }

      if (loadedContent == null) {
        ChapterContent fetched;
        if (chapter.url.startsWith('file:') ||
            chapter.url.startsWith('/') ||
            _novel!.sourceId == 'local_epub') {
          fetched = await EpubService().loadChapterContent(chapter.url);
        } else {
          final source = SourceRegistry.getSource(_novel!.sourceId) ?? SourceRegistry.getDefaultSource();
          fetched = await source.getChapterContent(chapter.url);
        }
        final populated = ChapterContent(
          chapterId: chapter.id,
          novelId: _novel!.id,
          title: fetched.title.isNotEmpty ? fetched.title : chapter.title,
          rawText: fetched.rawText,
          paragraphs: fetched.paragraphs,
        );
        loadedContent = populated;
        if (populated.paragraphs.isNotEmpty) {
          await _storage.cacheChapterContent(populated);
        }
      }

      _content = loadedContent;
      _sentences = loadedContent.toSentences();

      // Restore saved progress if available
      final progress = _storage.getProgress(_novel!.id);
      if (progress != null && progress.chapterId == chapter.id) {
        if (_sentences.isNotEmpty) {
          _activeSentenceIndex = progress.activeSentenceIndex.clamp(0, _sentences.length - 1);
        } else {
          _activeSentenceIndex = 0;
        }
      } else {
        _activeSentenceIndex = 0;
      }

      // Load sentences into the real-time TTS streaming ring-buffer
      if (_targetLanguageCode != null) {
        final langInfo = LanguageVoiceRegistry.getByCode(_targetLanguageCode!);
        await translateCurrentChapter(langInfo);
      } else {
        final detectedLang = _resolveLanguageForChapter(_sentences);

        if (detectedLang != 'en') {
          final langInfo = LanguageVoiceRegistry.getByCode(detectedLang);
          ttsManager.currentLanguage = detectedLang;
          final currentVoice = ttsManager.activeVoice;
          final isCurrentEnglishVoice = currentVoice.startsWith('en-') ||
              currentVoice.startsWith('en_') ||
              currentVoice.contains('Christopher') ||
              currentVoice.contains('Jenny') ||
              currentVoice.contains('Guy') ||
              currentVoice.contains('Aria') ||
              currentVoice.contains('Sonia') ||
              currentVoice.contains('Ryan') ||
              currentVoice.contains('Brian') ||
              currentVoice.contains('Ava');
          if (isCurrentEnglishVoice && langInfo.defaultFemaleVoice.isNotEmpty) {
            ttsManager.setVoice(langInfo.defaultFemaleVoice);
          }
        }

        ttsManager.loadSentences(
          _sentences,
          startIndex: _activeSentenceIndex,
          novelId: _novel!.id,
          chapterId: chapter.id,
          lang: detectedLang,
          novel: _novel,
          chapterTitle: chapter.title,
          trackNumber: _currentChapterIndex + 1,
        );
      }

      _isLoading = false;
      notifyListeners();

      // Reading position safety rule:
      // Only overwrite the novel's saved reading position if:
      // 1. Novel has no saved reading progress yet (first time reading)
      // 2. Currently reading the saved chapter itself
      // 3. Advancing forward from the saved position (e.g. Next chapter within novel)
      // Simply checking out an earlier chapter from the list does NOT demote the saved reading position.
      final savedProgress = _storage.getProgress(_novel!.id);
      final savedIdx = savedProgress != null
          ? _chapters.indexWhere((c) => c.id == savedProgress.chapterId || c.url == savedProgress.chapterId)
          : -1;

      final shouldUpdateProgress = savedProgress == null ||
          savedIdx == -1 ||
          _currentChapterIndex == savedIdx ||
          (isAdvancingForward && _currentChapterIndex > savedIdx);

      if (shouldUpdateProgress) {
        await _storage.saveProgress(
          ReadingProgress(
            novelId: _novel!.id,
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            scrollOffset: progress != null && progress.chapterId == chapter.id ? progress.scrollOffset : 0.0,
            activeSentenceIndex: _activeSentenceIndex,
            lastReadAt: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      _errorMessage = 'Failed to load chapter content: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _preloadNextChapter() async {
    if (_isPreloadingNextChapter || !hasNextChapter || _novel == null) return;
    _isPreloadingNextChapter = true;
    try {
      final nextChapterObj = _chapters[_currentChapterIndex + 1];
      ChapterContent? loadedContent = await _storage.getCachedChapterContent(nextChapterObj.id);
      if (loadedContent != null && loadedContent.paragraphs.isEmpty && !_novel!.isFullBook) {
        loadedContent = null;
      }

      if (loadedContent == null) {
        ChapterContent fetched;
        if (nextChapterObj.url.startsWith('file:') ||
            nextChapterObj.url.startsWith('/') ||
            _novel!.isFullBook ||
            _novel!.sourceId == 'local_epub') {
          fetched = await EpubService().loadChapterContent(nextChapterObj.url);
        } else {
          final source = SourceRegistry.getSource(_novel!.sourceId) ?? SourceRegistry.getDefaultSource();
          fetched = await source.getChapterContent(nextChapterObj.url);
        }
        final populated = ChapterContent(
          chapterId: nextChapterObj.id,
          novelId: _novel!.id,
          title: fetched.title.isNotEmpty ? fetched.title : nextChapterObj.title,
          rawText: fetched.rawText,
          paragraphs: fetched.paragraphs,
        );
        loadedContent = populated;
        if (populated.paragraphs.isNotEmpty) {
          await _storage.cacheChapterContent(populated);
        }
      }

      _preloadedNextContent = loadedContent;
      _preloadedNextSentences = loadedContent.toSentences();
      ttsManager.queueNextChapterSentences(_preloadedNextSentences);
    } catch (_) {
      // Best-effort background prefetch
    } finally {
      _isPreloadingNextChapter = false;
    }
  }

  Future<void> nextChapter() async {
    if (hasNextChapter) {
      if (_preloadedNextContent != null) {
        _currentChapterIndex++;
        _content = _preloadedNextContent;
        _sentences = List<String>.from(_preloadedNextSentences);
        _activeSentenceIndex = 0;
        _preloadedNextContent = null;
        _preloadedNextSentences = [];
        final detectedLang = _resolveLanguageForChapter(_sentences);
        if (detectedLang != 'en') {
          final langInfo = LanguageVoiceRegistry.getByCode(detectedLang);
          ttsManager.currentLanguage = detectedLang;
          final currentVoice = ttsManager.activeVoice;
          final isCurrentEnglishVoice = currentVoice.startsWith('en-') ||
              currentVoice.startsWith('en_') ||
              currentVoice.contains('Christopher') ||
              currentVoice.contains('Jenny') ||
              currentVoice.contains('Guy') ||
              currentVoice.contains('Aria') ||
              currentVoice.contains('Sonia') ||
              currentVoice.contains('Ryan') ||
              currentVoice.contains('Brian') ||
              currentVoice.contains('Ava');
          if (isCurrentEnglishVoice && langInfo.defaultFemaleVoice.isNotEmpty) {
            ttsManager.setVoice(langInfo.defaultFemaleVoice);
          }
        }
        ttsManager.loadSentences(
          _sentences,
          startIndex: 0,
          novelId: _novel!.id,
          chapterId: currentChapter?.id,
          lang: detectedLang,
          novel: _novel,
          chapterTitle: currentChapter?.title,
          trackNumber: _currentChapterIndex + 1,
        );
        if (_novel != null && currentChapter != null) {
          final savedProgress = _storage.getProgress(_novel!.id);
          final savedIdx = savedProgress != null
              ? _chapters.indexWhere((c) => c.id == savedProgress.chapterId || c.url == savedProgress.chapterId)
              : -1;
          if (savedProgress == null || savedIdx == -1 || _currentChapterIndex >= savedIdx) {
            await _storage.saveProgress(
              ReadingProgress(
                novelId: _novel!.id,
                chapterId: currentChapter!.id,
                chapterTitle: currentChapter!.title,
                activeSentenceIndex: 0,
                lastReadAt: DateTime.now(),
              ),
            );
          }
        }
        notifyListeners();
        return;
      }
      _currentChapterIndex++;
      await loadCurrentChapter(isAdvancingForward: true);
    }
  }

  Future<void> previousChapter() async {
    if (hasPreviousChapter) {
      _currentChapterIndex--;
      await loadCurrentChapter(isAdvancingForward: false);
    }
  }

  void saveScrollProgress(double scrollOffset) {
    if (_novel != null && currentChapter != null) {
      final savedProgress = _storage.getProgress(_novel!.id);
      final savedIdx = savedProgress != null
          ? _chapters.indexWhere((c) => c.id == savedProgress.chapterId || c.url == savedProgress.chapterId)
          : -1;
      if (savedProgress == null || savedIdx == -1 || _currentChapterIndex >= savedIdx) {
        _storage.saveProgress(
          ReadingProgress(
            novelId: _novel!.id,
            chapterId: currentChapter!.id,
            chapterTitle: currentChapter!.title,
            scrollOffset: scrollOffset,
            activeSentenceIndex: _activeSentenceIndex,
            lastReadAt: DateTime.now(),
          ),
        );
      }
    }
  }

  void setActiveSentence(int index) {
    if (index >= 0 && index < _sentences.length) {
      _activeSentenceIndex = index;
      notifyListeners();
      if (_novel != null && currentChapter != null) {
        final savedProgress = _storage.getProgress(_novel!.id);
        final savedIdx = savedProgress != null
            ? _chapters.indexWhere((c) => c.id == savedProgress.chapterId || c.url == savedProgress.chapterId)
            : -1;
        if (savedProgress == null || savedIdx == -1 || _currentChapterIndex >= savedIdx) {
          _storage.saveProgress(
            ReadingProgress(
              novelId: _novel!.id,
              chapterId: currentChapter!.id,
              chapterTitle: currentChapter!.title,
              activeSentenceIndex: index,
              lastReadAt: DateTime.now(),
            ),
          );
        }
      }
      // If user reaches within 2-3 sentences of chapter end, trigger background preload
      if (index >= _sentences.length - 3 && hasNextChapter) {
        _preloadNextChapter();
      }
    }
  }

  void toggleTtsPlayback() {
    if (ttsManager.isPlaying) {
      ttsManager.pause();
    } else {
      if (ttsManager.sentences.isNotEmpty) {
        ttsManager.resume();
      } else if (_sentences.isNotEmpty) {
        ttsManager.loadSentences(_sentences, startIndex: _activeSentenceIndex);
        ttsManager.playFrom(_activeSentenceIndex);
      }
    }
  }

  String _resolveLanguageForChapter(List<String> sentences) {
    if (_targetLanguageCode != null) return _targetLanguageCode!;

    // 1. Check first 10 sentences
    final sampleText = sentences.take(10).join(' ');
    String? detected = OdiaTransliteration.detectScript(sampleText);

    // 2. Scan all sentences if sampleText didn't detect Indic script
    if (detected == null) {
      for (final s in sentences) {
        final d = OdiaTransliteration.detectScript(s);
        if (d != null) {
          detected = d;
          break;
        }
      }
    }

    // 3. Fallback to novel title and description
    detected ??= OdiaTransliteration.detectScript(_novel?.title ?? '') ??
        OdiaTransliteration.detectScript(_novel?.description ?? '');

    // 4. Fallback to novel genres
    if (detected == null && _novel?.genres != null) {
      if (_novel!.genres.any((g) => g.toLowerCase() == 'odia' || g.toLowerCase() == 'or')) {
        detected = 'or';
      } else if (_novel!.genres.any((g) => g.toLowerCase() == 'hindi' || g.toLowerCase() == 'hi')) {
        detected = 'hi';
      }
    }

    // 5. Fallback to novel ID / source prefix
    if (detected == null && _novel != null) {
      if (_novel!.id.startsWith('or_') || _novel!.id.startsWith('odiabibhaba')) {
        detected = 'or';
      } else if (_novel!.id.startsWith('hindisamay') ||
          _novel!.id.startsWith('gadyakosh') ||
          _novel!.id.startsWith('kavitakosh') ||
          _novel!.id.startsWith('epustakalay')) {
        detected = 'hi';
      }
    }

    // 6. Source registry fallback
    detected ??= (SourceRegistry.getSource(_novel?.sourceId ?? '')?.lang);

    return detected ?? 'en';
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
