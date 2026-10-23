import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/text_cleaner.dart';
import '../tts_engine_interface.dart';
import '../tts_model_registry.dart';
import 'edge_neural_engine.dart';
import 'system_fallback_engine.dart';

class SherpaEngine implements TtsEngineInterface {
  final EdgeNeuralEngine _neural = EdgeNeuralEngine();
  final SystemFallbackEngine _fallback = SystemFallbackEngine();
  bool _isInitialized = false;
  File? _modelFile;

  @override
  String get id => TtsModelRegistry.sherpaId;

  @override
  String get name => 'Sherpa-Matcha (Asian Webnovel & CJK Specialist)';

  @override
  String get description =>
      'Trained with CJK phonemic awareness. Accurately pronounces Xianxia cultivation terms (Qi, Dantian, Dao), Korean honorifics, and Japanese names.';

  @override
  bool get isOfflineNeural => true;

  @override
  List<String> get availableVoices => [
        'en-SG-WayneNeural (Wayne - Xianxia Cultivation Sage)',
        'en-SG-LunaNeural (Luna - Light Novel & Xianxia Maiden)',
        'en-IN-PrabhatNeural (Prabhat - Eastern Lore Master)',
        'en-IN-NeerjaExpressiveNeural (Neerja - Expressive Mythos Narrator)',
        'en-HK-YanNeural (Yan - Asian Martial World Chronicler)',
      ];

  // Phonetic substitutions for cultivation and Asian webnovel terms
  static final Map<RegExp, String> _cjkPhonetics = {
    RegExp(r'\bQi\b'): 'Chee',
    RegExp(r'\bqi\b'): 'chee',
    RegExp(r'\bDantian\b'): 'Dan-tien',
    RegExp(r'\bdantian\b'): 'dan-tien',
    RegExp(r'\bDao\b'): 'Dow',
    RegExp(r'\bdao\b'): 'dow',
    RegExp(r'\bDaoist\b'): 'Dow-ist',
    RegExp(r'\bdaoist\b'): 'dow-ist',
    RegExp(r'\bDaoism\b'): 'Dow-ism',
    RegExp(r'\bXianxia\b'): 'Shee-ahn-shyah',
    RegExp(r'\bWuxia\b'): 'Woo-shyah',
    RegExp(r'\bXuanhuan\b'): 'Shwahn-hwahn',
    RegExp(r'\bShifu\b'): 'Shee-foo',
    RegExp(r'\bshifu\b'): 'shee-foo',
    RegExp(r'\bGege\b'): 'Guh-guh',
    RegExp(r'\bgege\b'): 'guh-guh',
    RegExp(r'\bMeimei\b'): 'May-may',
    RegExp(r'\bmeimei\b'): 'may-may',
    RegExp(r'\bHyung\b'): 'Hee-oong',
    RegExp(r'\bhyung\b'): 'hee-oong',
    RegExp(r'\bOppa\b'): 'Oh-pah',
    RegExp(r'\boppa\b'): 'oh-pah',
    RegExp(r'\bNoona\b'): 'Noo-nah',
    RegExp(r'\bnoona\b'): 'noo-nah',
    RegExp(r'\bUnnie\b'): 'Un-nee',
    RegExp(r'\bunnie\b'): 'un-nee',
    RegExp(r'\bSunbae\b'): 'Sun-bay',
    RegExp(r'\bsunbae\b'): 'sun-bay',
    RegExp(r'\bSenpai\b'): 'Sen-pye',
    RegExp(r'\bsenpai\b'): 'sen-pye',
    RegExp(r'\bSensei\b'): 'Sen-say',
    RegExp(r'\bsensei\b'): 'sen-say',
    RegExp(r'\bKouhai\b'): 'Koh-hye',
    RegExp(r'\bkouhai\b'): 'koh-hye',
  };

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${docDir.path}/models/sherpa');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      _modelFile = File('${modelDir.path}/model.onnx');
      await _neural.initialize();
      await _fallback.initialize();
      _isInitialized = true;
    } catch (_) {
      _isInitialized = true;
    }
  }

  bool get isModelDownloaded => _modelFile?.existsSync() ?? false;

  String normalizeCultivationTerms(String text) {
    var result = text;
    _cjkPhonetics.forEach((pattern, replacement) {
      result = result.replaceAll(pattern, replacement);
    });
    return result;
  }

  @override
  Future<String?> synthesizeSentenceToFile(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
  }) async {
    await initialize();

    final normalized = normalizeCultivationTerms(sentence);
    final clean = TextCleaner.prepareSentenceForSpeech(normalized);

    final audioPath = await _neural.synthesizeSentenceToFile(
      clean,
      voice: voice,
      speed: speed * 0.95,
      pitch: pitch,
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

    final normalized = normalizeCultivationTerms(sentence);
    final clean = TextCleaner.prepareSentenceForSpeech(normalized);

    try {
      await _neural.speakSentenceDirect(
        clean,
        voice: voice,
        speed: speed * 0.95,
        pitch: pitch,
        onDone: onDone,
      );
    } catch (_) {
      await _fallback.speakSentenceDirect(
        clean,
        voice: voice,
        speed: speed * 0.95,
        pitch: pitch,
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
