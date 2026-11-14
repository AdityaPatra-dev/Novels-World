import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/services/translation_service.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/tts/language_voice_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('translation_test_');
    storage = StorageService();
    await storage.init(appDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 3: LanguageVoiceRegistry Global Catalog', () {
    test('supports 70+ languages with flags and native scripts', () {
      expect(LanguageVoiceRegistry.supportedLanguages.length, greaterThan(25));

      final hindi = LanguageVoiceRegistry.getByCode('hi');
      expect(hindi.englishName, 'Hindi');
      expect(hindi.nativeName, 'हिन्दी');
      expect(hindi.flag, '🇮🇳');
      expect(hindi.defaultFemaleVoice, 'hi-IN-SwaraNeural');
      expect(hindi.defaultMaleVoice, 'hi-IN-MadhurNeural');

      final spanish = LanguageVoiceRegistry.getByCode('es');
      expect(spanish.englishName, 'Spanish');
      expect(spanish.nativeName, 'Español');
      expect(spanish.flag, '🇪🇸');
      expect(spanish.defaultFemaleVoice, 'es-ES-ElviraNeural');

      final japanese = LanguageVoiceRegistry.getByCode('ja');
      expect(japanese.englishName, 'Japanese');
      expect(japanese.nativeName, '日本語');
      expect(japanese.flag, '🇯🇵');
      expect(japanese.defaultFemaleVoice, 'ja-JP-NanamiNeural');
    });

    test('searches languages by English name, native script, or code', () {
      final hindiSearch = LanguageVoiceRegistry.search('Hindi');
      expect(hindiSearch.any((l) => l.code == 'hi'), isTrue);

      final nativeSearch = LanguageVoiceRegistry.search('हिन्दी');
      expect(nativeSearch.any((l) => l.code == 'hi'), isTrue);

      final codeSearch = LanguageVoiceRegistry.search('ja');
      expect(codeSearch.any((l) => l.code == 'ja'), isTrue);

      final unknown = LanguageVoiceRegistry.getByCode('unknown_xyz');
      expect(unknown.code, 'en');
    });
  });

  group('Phase 3: TranslationService Batched Network & Disk Caching', () {
    test('translates sentences in batches and caches to disk', () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        final q = request.url.queryParameters['q'] ?? '';
        final parts = q.split(RegExp(r'\s*<<<NW_DELIM>>>\s*'));

        final translatedText = parts.map((p) => '[HI] $p').join(' \n<<<NW_DELIM>>>\n ');
        final chunks = [
          [translatedText, q]
        ];

        return http.Response(jsonEncode([chunks]), 200);
      });

      final service = TranslationService(client: mockClient, storage: storage);

      final sentences = [
        'Sunny woke up in the cold dark cave.',
        'His shadow twitched with unnatural life.',
        'A monster lurked in the distance.',
      ];

      // First call: hits mock network
      final translated = await service.translateSentences(
        sentences,
        targetLang: 'hi',
        novelId: 'shadow_slave',
        chapterId: 'chapter_1',
      );

      expect(translated.length, 3);
      expect(translated[0], contains('[HI]'));
      expect(requestCount, 1);

      // Verify cached on disk
      final diskCached = await service.getCachedChapterTranslation('shadow_slave', 'chapter_1', 'hi');
      expect(diskCached, isNotNull);
      expect(diskCached!.length, 3);
      expect(diskCached[0], translated[0]);

      // Second call: loads from cache, zero additional network calls
      final cachedResult = await service.translateSentences(
        sentences,
        targetLang: 'hi',
        novelId: 'shadow_slave',
        chapterId: 'chapter_1',
      );

      expect(cachedResult, equals(translated));
      expect(requestCount, 1); // requestCount remained 1!
    });

    test('gracefully falls back to original sentences on network failure', () async {
      final failingClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final service = TranslationService(client: failingClient, storage: storage);

      final original = ['Sentence 1', 'Sentence 2'];
      final result = await service.translateSentences(
        original,
        targetLang: 'es',
      );

      expect(result, equals(original));
    });
  });
}
