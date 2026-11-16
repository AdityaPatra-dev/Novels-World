import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/providers/reader_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Reader Continuity & Background Playback Tests', () {
    test('Re-entering the same chapter does NOT stop TTS or reset active sentence', () async {
      final tempDir = Directory.systemTemp.createTempSync('reader_continuity_test');
      final storage = StorageService();
      await storage.init(appDir: tempDir);

      final novel = const Novel(
        id: 'novel_123',
        title: 'Background Audio Novel',
        author: 'Author Test',
        sourceId: 'readnovelfull',
        sourceUrl: 'https://test.com/novel/123',
      );
      final ch1 = const Chapter(
        id: 'ch_1',
        novelId: 'novel_123',
        title: 'Chapter 1: The Beginning',
        url: 'https://test.com/ch1',
      );
      final ch2 = const Chapter(
        id: 'ch_2',
        novelId: 'novel_123',
        title: 'Chapter 2: The Journey',
        url: 'https://test.com/ch2',
      );

      await storage.cacheChapterContent(ChapterContent(
        chapterId: 'ch_1',
        novelId: 'novel_123',
        title: 'Chapter 1: The Beginning',
        rawText: 'Text',
        paragraphs: ['P1 ' * 300, 'P2 ' * 300, 'P3 ' * 300],
      ));

      await storage.cacheChapterContent(ChapterContent(
        chapterId: 'ch_2',
        novelId: 'novel_123',
        title: 'Chapter 2: The Journey',
        rawText: 'Text 2',
        paragraphs: ['Chapter two text here. ' * 50],
      ));

      final reader = ReaderProvider(storage);
      await reader.initializeNovelReader(
        novel: novel,
        chapters: [ch1, ch2],
        initialChapter: ch1,
      );

      expect(reader.currentChapter?.id, equals('ch_1'));
      expect(reader.sentences.isNotEmpty, isTrue);
      expect(reader.activeSentenceIndex, equals(0));

      // Simulate advancing to sentence 1 while reading aloud in background
      reader.setActiveSentence(1);
      expect(reader.activeSentenceIndex, equals(1));

      // User presses back, explores app, then re-enters the same Chapter 1:
      await reader.initializeNovelReader(
        novel: novel,
        chapters: [ch1, ch2],
        initialChapter: ch1,
      );

      // Must preserve the current reading position and not reset to 0!
      expect(reader.currentChapter?.id, equals('ch_1'));
      expect(reader.activeSentenceIndex, equals(1));
    });

    test('Entering a different chapter reloads content and starts from sentence 0', () async {
      final tempDir = Directory.systemTemp.createTempSync('reader_switch_test');
      final storage = StorageService();
      await storage.init(appDir: tempDir);

      final novel = const Novel(
        id: 'novel_123',
        title: 'Background Audio Novel',
        author: 'Author Test',
        sourceId: 'readnovelfull',
        sourceUrl: 'https://test.com/novel/123',
      );
      final ch1 = const Chapter(
        id: 'ch_1',
        novelId: 'novel_123',
        title: 'Chapter 1',
        url: 'https://test.com/ch1',
      );
      final ch2 = const Chapter(
        id: 'ch_2',
        novelId: 'novel_123',
        title: 'Chapter 2',
        url: 'https://test.com/ch2',
      );

      await storage.cacheChapterContent(const ChapterContent(
        chapterId: 'ch_1',
        novelId: 'novel_123',
        title: 'Chapter 1',
        rawText: 'Sentence one.',
        paragraphs: ['Sentence one.'],
      ));
      await storage.cacheChapterContent(const ChapterContent(
        chapterId: 'ch_2',
        novelId: 'novel_123',
        title: 'Chapter 2',
        rawText: 'Sentence from chapter two.',
        paragraphs: ['Sentence from chapter two.'],
      ));

      final reader = ReaderProvider(storage);
      await reader.initializeNovelReader(
        novel: novel,
        chapters: [ch1, ch2],
        initialChapter: ch1,
      );

      reader.setActiveSentence(1);

      // Now enter Chapter 2
      await reader.initializeNovelReader(
        novel: novel,
        chapters: [ch1, ch2],
        initialChapter: ch2,
      );

      expect(reader.currentChapter?.id, equals('ch_2'));
      expect(reader.activeSentenceIndex, equals(0));
    });
  });
}
