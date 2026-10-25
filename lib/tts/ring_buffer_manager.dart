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

class RingBufferManager extends ChangeNotifier {
  final Map<String, TtsEngineInterface> _engines = {
    TtsModelRegistry.edgeNeuralId: EdgeNeuralEngine(),
    TtsModelRegistry.kokoroId: KokoroEngine(),
    TtsModelRegistry.piperId: PiperEngine(),
    TtsModelRegistry.sherpaId: SherpaEngine(),
    TtsModelRegistry.systemId: SystemFallbackEngine(),
  };

  late TtsEngineInterface _activeEngine;
  final SleepTimerService sleepTimer = SleepTimerService();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerState>? _stateSub;
  int _sessionEpoch = 0;

  // Strict Sequential Ordering FIFO queue for gapless playback
  final Map<int, String> _resolvedAudios = {};
  final Set<int> _failedIndices = {};
  final Set<int> _requestedIndices = {};
  int _nextQueuedIndex = 0;
  bool _isDraining = false;

  List<String> _sentences = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isBuffering = false;

  double _speed = 1.0;
  double _pitch = 1.0;
  String _activeVoice = 'en-US-ChristopherNeural';
  int _sentencePauseMs = 0; // 0ms for instant gapless human audiobook playback

  Function(int sentenceIndex)? onSentenceStarted;
  VoidCallback? onChapterFinished;

  RingBufferManager() {
    _activeEngine = _engines[TtsModelRegistry.edgeNeuralId]!;
    sleepTimer.onTimerExpired = () {
      pause();
    };
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _indexSub = _player.currentIndexStream.listen((tagIndex) {
      if (!_isPlaying || tagIndex == null) return;
      final sources = _player.audioSources;
      if (tagIndex < sources.length) {
        final source = sources[tagIndex];
        if (source is UriAudioSource && source.tag is int) {
          final newIdx = source.tag as int;
          if (newIdx != _currentIndex) {
            _currentIndex = newIdx;
            onSentenceStarted?.call(_currentIndex);
            notifyListeners();
            _schedulePrefetchAndAppend();
          }
        }
      }
    });

    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_currentIndex >= _sentences.length - 1) {
          _isPlaying = false;
          notifyListeners();
          sleepTimer.triggerEndOfChapter();
          onChapterFinished?.call();
        }
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
    _player.setPitch(_pitch);
    notifyListeners();
  }

  void setSentencePause(int ms) {
    _sentencePauseMs = ms.clamp(0, 1000);
    notifyListeners();
  }

  void loadSentences(List<String> sentences, {int startIndex = 0}) {
    stop();
    _sentences = sentences;
    _currentIndex = startIndex.clamp(0, sentences.isEmpty ? 0 : sentences.length - 1);
    notifyListeners();
    _prefetchUpcoming();
  }

  /// Aggressively prefetches upcoming sentences in the background
  /// to ensure 0ms network latency and instant line-to-line transitions.
  void _prefetchUpcoming() {
    for (int offset = 0; offset <= 4; offset++) {
      final targetIdx = _currentIndex + offset;
      if (targetIdx < _sentences.length) {
        final text = _sentences[targetIdx].trim();
        if (text.isNotEmpty) {
          _activeEngine.synthesizeSentenceToFile(
            text,
            voice: _activeVoice,
            speed: _speed,
            pitch: _pitch,
          ).catchError((_) => null);
        }
      }
    }
  }

  Future<void> playFrom(int index) async {
    if (_sentences.isEmpty) return;
    await stop();
    _sessionEpoch++;
    final epoch = _sessionEpoch;

    _resolvedAudios.clear();
    _failedIndices.clear();
    _requestedIndices.clear();

    _currentIndex = index.clamp(0, _sentences.length - 1);
    _nextQueuedIndex = _currentIndex + 1;
    _isPlaying = true;
    _isBuffering = true;
    notifyListeners();
    onSentenceStarted?.call(_currentIndex);

    final currentText = _sentences[_currentIndex].trim();
    if (currentText.isEmpty) {
      if (_currentIndex < _sentences.length - 1) {
        await playFrom(_currentIndex + 1);
      }
      return;
    }

    final firstAudio = await _activeEngine.synthesizeSentenceToFile(
      currentText,
      voice: _activeVoice,
      speed: _speed,
      pitch: _pitch,
    );

    if (epoch != _sessionEpoch || !_isPlaying) return;

    if (firstAudio != null && await File(firstAudio).exists()) {
      _isBuffering = false;
      notifyListeners();

      await _player.setAudioSources([
        AudioSource.file(firstAudio, tag: _currentIndex),
      ]);
      await _player.setSpeed(_speed);
      await _player.setPitch(_pitch);
      await _player.play();

      _schedulePrefetchAndAppend();
    } else {
      _isBuffering = false;
      notifyListeners();
      _playWithDirectFallback();
    }
  }

  /// Prefetches upcoming sentences and strictly enqueues them in narrative order.
  /// Even if short sentences synthesize faster over the network than preceding
  /// long paragraphs, the FIFO buffer guarantees the audio sources are appended
  /// in exact numerical index sequence (0, 1, 2, 3...).
  void _schedulePrefetchAndAppend() {
    if (!_isPlaying) return;
    final epoch = _sessionEpoch;

    for (int offset = 1; offset <= 4; offset++) {
      final targetIdx = _currentIndex + offset;
      if (targetIdx >= _sentences.length) break;

      final alreadyInPlaylist = _player.audioSources.any((s) => s is UriAudioSource && s.tag == targetIdx);
      if (alreadyInPlaylist || _resolvedAudios.containsKey(targetIdx) || _requestedIndices.contains(targetIdx)) {
        continue;
      }

      final text = _sentences[targetIdx].trim();
      if (text.isEmpty) {
        _failedIndices.add(targetIdx);
        _drainResolvedAudios(epoch);
        continue;
      }

      _requestedIndices.add(targetIdx);
      _activeEngine.synthesizeSentenceToFile(
        text,
        voice: _activeVoice,
        speed: _speed,
        pitch: _pitch,
      ).then((audioPath) async {
        if (epoch == _sessionEpoch && _isPlaying) {
          if (audioPath != null && await File(audioPath).exists()) {
            _resolvedAudios[targetIdx] = audioPath;
          } else {
            _failedIndices.add(targetIdx);
          }
          _drainResolvedAudios(epoch);
        }
      }).catchError((_) {
        if (epoch == _sessionEpoch && _isPlaying) {
          _failedIndices.add(targetIdx);
          _drainResolvedAudios(epoch);
        }
      });
    }
  }

  /// Drains resolved audio files in strict monotonically increasing sequence.
  Future<void> _drainResolvedAudios(int epoch) async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      while (_resolvedAudios.containsKey(_nextQueuedIndex) || _failedIndices.contains(_nextQueuedIndex)) {
        if (epoch != _sessionEpoch || !_isPlaying) break;
        final targetIdx = _nextQueuedIndex;
        if (_failedIndices.contains(targetIdx)) {
          _failedIndices.remove(targetIdx);
          _nextQueuedIndex++;
          continue;
        }

        final audioPath = _resolvedAudios.remove(targetIdx)!;
        if (await File(audioPath).exists()) {
          final alreadyIn = _player.audioSources.any((s) => s is UriAudioSource && s.tag == targetIdx);
          if (!alreadyIn) {
            await _player.addAudioSource(AudioSource.file(audioPath, tag: targetIdx));
          }
        }
        _nextQueuedIndex++;
      }
    } finally {
      _isDraining = false;
    }
  }

  Future<void> resume() async {
    if (_sentences.isEmpty || _isPlaying) return;
    if (_player.audioSources.isNotEmpty) {
      _isPlaying = true;
      notifyListeners();
      await _player.play();
      _schedulePrefetchAndAppend();
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
    _resolvedAudios.clear();
    _failedIndices.clear();
    _requestedIndices.clear();
    try {
      await _player.stop();
      await _player.clearAudioSources();
    } catch (_) {}
    await _activeEngine.stop();
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (_currentIndex < _sentences.length - 1) {
      if (_player.hasNext) {
        await _player.seekToNext();
      } else {
        await playFrom(_currentIndex + 1);
      }
    } else {
      await stop();
      sleepTimer.triggerEndOfChapter();
      onChapterFinished?.call();
    }
  }

  Future<void> skipPrevious() async {
    if (_currentIndex > 0) {
      if (_player.hasPrevious) {
        await _player.seekToPrevious();
      } else {
        await playFrom(_currentIndex - 1);
      }
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
    stop();
    _indexSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    sleepTimer.dispose();
    for (final engine in _engines.values) {
      engine.dispose();
    }
    super.dispose();
  }
}
