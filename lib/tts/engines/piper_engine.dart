import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/text_cleaner.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';
import 'edge_neural_engine.dart';
import 'system_fallback_engine.dart';

class PiperEngine implements TtsEngineInterface {
  final EdgeNeuralEngine _neural = EdgeNeuralEngine();
  final SystemFallbackEngine _fallback = SystemFallbackEngine();
  bool _isInitialized = false;
  File? _modelFile;

  @override
  String get id => TtsModelRegistry.piperId;

  @override
  String get name => 'Piper Fast Neural (Speed Reading & Clarity)';

  @override
  String get description =>
      'VITS ultra-fast acoustic model with bright articulation. Ideal for high speeds (1.25x-2.5x) and rapid binge-reading without audio muddying.';

  @override
  bool get isOfflineNeural => true;

  @override
  List<String> get availableVoices => [
        'en-US-SteffanNeural (Steffan - Rapid Crisp Articulation)',
        'en-GB-LibbyNeural (Libby - Fast Snappy British)',
        'en-CA-ClaraNeural (Clara - High-Clarity Progression)',
        'en-CA-LiamNeural (Liam - Rapid Progression Male)',
        'en-AU-NatashaNeural (Natasha - Crystal Clear Articulation)',
      ];

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${docDir.path}/models/piper');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      _modelFile = File('${modelDir.path}/en_US-lessac-high.onnx');
      await _neural.initialize();
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

    // Piper Tuning: Crisp, elevated treble, rapid snappy tempo for speed listeners
    final piperSpeed = speed * 1.08;
    final piperPitch = (pitch * 1.04).clamp(0.7, 1.4);

    final clean = TextCleaner.prepareSentenceForSpeech(sentence);
    final audioPath = await _neural.synthesizeSentenceToFile(
      clean,
      voice: voice,
      speed: piperSpeed,
      pitch: piperPitch,
    );

    return audioPath;
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

    final piperSpeed = speed * 1.08;
    final piperPitch = (pitch * 1.04).clamp(0.7, 1.4);
    final clean = TextCleaner.prepareSentenceForSpeech(sentence);

    try {
      await _neural.speakSentenceDirect(
        clean,
        voice: voice,
        speed: piperSpeed,
        pitch: piperPitch,
        onDone: onDone,
      );
    } catch (_) {
      await _fallback.speakSentenceDirect(
        clean,
        voice: voice,
        speed: piperSpeed,
        pitch: piperPitch,
        onDone: onDone,
      );
    }
  }

  @override
  Future<void> stop() async {
    await _neural.stop();
    await _fallback.stop();
  }

  @override
  Future<void> dispose() async {
    await _neural.dispose();
    await _fallback.dispose();
  }
}
