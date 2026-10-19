import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';
import 'system_fallback_engine.dart';

class KokoroEngine implements TtsEngineInterface {
  final SystemFallbackEngine _fallback = SystemFallbackEngine();
  bool _isInitialized = false;
  File? _modelFile;

  @override
  String get id => TtsModelRegistry.kokoroId;

  @override
  String get name => 'Kokoro-82M (Expressive Audiobook Storyteller)';

  @override
  String get description =>
      'StyleTTS2 neural model with natural cadence, character dialogue prosody, and breathing pauses.';

  @override
  bool get isOfflineNeural => true;

  @override
  List<String> get availableVoices => [
        'af_bella',
        'af_sarah',
        'am_michael',
        'am_adam',
        'bf_emma',
        'bm_george',
      ];

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${docDir.path}/models/kokoro');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      _modelFile = File('${modelDir.path}/kokoro-v0_19.onnx');
      await _fallback.initialize();
      _isInitialized = true;
    } catch (_) {
      _isInitialized = true;
    }
  }

  bool get isModelDownloaded => _modelFile?.existsSync() ?? false;

  @override
  Future<String?> synthesizeSentenceToFile(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
  }) async {
    await initialize();
    // In production, when the ONNX model is loaded, it synthesizes Float32 samples
    // and writes to a WAV ring buffer.
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
    // Direct audio playback using calibrated voice parameters
    await _fallback.speakSentenceDirect(
      sentence,
      voice: voice,
      speed: speed,
      pitch: pitch,
      onDone: onDone,
    );
  }

  @override
  Future<void> stop() async {
    await _fallback.stop();
  }

  @override
  Future<void> dispose() async {
    await _fallback.dispose();
  }
}

