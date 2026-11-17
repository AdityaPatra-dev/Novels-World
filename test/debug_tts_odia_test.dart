import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/tts/engines/edge_neural_engine.dart';
import 'package:novels_world/tts/services/odia_transliteration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Test EdgeNeuralEngine synthesizing Odia sample', () async {
    final engine = EdgeNeuralEngine();
    await engine.initialize();

    const sample = 'ଉପନ୍ୟାସ ଜଗତକୁ ଆପଣଙ୍କୁ ସ୍ୱାଗତ, ଗଳ୍ପ ଉପଭୋଗ କରନ୍ତୁ।';
    print('Original text: $sample');
    final transliterated = OdiaTransliteration.toDevanagari(sample);
    print('Transliterated: $transliterated');

    final femalePath = await engine.synthesizeSentenceToFile(
      sample,
      voice: 'or-IN-SubhasiniNeural',
      speed: 1.0,
      pitch: 1.0,
    );
    print('Female synthesis audioPath: $femalePath');
    if (femalePath != null) {
      final f = File(femalePath);
      print('Female file size: ${await f.length()} bytes');
      expect(await f.length() > 5000, true);
    }

    final malePath = await engine.synthesizeSentenceToFile(
      sample,
      voice: 'or-IN-SukantNeural',
      speed: 1.0,
      pitch: 1.0,
    );
    print('Male synthesis audioPath: $malePath');
    if (malePath != null) {
      final f = File(malePath);
      print('Male file size: ${await f.length()} bytes');
      expect(await f.length() > 5000, true);
    }
  });
}
