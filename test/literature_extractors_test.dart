import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/allfreenovel_extractor.dart';
import 'package:novels_world/extractors/bespoke/gutenberg_extractor.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  group('AllFreeNovel Extractor Live Tests', () {
    final extractor = AllFreeNovelExtractor();

    test('Registry contains allfreenovel', () {
      final source = SourceRegistry.getSource('allfreenovel');
      expect(source, isNotNull);
      expect(source!.name, 'AllFreeNovel');
    });

    test('getPopular returns published bookstore novels', () async {
      final novels = await extractor.getPopular(page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title, isNotEmpty);
      expect(novels.first.sourceUrl, contains('allfreenovel.com'));
    });

    test('search returns matching books', () async {
      final novels = await extractor.search('Harry', page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title.toLowerCase(), contains('harry'));
    });

    test('getNovelDetails returns populated details', () async {
      const url = 'https://allfreenovel.com/Book/Details/73607/Haunting-Adeline-Cat-and-Mouse-Duet';
      final details = await extractor.getNovelDetails(url);
      expect(details.title, contains('Haunting Adeline'));
      expect(details.author, isNotEmpty);
      expect(details.description, isNotEmpty);
    });

    test('getChapterList returns pages', () async {
      const url = 'https://allfreenovel.com/Book/Details/73607/Haunting-Adeline-Cat-and-Mouse-Duet';
      final chapters = await extractor.getChapterList(url);
      expect(chapters, isNotEmpty);
      expect(chapters.first.url, contains('/Page/Story/'));
    });

    test('getChapterContent returns clean paragraphs', () async {
      const chUrl = 'https://allfreenovel.com/Page/Story/73607/page-1-of-Haunting-Adeline-Cat-and-Mouse-Duet/1/207/4';
      final content = await extractor.getChapterContent(chUrl);
      expect(content.paragraphs, isNotEmpty);
      expect(content.rawText, isNotEmpty);
    });
  });

  group('Project Gutenberg Extractor Live Tests', () {
    final extractor = GutenbergExtractor();

    test('Registry contains gutenberg', () {
      final source = SourceRegistry.getSource('gutenberg');
      expect(source, isNotNull);
      expect(source!.name, 'Project Gutenberg');
    });

    test('getPopular returns literary classics', () async {
      final novels = await extractor.getPopular(page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title, isNotEmpty);
      expect(novels.first.sourceUrl, contains('gutenberg.org'));
    });

    test('search returns matching literary works', () async {
      final novels = await extractor.search('Frankenstein', page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title.toLowerCase(), contains('frankenstein'));
    });

    test('getNovelDetails returns book details', () async {
      const url = 'https://www.gutenberg.org/ebooks/84';
      final details = await extractor.getNovelDetails(url);
      expect(details.title.toLowerCase(), contains('frankenstein'));
      expect(details.author.toLowerCase(), contains('shelley'));
    });

    test('getChapterList returns book chapters', () async {
      const url = 'https://www.gutenberg.org/ebooks/84';
      final chapters = await extractor.getChapterList(url);
      expect(chapters, isNotEmpty);
      expect(chapters.first.title, isNotEmpty);
    });

    test('getChapterContent returns chapter text', () async {
      const chUrl = 'https://www.gutenberg.org/cache/epub/84/pg84-images.html#chap01';
      final content = await extractor.getChapterContent(chUrl);
      expect(content.paragraphs, isNotEmpty);
      expect(content.paragraphs.first, contains('Genevese'));
    });
  });
}
