import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../data/storage_service.dart';

class AudiobookPlayerProvider extends ChangeNotifier {
  final StorageService _storageService;
  final AudioPlayer _player = AudioPlayer();

  Novel? _currentNovel;
  Chapter? _currentChapter;
  String _currentLanguage = 'en';
  List<Chapter> _audioChapters = [];

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  // Sleep Timer with volume fade
  Duration? _sleepTimerDuration;
  Duration? _sleepTimerRemaining;
  Timer? _countdownTimer;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  AudiobookPlayerProvider({StorageService? storageService})
      : _storageService = storageService ?? StorageService() {
    _initStreams();
  }

  Novel? get currentNovel => _currentNovel;
  Chapter? get currentChapter => _currentChapter;
  String get currentLanguage => _currentLanguage;
  List<Chapter> get audioChapters => _audioChapters;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;
  Duration? get sleepTimerDuration => _sleepTimerDuration;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  bool get hasTrack => _currentNovel != null && _currentChapter != null;

  void _initStreams() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      final playing = state.playing && state.processingState != ProcessingState.completed;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }

      if (state.processingState == ProcessingState.completed) {
        _onChapterCompleted();
      }
    });

    _positionSub = _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });
  }

  Future<void> playAudiobook({
    required Novel novel,
    required Chapter chapter,
    required String language,
    List<Chapter>? allChapters,
  }) async {
    _currentNovel = novel;
    _currentChapter = chapter;
    _currentLanguage = language;

    if (allChapters != null && allChapters.isNotEmpty) {
      _audioChapters = allChapters.where((c) {
        return _storageService.hasOfflineAudiobook(novel.id, c.id, language);
      }).toList();
    } else {
      final downloadedChapterIds = _storageService.getDownloadedAudiobookChapterIds(novel.id);
      _audioChapters = [chapter];
      final cachedChapters = await _storageService.getCachedChapters(novel.id);
      if (cachedChapters != null) {
        _audioChapters = cachedChapters.where((c) => downloadedChapterIds.contains(c.id)).toList();
      }
    }

    final audioFile = _storageService.getAudiobookFile(novel.id, chapter.id, language);
    if (!audioFile.existsSync()) {
      debugPrint('[AUDIOBOOK] File not found: ${audioFile.path}');
      return;
    }

    try {
      await _player.stop();
      await _player.setFilePath(audioFile.path);
      await _player.setSpeed(_speed);
      await _player.play();
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[AUDIOBOOK] Error loading audio file: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> seek(Duration target) async {
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration && _duration > Duration.zero ? _duration : target);
    await _player.seek(clamped);
  }

  Future<void> smartRewind([int seconds = 15]) async {
    final target = _position - Duration(seconds: seconds);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> smartForward([int seconds = 15]) async {
    final target = _position + Duration(seconds: seconds);
    await seek(target > _duration ? _duration : target);
  }

  Future<void> setSpeed(double newSpeed) async {
    _speed = newSpeed;
    await _player.setSpeed(newSpeed);
    notifyListeners();
  }

  void setSleepTimer(Duration? duration) {
    _countdownTimer?.cancel();
    _sleepTimerDuration = duration;
    _sleepTimerRemaining = duration;
    _player.setVolume(1.0);

    if (duration == null) {
      notifyListeners();
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTimerRemaining == null) {
        timer.cancel();
        return;
      }

      final rem = _sleepTimerRemaining! - const Duration(seconds: 1);
      if (rem <= Duration.zero) {
        timer.cancel();
        _sleepTimerRemaining = null;
        _player.pause();
        _player.setVolume(1.0);
        notifyListeners();
        return;
      }

      _sleepTimerRemaining = rem;

      // Graceful volume fade during the last 45 seconds
      if (rem.inSeconds <= 45) {
        final fadeVolume = (rem.inSeconds / 45.0).clamp(0.05, 1.0);
        _player.setVolume(fadeVolume);
      }

      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> playNextChapter() async {
    if (_currentNovel == null || _currentChapter == null || _audioChapters.isEmpty) return;
    final currentIndex = _audioChapters.indexWhere((c) => c.id == _currentChapter!.id);
    if (currentIndex >= 0 && currentIndex < _audioChapters.length - 1) {
      final nextChapter = _audioChapters[currentIndex + 1];
      await playAudiobook(
        novel: _currentNovel!,
        chapter: nextChapter,
        language: _currentLanguage,
        allChapters: _audioChapters,
      );
    }
  }

  Future<void> playPreviousChapter() async {
    if (_currentNovel == null || _currentChapter == null || _audioChapters.isEmpty) return;
    final currentIndex = _audioChapters.indexWhere((c) => c.id == _currentChapter!.id);
    if (currentIndex > 0) {
      final prevChapter = _audioChapters[currentIndex - 1];
      await playAudiobook(
        novel: _currentNovel!,
        chapter: prevChapter,
        language: _currentLanguage,
        allChapters: _audioChapters,
      );
    }
  }

  void _onChapterCompleted() {
    if (_currentNovel == null || _currentChapter == null || _audioChapters.isEmpty) return;
    final currentIndex = _audioChapters.indexWhere((c) => c.id == _currentChapter!.id);
    if (currentIndex >= 0 && currentIndex < _audioChapters.length - 1) {
      playNextChapter();
    }
  }

  void stop() {
    _player.stop();
    _currentNovel = null;
    _currentChapter = null;
    _isPlaying = false;
    _countdownTimer?.cancel();
    _sleepTimerRemaining = null;
    _player.setVolume(1.0);
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
