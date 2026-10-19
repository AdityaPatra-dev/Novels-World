import 'package:flutter_tts/flutter_tts.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';

class SystemFallbackEngine implements TtsEngineInterface {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  @override
  String get id => TtsModelRegistry.systemId;

  @override
  String get name => 'System / Device Native';

  @override
  String get description => 'Zero-download native device TTS';

  @override
  bool get isOfflineNeural => false;

  @override
  List<String> get availableVoices => ['System Default'];

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5); // FlutterTTS normal speed is ~0.5
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
    } catch (_) {
      _isInitialized = true;
    }
  }

  @override
  Future<String?> synthesizeSentenceToFile(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
  }) async {
    // Native system TTS does not always support file synthesis across all Linux/Android versions;
    // speakSentenceDirect is used instead.
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
    await initialize();
    try {
      // Map speed (1.0 default -> 0.5 for FlutterTTS)
      final rate = (speed * 0.5).clamp(0.1, 1.0);
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.setPitch(pitch.clamp(0.5, 2.0));

      _flutterTts.setCompletionHandler(() {
        onDone();
      });

      _flutterTts.setErrorHandler((_) {
        onDone();
      });

      await _flutterTts.speak(sentence);
    } catch (_) {
      onDone();
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

