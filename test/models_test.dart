import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/core/models/reader_settings.dart';
import 'package:novels_world/core/utils/text_cleaner.dart';

void main() {
  group('Novel and Chapter Domain Models', () {
    test('Novel serialization round-trip', () {
      final novel = Novel(
        id: 'test_novel_1',
        sourceId: '1stkissnovel',
        title: 'Shadow Slave',
        author: 'Guiltythree',
        description: 'Growing up in poverty, Sunny never expected anything good from life.',
        coverUrl: 'https://example.com/cover.jpg',
        genres: ['Action', 'Fantasy', 'Mystery'],
        status: 'ONGOING',
        sourceUrl: 'https://1stkissnovel.org/novel/shadow-slave/',
        inLibrary: true,
      );

      final json = novel.toJson();
      final restored = Novel.fromJson(json);

      expect(restored.id, novel.id);
      expect(restored.title, 'Shadow Slave');
      expect(restored.genres.length, 3);
      expect(restored.inLibrary, true);
    });

    test('Chapter serialization round-trip', () {
      const chapter = Chapter(
        id: 'ch_1',
        novelId: 'test_novel_1',
        title: 'Chapter 1: Nightmare Begins',
        chapterNumber: 1.0,
        url: 'https://example.com/ch-1',
        releaseDate: '2 days ago',
      );

      final json = chapter.toJson();
      final restored = Chapter.fromJson(json);

      expect(restored.title, 'Chapter 1: Nightmare Begins');
      expect(restored.chapterNumber, 1.0);
    });

    test('ChapterContent sentence parsing for TTS & Karaoke highlight', () {
      const content = ChapterContent(
        chapterId: 'ch_1',
        novelId: 'test_novel_1',
        title: 'Chapter 1',
        rawText: 'Sunny looked at the sky. It was dark! "Why me?" he whispered.',
        paragraphs: [
          'Sunny looked at the sky. It was dark!',
          '"Why me?" he whispered.',
        ],
      );

      final sentences = content.toSentences();
      expect(sentences.length, greaterThanOrEqualTo(2));
      expect(sentences.first, contains('Sunny looked at the sky'));
    });

    test('TextCleaner strips promotional ad lines and normalizes quotes', () {
      final dirtyParagraphs = [
        'Read latest chapters at 1stkissnovel.org',
        '“He who fights monsters,” whispered the elder.',
        'If you find any errors please let us know to fix it!',
        'A cold breeze swept across the plain.',
      ];

      final cleaned = TextCleaner.cleanParagraphs(dirtyParagraphs);

      expect(cleaned.length, 2);
      expect(cleaned[0], contains('"He who fights monsters,"')); // normalized quotes
      expect(cleaned[1], 'A cold breeze swept across the plain.');
    });

    test('ReaderSettings themes have distinct colors', () {
      const darkSettings = ReaderSettings(theme: ReaderTheme.dark);
      const amoledSettings = ReaderSettings(theme: ReaderTheme.amoled);
      const lightSettings = ReaderSettings(theme: ReaderTheme.light);

      expect(darkSettings.backgroundColor, isNot(equals(amoledSettings.backgroundColor)));
      expect(lightSettings.backgroundColor, isNot(equals(darkSettings.backgroundColor)));
    });
  });
}

