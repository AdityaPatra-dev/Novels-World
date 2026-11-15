import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/tts/tts_model_registry.dart';
import 'package:novels_world/tts/voice_calibration.dart';
import 'package:novels_world/core/services/global_search_controller.dart';
import 'package:novels_world/extractors/novel_source.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';

class _MockFastSource implements NovelSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final String baseUrl;
  @override
  final String lang = 'en';
  @override
  final String iconUrl = '';
  @override
  final int estimatedNovelCount = 1000;

  int searchCallCount = 0;

  _MockFastSource(this.id, this.name) : baseUrl = 'https://mock-$id.com';

  @override
  Future<List<Novel>> getPopular({int page = 1}) async => [];

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => [];

  @override
  Future<Novel> getNovelDetails(String novelUrl) async => throw UnimplementedError();

  @override
  Future<List<Chapter>> getChapterList(String novelUrl, {int page = 1, void Function(List<Chapter> batch)? onBatchLoaded}) async => [];

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async =>
      const ChapterContent(novelId: '1', chapterId: '1', title: 'Chapter 1', rawText: 'Content', paragraphs: ['Content']);

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    searchCallCount++;
    await Future.delayed(const Duration(milliseconds: 20));
    return [
      Novel(
        id: '$id-1',
        title: 'Shadow Slave ($name)',
        coverUrl: 'https://img.com/cover.jpg',
        author: 'Guiltythree',
        sourceId: id,
        sourceUrl: '$baseUrl/shadow-slave',
      ),
    ];
  }
}

List<VoiceProfile> filterVoicesForModel(TtsModelInfo model, String currentLang, bool isEnglish) {
  return VoiceCalibration.getProfilesForLanguage(currentLang).where((p) {
    if (model.id == TtsModelRegistry.systemId) {
      return p.id.startsWith('system') || p.id == 'default';
    }
    if (isEnglish) {
      return model.voices.any((v) => v.startsWith(p.id));
    }
    return !p.id.startsWith('system');
  }).toList();
}

void main() {
  group('TTS Engine & Voice Filter Tests', () {
    test('English persona filter strictly limits voices to the active AI audio model', () {
      const isEnglish = true;
      const currentLang = 'en';

      // 1. Microsoft HD Neural
      final edgeModel = TtsModelRegistry.getModel(TtsModelRegistry.edgeNeuralId);
      final edgeProfiles = filterVoicesForModel(edgeModel, currentLang, isEnglish);

      expect(edgeProfiles.length, equals(8));
      expect(edgeProfiles.any((p) => p.id == 'en-US-ChristopherNeural'), isTrue);
      expect(edgeProfiles.any((p) => p.id == 'en-US-JennyNeural'), isTrue);
      expect(edgeProfiles.any((p) => p.id == 'en-US-AndrewMultilingualNeural'), isFalse); // Kokoro voice
      expect(edgeProfiles.any((p) => p.id == 'en-US-SteffanNeural'), isFalse); // Piper voice
      expect(edgeProfiles.any((p) => p.id == 'en-SG-WayneNeural'), isFalse); // Sherpa voice

      // 2. Kokoro-82M
      final kokoroModel = TtsModelRegistry.getModel(TtsModelRegistry.kokoroId);
      final kokoroProfiles = filterVoicesForModel(kokoroModel, currentLang, isEnglish);

      expect(kokoroProfiles.length, equals(6));
      expect(kokoroProfiles.any((p) => p.id == 'en-US-AndrewMultilingualNeural'), isTrue);
      expect(kokoroProfiles.any((p) => p.id == 'en-US-EmmaMultilingualNeural'), isTrue);
      expect(kokoroProfiles.any((p) => p.id == 'en-US-ChristopherNeural'), isFalse);

      // 3. Piper Fast Neural
      final piperModel = TtsModelRegistry.getModel(TtsModelRegistry.piperId);
      final piperProfiles = filterVoicesForModel(piperModel, currentLang, isEnglish);

      expect(piperProfiles.length, equals(5));
      expect(piperProfiles.any((p) => p.id == 'en-US-SteffanNeural'), isTrue);
      expect(piperProfiles.any((p) => p.id == 'en-GB-LibbyNeural'), isTrue);
      expect(piperProfiles.any((p) => p.id == 'en-US-ChristopherNeural'), isFalse);

      // 4. Sherpa-Matcha
      final sherpaModel = TtsModelRegistry.getModel(TtsModelRegistry.sherpaId);
      final sherpaProfiles = filterVoicesForModel(sherpaModel, currentLang, isEnglish);

      expect(sherpaProfiles.length, equals(5));
      expect(sherpaProfiles.any((p) => p.id == 'en-SG-WayneNeural'), isTrue);
      expect(sherpaProfiles.any((p) => p.id == 'en-IN-PrabhatNeural'), isTrue);
      expect(sherpaProfiles.any((p) => p.id == 'en-US-ChristopherNeural'), isFalse);

      // 5. Device Native System
      final systemModel = TtsModelRegistry.getModel(TtsModelRegistry.systemId);
      final systemProfiles = filterVoicesForModel(systemModel, currentLang, isEnglish);

      expect(systemProfiles.length, equals(1));
      expect(systemProfiles.first.id, equals('default'));
    });

    test('Non-English languages load language-specific studio calibrated profiles', () {
      final hindiProfiles = VoiceCalibration.getProfilesForLanguage('hi');
      expect(hindiProfiles.isNotEmpty, isTrue);
      expect(hindiProfiles.any((p) => p.id.contains('hi-IN') || p.accent == 'India' || p.accent == 'Native'), isTrue);
    });
  });

  group('Global Search Caching and Worker Concurrency Tests', () {
    test('Query caching returns instant results without re-invoking sources', () async {
      final sourceA = _MockFastSource('src_a', 'Source A');
      final sourceB = _MockFastSource('src_b', 'Source B');
      final controller = GlobalSearchController();

      // Initial search
      await controller.search('Shadow', targetSources: [sourceA, sourceB]);
      expect(controller.value.groupedMatches.isNotEmpty, isTrue);
      expect(sourceA.searchCallCount, equals(1));
      expect(sourceB.searchCallCount, equals(1));

      // Second identical search should hit _queryCache immediately
      await controller.search('Shadow', targetSources: [sourceA, sourceB]);
      expect(controller.value.groupedMatches.isNotEmpty, isTrue);
      // Source search count must NOT increase because it served from RAM cache!
      expect(sourceA.searchCallCount, equals(1));
      expect(sourceB.searchCallCount, equals(1));
    });
  });
}
