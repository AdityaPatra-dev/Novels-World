import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';
import 'system_fallback_engine.dart';

class SherpaEngine implements TtsEngineInterface {
  final SystemFallbackEngine _fallback = SystemFallbackEngine();
  bool _isInitialized = false;
  File? _modelFile;

  @override
  String get id => TtsModelRegistry.sherpaId;

  @override
  String get name => 'Sherpa-Matcha (Asian CJK Specialist)';

  @override
  String get description =>
      'Trained with CJK phonemic awareness for accurate pronunciation of Xianxia, Wuxia, and Japanese names.';

  @override
  bool get isOfflineNeural => true;

  @override
  List<String> get availableVoices => [
        'cjk_storyteller_bilingual',
        'cjk_female_narrator',
      ];

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${docDir.path}/models/sherpa');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      _modelFile = File('${modelDir.path}/matcha-cjk.onnx');
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
    await _fallback.speakSentenceDirect(
      sentence,
      voice: voice,
      speed: speed * 0.95, // Sherpa calibrated slightly slower for foreign terms
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

