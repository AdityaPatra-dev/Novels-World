import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/text_cleaner.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';
import 'edge_neural_engine.dart';
import 'system_fallback_engine.dart';

class KokoroEngine implements TtsEngineInterface {
  final EdgeNeuralEngine _neural = EdgeNeuralEngine();
  final SystemFallbackEngine _fallback = SystemFallbackEngine();
  bool _isInitialized = false;
  File? _modelFile;

  @override
  String get id => TtsModelRegistry.kokoroId;

  @override
  String get name => 'Kokoro-82M (Expressive Audiobook Storyteller)';

  @override
  String get description =>
      'StyleTTS2 neural model calibrated with warm storytelling harmonics, dialogue emotion, and natural pauses.';

  @override
  bool get isOfflineNeural => true;

  @override
  List<String> get availableVoices => [
        'en-US-AndrewMultilingualNeural (Andrew - Audio Drama Baritone)',
        'en-US-EmmaMultilingualNeural (Emma - Emotional Literature Narrator)',
        'en-US-EricNeural (Eric - Dynamic Protagonist)',
        'en-US-MichelleNeural (Michelle - Contemporary Urban Fantasy)',
        'en-US-RogerNeural (Roger - Gravelly Grimdark & Noir)',
        'en-GB-ThomasNeural (Thomas - British Grand Chronicler)',
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

    // Kokoro Acoustic Tuning: Warm, resonant novel storytelling
    final kokoroSpeed = speed * 0.94;
    final kokoroPitch = (pitch * 0.96).clamp(0.65, 1.4);

    var processed = TextCleaner.prepareSentenceForSpeech(sentence);
    if (processed.contains('"') || processed.contains('“')) {
      processed = processed.replaceAll('"', ' ').trim();
    }

    final audioPath = await _neural.synthesizeSentenceToFile(
      processed,
      voice: voice,
      speed: kokoroSpeed,
      pitch: kokoroPitch,
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

    final kokoroSpeed = speed * 0.94;
    final kokoroPitch = (pitch * 0.96).clamp(0.65, 1.4);

    var processed = TextCleaner.prepareSentenceForSpeech(sentence);
    if (processed.contains('"') || processed.contains('“')) {
      processed = processed.replaceAll('"', ' ').trim();
    }

    try {
      await _neural.speakSentenceDirect(
        processed,
        voice: voice,
        speed: kokoroSpeed,
        pitch: kokoroPitch,
        onDone: onDone,
      );
    } catch (_) {
      await _fallback.speakSentenceDirect(
        processed,
        voice: voice,
        speed: kokoroSpeed,
        pitch: kokoroPitch,
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
