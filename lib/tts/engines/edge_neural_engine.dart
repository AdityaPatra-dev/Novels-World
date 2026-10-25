import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:edge_tts/edge_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/text_cleaner.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';
import 'system_fallback_engine.dart';

class EdgeNeuralEngine implements TtsEngineInterface {
  final AudioPlayer _player = AudioPlayer();
  final SystemFallbackEngine _fallback = SystemFallbackEngine();
  StreamSubscription<PlayerState>? _playerSub;
  bool _isInitialized = false;
  Directory? _cacheDir;
  final Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};

  @override
  String get id => TtsModelRegistry.edgeNeuralId;

  @override
  String get name => 'Microsoft Neural HD (Studio AI)';

  @override
  String get description =>
      'Ultra-realistic cloud neural voices with natural breathing, emotional sentence prosody, and studio clarity. The absolute gold standard for novels.';

  @override
  bool get isOfflineNeural => false;

  @override
  List<String> get availableVoices => [
        'en-US-ChristopherNeural (Christopher - Heroic Baritone)',
        'en-US-JennyNeural (Jenny - Warm Expressive Narrator)',
        'en-US-GuyNeural (Guy - Relaxed Conversational)',
        'en-US-AriaNeural (Aria - Dynamic High-Clarity)',
        'en-GB-SoniaNeural (Sonia - British Fantasy Lore)',
        'en-GB-RyanNeural (Ryan - British Aristocratic Sage)',
        'en-US-BrianNeural (Brian - Deep Wisdom & Worldbuilding)',
        'en-US-AvaNeural (Ava - Gentle Bedside Storyteller)',
      ];

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final temp = await getTemporaryDirectory();
      _cacheDir = Directory('${temp.path}/edge_tts_cache');
    } catch (_) {
      _cacheDir = Directory('${Directory.systemTemp.path}/edge_tts_cache');
    }
    try {
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (_) {}
    _isInitialized = true;
  }

  String _cleanVoiceId(String voice) {
    final token = voice.split(' ').first.trim();
    if (token.startsWith('en-') || token.startsWith('en_')) {
      return token.replaceAll('_', '-');
    }
    if (token.contains('Neural')) {
      return token;
    }
    // Map legacy or voice profiles to matching studio voice
    switch (token) {
      case 'am_michael':
        return 'en-US-AndrewMultilingualNeural';
      case 'af_bella':
        return 'en-US-EmmaMultilingualNeural';
      case 'af_sarah':
        return 'en-US-MichelleNeural';
      case 'am_adam':
        return 'en-US-EricNeural';
      case 'bf_emma':
        return 'en-GB-LibbyNeural';
      case 'bm_george':
        return 'en-GB-ThomasNeural';
      case 'cjk_storyteller_bilingual':
        return 'en-SG-WayneNeural';
      case 'cjk_female_narrator':
        return 'en-SG-LunaNeural';
      default:
        return 'en-US-ChristopherNeural';
    }
  }

  String _formatRate(double speed) {
    final pct = ((speed - 1.0) * 100).round();
    if (pct >= 0) {
      return '+$pct%';
    } else {
      return '$pct%';
    }
  }

  String _formatPitch(double pitch) {
    final hz = ((pitch - 1.0) * 50).round();
    if (hz >= 0) {
      return '+$hz' 'Hz';
    } else {
      return '$hz' 'Hz';
    }
  }

  @override
  Future<String?> synthesizeSentenceToFile(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
  }) async {
    await initialize();
    final cleanText = TextCleaner.prepareSentenceForSpeech(sentence);
    if (cleanText.isEmpty) return null;

    final edgeVoice = _cleanVoiceId(voice);
    final cacheKey = '${edgeVoice}_${cleanText.hashCode}';

    // 1. Instant RAM Cache hit
    if (_cache.containsKey(cacheKey)) {
      final cachedPath = _cache[cacheKey]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      }
    }

    // 2. Reuse in-flight network request if already pre-fetching
    if (_inFlight.containsKey(cacheKey)) {
      return await _inFlight[cacheKey];
    }

    // 3. Initiate synthesis and track in _inFlight
    final future = _performSynthesis(cleanText, edgeVoice, cacheKey, speed, pitch);
    _inFlight[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } catch (e) {
      return null;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<String?> _performSynthesis(
    String cleanText,
    String edgeVoice,
    String cacheKey,
    double speed,
    double pitch,
  ) async {
    try {
      await initialize();
      final cacheDir = _cacheDir ?? Directory('${Directory.systemTemp.path}/edge_tts_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final targetPath = '${cacheDir.path}/$cacheKey.mp3';
      final file = File(targetPath);
      if (await file.exists() && await file.length() > 0) {
        _cache[cacheKey] = targetPath;
        return targetPath;
      }

      final rateStr = _formatRate(speed);
      final pitchStr = _formatPitch(pitch);

      final communicate = Communicate(
        text: cleanText,
        voice: edgeVoice,
        rate: rateStr,
        pitch: pitchStr,
      );

      final rawBytes = await communicate.toBytes().timeout(const Duration(seconds: 10));
      if (rawBytes.isNotEmpty) {
        // Strip trailing Microsoft silent padding frames for 0ms gapless transition
        final trimmedBytes = _trimTrailingSilence(rawBytes);
        await file.writeAsBytes(trimmedBytes);
        _cache[cacheKey] = targetPath;
        return targetPath;
      }
    } catch (e, st) {
      debugPrint('[TTS_DEBUG] _performSynthesis error: $e\n$st');
      return null;
    }
    return null;
  }

  /// Removes trailing silent MP3 padding frames (0x55) injected by Microsoft Edge TTS.
  /// Eliminates the 800ms-1000ms dead silence at the end of every synthesized line,
  /// giving human-level seamless audio transitions.
  static Uint8List _trimTrailingSilence(Uint8List bytes) {
    int end = bytes.length;
    const int frameSize = 144;
    while (end >= frameSize) {
      int count55 = 0;
      for (int i = end - frameSize; i < end; i++) {
        if (bytes[i] == 0x55) count55++;
      }
      if (count55 > 70) {
        end -= frameSize;
      } else {
        break;
      }
    }
    return end < bytes.length ? Uint8List.sublistView(bytes, 0, end) : bytes;
  }

  @override
  Future<void> speakSentenceDirect(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
    required Function() onDone,
  }) async {
    await initialize();

    final cleanText = TextCleaner.prepareSentenceForSpeech(sentence);
    if (cleanText.isEmpty) {
      onDone();
      return;
    }

    try {
      debugPrint('[TTS_DEBUG] EdgeNeuralEngine: synthesizing "$cleanText"');
      final audioPath = await synthesizeSentenceToFile(
        cleanText,
        voice: voice,
        speed: speed,
        pitch: pitch,
      );

      debugPrint('[TTS_DEBUG] EdgeNeuralEngine: audioPath=$audioPath');

      if (audioPath != null && await File(audioPath).exists()) {
        _playerSub?.cancel();
        await _player.setFilePath(audioPath);

        _playerSub = _player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            debugPrint('[TTS_DEBUG] EdgeNeuralEngine: player completed for "$cleanText"');
            _playerSub?.cancel();
            _playerSub = null;
            onDone();
          }
        });

        await _player.play();
        return;
      } else {
        debugPrint('[TTS_DEBUG] EdgeNeuralEngine: audioPath is null or file does not exist, falling back');
      }
    } catch (e, st) {
      debugPrint('[TTS_DEBUG] EdgeNeuralEngine exception: $e\n$st');
    }

    debugPrint('[TTS_DEBUG] EdgeNeuralEngine: invoking fallback SystemFallbackEngine');
    await _fallback.speakSentenceDirect(
      cleanText,
      voice: voice,
      speed: speed,
      pitch: pitch,
      onDone: onDone,
    );
  }

  @override
  Future<void> stop() async {
    _playerSub?.cancel();
    _playerSub = null;
    try {
      await _player.stop();
    } catch (_) {}
    await _fallback.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
    await _fallback.dispose();
  }
}
