import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'tts_engine_interface.dart';
import 'tts_model_registry.dart';
import 'engines/edge_neural_engine.dart';
import 'engines/kokoro_engine.dart';
import 'engines/piper_engine.dart';
import 'engines/sherpa_engine.dart';
import 'engines/system_fallback_engine.dart';
import 'sleep_timer_service.dart';

/// Rock-solid sequential audio playback manager with aggressive background pre-fetching,
/// zero DSP pitch artifacts, and seamless cross-chapter continuity.
class RingBufferManager extends ChangeNotifier {
  final Map<String, TtsEngineInterface> _engines;
  late TtsEngineInterface _activeEngine;
  final SleepTimerService sleepTimer;
  final AudioPlayer _player;

  StreamSubscription<PlayerState>? _stateSub;
  int _sessionEpoch = 0;
  bool _isTransitioning = false;

  List<String> _sentences = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isBuffering = false;

  double _speed = 1.0;
  double _pitch = 1.0;
  String _activeVoice = 'en-US-ChristopherNeural';
  int _sentencePauseMs = 0; // 0ms for continuous human audiobook playback

  Function(int sentenceIndex)? onSentenceStarted;
  VoidCallback? onChapterFinished;
  VoidCallback? onApproachingEndOfChapter;
  VoidCallback? onCrossChapterTransition;

  List<String> _nextChapterSentences = [];
  bool _hasTriggeredApproachingEnd = false;

  RingBufferManager({
    AudioPlayer? player,
    SleepTimerService? sleepTimer,
    Map<String, TtsEngineInterface>? customEngines,
  })  : _player = player ?? AudioPlayer(),
        sleepTimer = sleepTimer ?? SleepTimerService(),
        _engines = {
          TtsModelRegistry.edgeNeuralId: EdgeNeuralEngine(),
          TtsModelRegistry.kokoroId: KokoroEngine(),
          TtsModelRegistry.piperId: PiperEngine(),
          TtsModelRegistry.sherpaId: SherpaEngine(),
          TtsModelRegistry.systemId: SystemFallbackEngine(),
        } {
    if (customEngines != null) {
      _engines.addAll(customEngines);
    }
    _activeEngine = _engines[TtsModelRegistry.edgeNeuralId]!;
    this.sleepTimer.onTimerExpired = () {
      pause();
    };
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleSentenceCompleted();
      }
    });
  }

  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  int get currentIndex => _currentIndex;
  List<String> get sentences => _sentences;
  TtsEngineInterface get activeEngine => _activeEngine;
  double get speed => _speed;
  double get pitch => _pitch;
  String get activeVoice => _activeVoice;
  int get sentencePauseMs => _sentencePauseMs;

  void switchEngine(String engineId) {
    final newEngine = _engines[engineId];
    if (newEngine != null && newEngine.id != _activeEngine.id) {
      final wasPlaying = _isPlaying;
      stop();
      _activeEngine = newEngine;
      final modelInfo = TtsModelRegistry.getModel(engineId);
      _activeVoice = modelInfo.defaultVoice;
      if (wasPlaying) {
        playFrom(_currentIndex);
      }
      notifyListeners();
    }
  }

  void setVoice(String voice) {
    _activeVoice = voice;
    notifyListeners();
    if (_isPlaying) {
      playFrom(_currentIndex);
    }
  }

  void setSpeed(double speed) {
    _speed = speed.clamp(0.5, 3.0);
    _player.setSpeed(_speed);
    notifyListeners();
  }

  void setPitch(double pitch) {
    _pitch = pitch.clamp(0.5, 2.0);
    // Note: Do NOT call _player.setPitch(_pitch) — ExoPlayer DSP pitch-shifting
    // introduces metallic, robotic noise. Neural voices handle pitch natively in SSML.
    notifyListeners();
  }

  void setSentencePause(int pauseMs) {
    _sentencePauseMs = pauseMs.clamp(0, 1000);
    notifyListeners();
  }

  /// Evaluates whether the current sentence position is within 2-3 lines of the chapter's end.
  /// If so, fires [onApproachingEndOfChapter] to initiate background chapter prefetching.
  void checkApproachingEnd(int index) {
    if (_sentences.isNotEmpty && index >= _sentences.length - 3 && !_hasTriggeredApproachingEnd) {
      _hasTriggeredApproachingEnd = true;
      onApproachingEndOfChapter?.call();
    }
  }

  /// Handles seamless boundary transition when audio player rolls into the next chapter's audio stream.
  void handleCrossChapterTag(String tag) {
    if (!tag.startsWith('next_')) return;
    final nextIdx = int.tryParse(tag.replaceFirst('next_', '')) ?? 0;

    // Respect sleep timer if set to end of chapter
    if (sleepTimer.mode == SleepTimerMode.endOfChapter) {
      pause();
      sleepTimer.triggerEndOfChapter();
      return;
    }

    // Seamless cross-chapter boundary transition without audio stutter
    if (_nextChapterSentences.isNotEmpty) {
      _sentences = List<String>.from(_nextChapterSentences);
      _nextChapterSentences.clear();
    }
    _currentIndex = nextIdx;
    _hasTriggeredApproachingEnd = false;
    onCrossChapterTransition?.call();
    onSentenceStarted?.call(_currentIndex);
    notifyListeners();
  }

  void queueNextChapterSentences(List<String> sentences) {
    _nextChapterSentences = List<String>.from(sentences);
    if (_isPlaying) {
      _prefetchUpcoming();
    }
  }

  void loadSentences(List<String> sentences, {int startIndex = 0}) {
    stop();
    _sentences = sentences;
    _nextChapterSentences.clear();
    _hasTriggeredApproachingEnd = false;
    _currentIndex = startIndex.clamp(0, sentences.isEmpty ? 0 : sentences.length - 1);
    notifyListeners();
    _prefetchUpcoming();
  }

  /// Aggressively prefetches upcoming sentences in the background
  /// to ensure 0ms network latency and instant line-to-line transitions.
  void _prefetchUpcoming() {
    for (int offset = 1; offset <= 5; offset++) {
      final targetIdx = _currentIndex + offset;
      if (targetIdx < _sentences.length) {
        final text = _sentences[targetIdx].trim();
        if (text.isNotEmpty) {
          _activeEngine.synthesizeSentenceToFile(
            text,
            voice: _activeVoice,
            speed: 1.0,
            pitch: _pitch,
          ).catchError((_) => null);
        }
      } else if (_nextChapterSentences.isNotEmpty) {
        final nextIdx = targetIdx - _sentences.length;
        if (nextIdx < _nextChapterSentences.length && nextIdx < 3) {
          final text = _nextChapterSentences[nextIdx].trim();
          if (text.isNotEmpty) {
            _activeEngine.synthesizeSentenceToFile(
              text,
              voice: _activeVoice,
              speed: 1.0,
              pitch: _pitch,
            ).catchError((_) => null);
          }
        }
      }
    }
  }

  Future<void> playFrom(int index) async {
    if (_sentences.isEmpty) return;
    await stop();
    _sessionEpoch++;
    final epoch = _sessionEpoch;

    _nextChapterSentences.clear();
    _hasTriggeredApproachingEnd = false;

    _currentIndex = index.clamp(0, _sentences.length - 1);
    _isPlaying = true;
    _isBuffering = true;
    notifyListeners();
    onSentenceStarted?.call(_currentIndex);

    checkApproachingEnd(_currentIndex);
    await _playCurrentSentence(epoch);
  }

  Future<void> _playCurrentSentence(int epoch) async {
    if (!_isPlaying || epoch != _sessionEpoch || _sentences.isEmpty) return;
    final text = _sentences[_currentIndex].trim();
    if (text.isEmpty) {
      if (_currentIndex < _sentences.length - 1) {
        _currentIndex++;
        onSentenceStarted?.call(_currentIndex);
        notifyListeners();
        await _playCurrentSentence(epoch);
      }
      return;
    }

    // Prefetch next 5 sentences in parallel into disk cache
    _prefetchUpcoming();

    _isBuffering = true;
    notifyListeners();

    final audioPath = await _activeEngine.synthesizeSentenceToFile(
      text,
      voice: _activeVoice,
      speed: 1.0,
      pitch: _pitch,
    );

    if (epoch != _sessionEpoch || !_isPlaying) return;

    if (audioPath != null && await File(audioPath).exists()) {
      _isBuffering = false;
      notifyListeners();
      try {
        await _player.setFilePath(audioPath);
        await _player.setSpeed(_speed);
        await _player.setPitch(1.0); // Clean native playback without DSP artifacts
        await _player.play();
      } catch (e) {
        debugPrint('[RingBufferManager] Playback error: $e');
        _playWithDirectFallback();
      }
    } else {
      _isBuffering = false;
      notifyListeners();
      _playWithDirectFallback();
    }
  }

  Future<void> _handleSentenceCompleted() async {
    if (!_isPlaying || _isTransitioning) return;
    _isTransitioning = true;
    final epoch = _sessionEpoch;

    if (_sentencePauseMs > 0) {
      await Future.delayed(Duration(milliseconds: _sentencePauseMs));
      if (!_isPlaying || epoch != _sessionEpoch) {
        _isTransitioning = false;
        return;
      }
    }

    if (_currentIndex < _sentences.length - 1) {
      // Normal sentence progression within the current chapter
      _currentIndex++;
      onSentenceStarted?.call(_currentIndex);
      notifyListeners();
      checkApproachingEnd(_currentIndex);
      await _playCurrentSentence(epoch);
    } else {
      // Reached the end of current chapter's sentences
      if (sleepTimer.mode == SleepTimerMode.endOfChapter) {
        _isPlaying = false;
        notifyListeners();
        sleepTimer.triggerEndOfChapter();
        _isTransitioning = false;
        return;
      }

      if (_nextChapterSentences.isNotEmpty) {
        // Seamless cross-chapter continuous playback
        _sentences = List<String>.from(_nextChapterSentences);
        _nextChapterSentences.clear();
        _currentIndex = 0;
        _hasTriggeredApproachingEnd = false;
        onCrossChapterTransition?.call();
        onSentenceStarted?.call(_currentIndex);
        notifyListeners();
        await _playCurrentSentence(epoch);
      } else {
        // Entire novel completed or no next chapter available
        _isPlaying = false;
        notifyListeners();
        sleepTimer.triggerEndOfChapter();
        onChapterFinished?.call();
      }
    }
    _isTransitioning = false;
  }

  Future<void> resume() async {
    if (_sentences.isEmpty || _isPlaying) return;
    _isPlaying = true;
    notifyListeners();
    if (_player.processingState == ProcessingState.ready) {
      await _player.play();
    } else {
      await playFrom(_currentIndex);
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    try {
      await _player.pause();
    } catch (_) {}
    await _activeEngine.stop();
    notifyListeners();
  }

  Future<void> stop() async {
    _sessionEpoch++;
    _isPlaying = false;
    _isBuffering = false;
    _nextChapterSentences.clear();
    _hasTriggeredApproachingEnd = false;
    try {
      await _player.stop();
    } catch (_) {}
    await _activeEngine.stop();
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (_currentIndex < _sentences.length - 1) {
      await playFrom(_currentIndex + 1);
    } else if (_nextChapterSentences.isNotEmpty) {
      _sentences = List<String>.from(_nextChapterSentences);
      _nextChapterSentences.clear();
      onCrossChapterTransition?.call();
      await playFrom(0);
    } else {
      await stop();
      sleepTimer.triggerEndOfChapter();
      onChapterFinished?.call();
    }
  }

  Future<void> skipPrevious() async {
    if (_currentIndex > 0) {
      await playFrom(_currentIndex - 1);
    }
  }

  Future<void> _playWithDirectFallback() async {
    if (!_isPlaying || _sentences.isEmpty) return;
    if (_currentIndex >= _sentences.length) {
      _isPlaying = false;
      notifyListeners();
      sleepTimer.triggerEndOfChapter();
      onChapterFinished?.call();
      return;
    }

    final sentence = _sentences[_currentIndex].trim();
    if (sentence.isEmpty) {
      _currentIndex++;
      _playWithDirectFallback();
      return;
    }

    onSentenceStarted?.call(_currentIndex);
    final epoch = _sessionEpoch;

    await _activeEngine.speakSentenceDirect(
      sentence,
      voice: _activeVoice,
      speed: _speed,
      pitch: _pitch,
      onDone: () async {
        if (!_isPlaying || epoch != _sessionEpoch) return;
        if (_sentencePauseMs > 0) {
          await Future.delayed(Duration(milliseconds: _sentencePauseMs));
        }
        if (_isPlaying && epoch == _sessionEpoch) {
          _currentIndex++;
          _playWithDirectFallback();
        }
      },
    );
  }

  Future<void> previewVoice(String voice) async {
    final wasPlaying = _isPlaying;
    if (wasPlaying) {
      await pause();
    }

    String sample = 'Welcome to Novels World. The journey through the realms begins now.';
    if (voice.contains('Christopher') || voice.contains('michael')) {
      sample = 'The ancient gates of the Abyss slowly swung open, echoing through the cavern.';
    } else if (voice.contains('Jenny') || voice.contains('bella')) {
      sample = 'She looked across the mist-shrouded valley with a warm smile, ready for the adventure.';
    } else if (voice.contains('Sonia') || voice.contains('emma')) {
      sample = 'By royal decree of the high council, the forgotten chronicle shall now be unsealed.';
    } else if (voice.contains('cjk') || voice.contains('sherpa')) {
      sample = 'Fellow Daoist, the spiritual Qi of heaven and earth gathers within the Dantian.';
    }

    await _activeEngine.speakSentenceDirect(
      sample,
      voice: voice,
      speed: _speed,
      pitch: _pitch,
      onDone: () {},
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    for (final engine in _engines.values) {
      engine.dispose();
    }
    sleepTimer.dispose();
    super.dispose();
  }
}
