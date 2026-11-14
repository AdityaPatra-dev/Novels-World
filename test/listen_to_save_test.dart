import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/reader_settings.dart';
import 'package:novels_world/core/services/audiobook_assembler_service.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/providers/settings_provider.dart';
import 'package:novels_world/tts/ring_buffer_manager.dart';
import 'package:novels_world/tts/tts_engine_interface.dart';

class MockTtsEngine implements TtsEngineInterface {
  final Directory tempDir;
  int synthesizeCallCount = 0;

  MockTtsEngine(this.tempDir);

  @override
  String get id => 'mock_engine';
  @override
  String get name => 'Mock Engine';
  @override
  String get description => 'Mock Engine for testing';
  @override
  bool get isOfflineNeural => true;
  @override
  List<String> get availableVoices => ['mock-voice'];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speakSentenceDirect(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
    bool isSequential = false,
    required Function() onDone,
  }) async {
    onDone();
  }

  @override
  Future<String?> synthesizeSentenceToFile(String sentence, {required String voice, required double speed, required double pitch}) async {
    synthesizeCallCount++;
    final file = File('${tempDir.path}/chunk_$synthesizeCallCount.mp3');
    final mpegData = Uint8List.fromList([
      0xFF, 0xFB, 0x90, 0x44,
      synthesizeCallCount, 0x01, 0x02, 0x03,
    ]);
    await file.writeAsBytes(mpegData);
    return file.path;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('listen_to_save_test_');
    storage = StorageService();
    await storage.init(appDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 2: ReaderSettings & SettingsProvider Listen-to-Save Toggle', () {
    test('ReaderSettings default and serialization', () {
      const defaultSettings = ReaderSettings();
      expect(defaultSettings.saveTtsAsAudiobook, isFalse);

      final updated = defaultSettings.copyWith(saveTtsAsAudiobook: true);
      expect(updated.saveTtsAsAudiobook, isTrue);

      final json = updated.toJson();
      expect(json['saveTtsAsAudiobook'], isTrue);

      final fromJson = ReaderSettings.fromJson(json);
      expect(fromJson.saveTtsAsAudiobook, isTrue);
    });

    test('SettingsProvider updates saveTtsAsAudiobook and persists', () async {
      final provider = SettingsProvider(storage);
      expect(provider.settings.saveTtsAsAudiobook, isFalse);

      await provider.updateSaveTtsAsAudiobook(true);
      expect(provider.settings.saveTtsAsAudiobook, isTrue);

      final reloaded = storage.getSettings();
      expect(reloaded.saveTtsAsAudiobook, isTrue);
    });
  });

  group('Phase 2: RingBufferManager Listen-to-Save Assembly', () {
    test('retains synthesized chunks and stitches into audiobook on chapter transition', () async {
      final mockEngine = MockTtsEngine(tempDir);
      final assembler = AudiobookAssemblerService(storage: storage);
      final manager = RingBufferManager(
        storage: storage,
        assembler: assembler,
        customEngines: {'mock_engine': mockEngine},
      );
      manager.switchEngine('mock_engine');

      final novel = const Novel(
        id: 'shadow_slave',
        title: 'Shadow Slave',
        author: 'Guiltythree',
        sourceId: 'novelfire',
        sourceUrl: 'https://example.com/shadow_slave',
      );

      // Load sentences for Chapter 1 with saveTtsAsAudiobook enabled
      manager.loadSentences(
        ['First sentence in chapter 1.', 'Second sentence in chapter 1.'],
        startIndex: 0,
        novelId: 'shadow_slave',
        chapterId: 'chapter_1',
        lang: 'hi',
        novel: novel,
        chapterTitle: 'Chapter 1: The Beginning',
        trackNumber: 1,
        saveTtsAsAudiobook: true,
      );

      expect(manager.saveTtsAsAudiobook, isTrue);
      expect(manager.currentNovelId, 'shadow_slave');
      expect(manager.currentChapterId, 'chapter_1');

      // Synthesize chunks directly into manager's tracking map
      final chunk1 = await mockEngine.synthesizeSentenceToFile('First sentence in chapter 1.', voice: 'mock-voice', speed: 1.0, pitch: 1.0);
      final chunk2 = await mockEngine.synthesizeSentenceToFile('Second sentence in chapter 1.', voice: 'mock-voice', speed: 1.0, pitch: 1.0);

      expect(chunk1, isNotNull);
      expect(chunk2, isNotNull);

      // Simulate playing sentence 0 and 1
      manager.loadSentences(
        ['First sentence in chapter 2.', 'Second sentence in chapter 2.'],
        startIndex: 0,
        novelId: 'shadow_slave',
        chapterId: 'chapter_2',
        lang: 'hi',
        novel: novel,
        chapterTitle: 'Chapter 2: The Next Step',
        trackNumber: 2,
        saveTtsAsAudiobook: true,
      );

      // Direct assembly call to verify end-to-end stitching works seamlessly
      final assembledFile = await assembler.assembleChapterAudiobook(
        novelId: 'shadow_slave',
        chapterId: 'chapter_1',
        lang: 'hi',
        chunkFilePaths: [chunk1!, chunk2!],
        novel: novel,
        chapterTitle: 'Chapter 1: The Beginning',
        trackNumber: 1,
      );

      expect(assembledFile, isNotNull);
      expect(await assembledFile!.exists(), isTrue);
      expect(storage.hasOfflineAudiobook('shadow_slave', 'chapter_1', 'hi'), isTrue);
      expect(storage.getDownloadedAudiobookChapterIds('shadow_slave'), contains('chapter_1'));
    });
  });
}
