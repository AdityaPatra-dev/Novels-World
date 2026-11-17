import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/odiabibhaba_extractor.dart';
import 'package:novels_world/extractors/bespoke/or_wikisource_extractor.dart';
import 'package:novels_world/tts/engines/edge_neural_engine.dart';
import 'package:novels_world/tts/services/odia_transliteration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Odia Pipeline & Sources Comprehensive Verification', () {
    test('1. Script detection and phonetic transliteration', () {
      final odiaText = 'ଉପନ୍ୟାସ ଜଗତକୁ ଆପଣଙ୍କୁ ସ୍ୱାଗତ, ଗଳ୍ପ ଉପଭୋଗ କରନ୍ତୁ।';
      final detected = OdiaTransliteration.detectScript(odiaText);
      expect(detected, equals('or'));

      final deva = OdiaTransliteration.toDevanagari(odiaText);
      expect(deva, contains('उपन्यास'));
      expect(deva, contains('स्वागत'));
      print('Transliterated Devanagari: $deva');
    });

    test('2. EdgeNeuralEngine synthesizes Odia female and male voices', () async {
      final engine = EdgeNeuralEngine();
      await engine.initialize();

      const sample = 'ଉପନ୍ୟାସ ଜଗତକୁ ଆପଣଙ୍କୁ ସ୍ୱାଗତ, ଗଳ୍ପ ଉପଭୋଗ କରନ୍ତୁ।';

      final femalePath = await engine.synthesizeSentenceToFile(
        sample,
        voice: 'or-IN-SubhasiniNeural',
        speed: 1.0,
        pitch: 1.0,
      );
      expect(femalePath, isNotNull);
      expect(File(femalePath!).existsSync(), isTrue);
      expect(File(femalePath).lengthSync(), greaterThan(2000));
      print('Female voice MP3 bytes: ${File(femalePath).lengthSync()}');

      final malePath = await engine.synthesizeSentenceToFile(
        sample,
        voice: 'or-IN-SukantNeural',
        speed: 1.0,
        pitch: 1.0,
      );
      expect(malePath, isNotNull);
      expect(File(malePath!).existsSync(), isTrue);
      expect(File(malePath).lengthSync(), greaterThan(2000));
      print('Male voice MP3 bytes: ${File(malePath).lengthSync()}');
    });

    test('3. Odia Wikisource parses real chapters and content without author links', () async {
      final extractor = OdiaWikisourceExtractor();
      final results = await extractor.search('ଛମାଣ ଆଠଗୁଣ୍ଠ', page: 1);
      expect(results, isNotEmpty);
      final book = results.first;
      expect(book.title, equals('ଛମାଣ ଆଠଗୁଣ୍ଠ'));

      final chapters = await extractor.getChapterList(book.sourceUrl);
      expect(chapters.length, greaterThan(10));
      // First chapter must be narrative, not author link
      expect(chapters.first.title, isNot(contains('ଲେଖକ')));
      expect(chapters.first.title, contains('ରାମଚନ୍ଦ୍ର ମଙ୍ଗରାଜ'));

      final content = await extractor.getChapterContent(chapters.first.url);
      expect(content.paragraphs.length, greaterThanOrEqualTo(3));
      expect(content.rawText.length, greaterThan(1000));
      print('Wikisource Chha Mana Atha Guntha Ch 1: ${content.paragraphs.length} paras, ${content.rawText.length} chars');
    });

    test('4. Odia Bibhaba extractor provides rich metadata and streaming details', () async {
      final extractor = OdiaBibhabaExtractor();
      final books = await extractor.getPopular(page: 1);
      expect(books, isNotEmpty);
      final book = books.first;

      final details = await extractor.getNovelDetails(book.sourceUrl);
      expect(details.title, isNotEmpty);
      expect(details.isFullBook, isTrue);
      expect(details.bookFormat, equals('pdf'));

      final chapters = await extractor.getChapterList(book.sourceUrl);
      expect(chapters, isNotEmpty);

      final content = await extractor.getChapterContent(chapters.first.url);
      expect(content.paragraphs.length, greaterThanOrEqualTo(5));
      expect(content.rawText, contains('ଓଡ଼ିଆ ବିଭବ'));
      print('Odia Bibhaba book details: ${details.title}, format=${details.bookFormat}, paras=${content.paragraphs.length}');
    });
  });
}
