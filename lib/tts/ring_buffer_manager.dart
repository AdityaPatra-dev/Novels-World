import 'dart:async';
import 'package:flutter/foundation.dart';
import 'tts_engine_interface.dart';
import 'tts_model_registry.dart';
import 'engines/kokoro_engine.dart';
import 'engines/piper_engine.dart';
import 'engines/sherpa_engine.dart';
import 'engines/system_fallback_engine.dart';
import 'sleep_timer_service.dart';

class RingBufferManager extends ChangeNotifier {
  final Map<String, TtsEngineInterface> _engines = {
    TtsModelRegistry.kokoroId: KokoroEngine(),
    TtsModelRegistry.piperId: PiperEngine(),
    TtsModelRegistry.sherpaId: SherpaEngine(),
    TtsModelRegistry.systemId: SystemFallbackEngine(),
  };

  late TtsEngineInterface _activeEngine;
  final SleepTimerService sleepTimer = SleepTimerService();

  List<String> _sentences = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isBuffering = false;

  double _speed = 1.0;
  double _pitch = 1.0;
  String _activeVoice = 'af_bella';

  Function(int sentenceIndex)? onSentenceStarted;
  VoidCallback? onChapterFinished;

  RingBufferManager() {
    _activeEngine = _engines[TtsModelRegistry.kokoroId]!;
    sleepTimer.onTimerExpired = () {
      pause();
    };
  }

  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  int get currentIndex => _currentIndex;
  List<String> get sentences => _sentences;
  TtsEngineInterface get activeEngine => _activeEngine;
  double get speed => _speed;
  String get activeVoice => _activeVoice;

  void switchEngine(String engineId) {
    final newEngine = _engines[engineId];
    if (newEngine != null && newEngine.id != _activeEngine.id) {
      final wasPlaying = _isPlaying;
      stop();
      _activeEngine = newEngine;
      if (wasPlaying) {
        resume();
      }
      notifyListeners();
    }
  }

  void setVoice(String voice) {
    _activeVoice = voice;
    notifyListeners();
  }

  void setSpeed(double speed) {
    _speed = speed.clamp(0.5, 3.0);
    notifyListeners();
  }

  void setPitch(double pitch) {
    _pitch = pitch.clamp(0.5, 2.0);
    notifyListeners();
  }

  void loadSentences(List<String> sentences, {int startIndex = 0}) {
    stop();
    _sentences = sentences;
    _currentIndex = startIndex.clamp(0, sentences.isEmpty ? 0 : sentences.length - 1);
    notifyListeners();
  }

  Future<void> playFrom(int index) async {
    if (_sentences.isEmpty) return;
    await stop();
    _currentIndex = index.clamp(0, _sentences.length - 1);
    _isPlaying = true;
    notifyListeners();
    _playCurrentSentence();
  }

  Future<void> resume() async {
    if (_sentences.isEmpty || _isPlaying) return;
    _isPlaying = true;
    notifyListeners();
    _playCurrentSentence();
  }

  Future<void> pause() async {
    _isPlaying = false;
    await _activeEngine.stop();
    notifyListeners();
  }

  Future<void> stop() async {
    _isPlaying = false;
    _isBuffering = false;
    await _activeEngine.stop();
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (_currentIndex < _sentences.length - 1) {
      await playFrom(_currentIndex + 1);
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

  Future<void> _playCurrentSentence() async {
    if (!_isPlaying || _sentences.isEmpty) return;

    if (_currentIndex >= _sentences.length) {
      // Reached end of chapter
      _isPlaying = false;
      notifyListeners();
      sleepTimer.triggerEndOfChapter();
      onChapterFinished?.call();
      return;
    }

    final sentence = _sentences[_currentIndex].trim();
    if (sentence.isEmpty) {
      _currentIndex++;
      _playCurrentSentence();
      return;
    }

    _isBuffering = true;
    notifyListeners();
    onSentenceStarted?.call(_currentIndex);

    _isBuffering = false;
    notifyListeners();

    await _activeEngine.speakSentenceDirect(
      sentence,
      voice: _activeVoice,
      speed: _speed,
      pitch: _pitch,
      onDone: () {
        if (_isPlaying) {
          _currentIndex++;
          _playCurrentSentence();
        }
      },
    );
  }

  @override
  void dispose() {
    stop();
    sleepTimer.dispose();
    super.dispose();
  }
}

