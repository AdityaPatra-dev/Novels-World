import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../core/utils/text_cleaner.dart';
import '../services/web_speech_interop.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';
import '../voice_calibration.dart';

class SystemFallbackEngine implements TtsEngineInterface {
  // Singleton pattern to ensure only ONE FlutterTts instance exists app-wide
  static final SystemFallbackEngine _instance = SystemFallbackEngine._internal();
  factory SystemFallbackEngine() => _instance;
  SystemFallbackEngine._internal();

  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;
  static List<dynamic> _availableSystemVoices = [];
  static final Map<String, Map<String, String>> _voiceCache = {};

  static String? _appliedVoiceName;
  static double? _appliedSpeed;
  static double? _appliedPitch;
  static Function()? _currentCompletion;

  @override
  String get id => TtsModelRegistry.systemId;

  @override
  String get name => 'Device Native (Offline Hardware)';

  @override
  String get description => 'Direct hardware voice synthesizer on your device';

  @override
  bool get isOfflineNeural => false;

  @override
  List<String> get availableVoices {
    return VoiceCalibration.profiles.map((p) => p.displayName).toList();
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (kIsWeb) {
      _isInitialized = true;
      return;
    }
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.48);
      try {
        await _flutterTts.awaitSynthCompletion(false); // Non-blocking synthesis for rapid streaming on native
      } catch (_) {}
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      // Register completion handler once globally
      _flutterTts.setCompletionHandler(() {
        final cb = _currentCompletion;
        _currentCompletion = null;
        cb?.call();
      });

      _flutterTts.setErrorHandler((_) {
        final cb = _currentCompletion;
        _currentCompletion = null;
        cb?.call();
      });

      // Query available voices safely from OS
      final dynamic voices = await _flutterTts.getVoices;
      if (voices is List) {
        _availableSystemVoices = voices;
      }
      _isInitialized = true;
    } catch (_) {
      _isInitialized = true;
    }
  }

  Map<String, String>? _resolveBestVoice(VoiceProfile profile) {
    if (_voiceCache.containsKey(profile.id)) {
      return _voiceCache[profile.id];
    }

    if (_availableSystemVoices.isEmpty) return null;

    // Search for keyword matches in available system voices
    for (final keyword in profile.targetVoiceKeywords) {
      for (final v in _availableSystemVoices) {
        if (v is Map) {
          final name = (v['name'] ?? '').toString().toLowerCase();
          final locale = (v['locale'] ?? '').toString().toLowerCase();
          if (name.contains(keyword) || locale.contains(keyword)) {
            final resolved = {
              'name': v['name'].toString(),
              'locale': v['locale'].toString(),
            };
            _voiceCache[profile.id] = resolved;
            return resolved;
          }
        }
      }
    }

    // Fallback: pick any English voice matching the locale prefix
    final targetPrefix = profile.accent == 'UK' ? 'en-gb' : 'en-us';
    for (final v in _availableSystemVoices) {
      if (v is Map) {
        final locale = (v['locale'] ?? '').toString().toLowerCase();
        if (locale.startsWith(targetPrefix)) {
          final resolved = {
            'name': v['name'].toString(),
            'locale': v['locale'].toString(),
          };
          _voiceCache[profile.id] = resolved;
          return resolved;
        }
      }
    }

    return null;
  }

  @override
  Future<String?> synthesizeSentenceToFile(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
  }) async {
    return null;
  }

  @override
  Future<void> speakSentenceDirect(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
    required Function() onDone,
  }) async {
    final cleanText = TextCleaner.prepareSentenceForSpeech(sentence);
    if (cleanText.isEmpty) {
      onDone();
      return;
    }

    // On Web, use direct native browser Speech Synthesis API for instant, glitch-free audio
    if (kIsWeb) {
      playWebSpeech(
        cleanText,
        voice: voice,
        rate: speed,
        pitch: pitch,
        onDone: onDone,
      );
      return;
    }

    await initialize();

    try {
      final profile = VoiceCalibration.getProfile(voice);

      // ONLY reload voice if it actually changed — avoiding Android voice pack reset delay!
      final matchedVoice = _resolveBestVoice(profile);
      if (matchedVoice != null && matchedVoice['name'] != _appliedVoiceName) {
        try {
          await _flutterTts.setVoice(matchedVoice);
          _appliedVoiceName = matchedVoice['name'];
        } catch (_) {}
      }

      // ONLY reload speech rate if changed (Android normal speed is ~0.48)
      final effectiveSpeed = (profile.baseSpeed * speed * 0.48).clamp(0.15, 1.0);
      if (_appliedSpeed != effectiveSpeed) {
        await _flutterTts.setSpeechRate(effectiveSpeed);
        _appliedSpeed = effectiveSpeed;
      }

      // ONLY reload pitch if changed
      final effectivePitch = (profile.basePitch * pitch).clamp(0.5, 2.0);
      if (_appliedPitch != effectivePitch) {
        await _flutterTts.setPitch(effectivePitch);
        _appliedPitch = effectivePitch;
      }

      debugPrint('[TTS_DEBUG] SystemFallbackEngine: calling flutterTts.speak for "$cleanText"');
      _currentCompletion = () {
        debugPrint('[TTS_DEBUG] SystemFallbackEngine: flutterTts finished "$cleanText"');
        onDone();
      };
      await _flutterTts.speak(cleanText);
    } catch (e, st) {
      debugPrint('[TTS_DEBUG] SystemFallbackEngine error: $e\n$st');
      onDone();
    }
  }

  @override
  Future<void> stop() async {
    if (kIsWeb) {
      stopWebSpeech();
      return;
    }
    _currentCompletion = null;
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
