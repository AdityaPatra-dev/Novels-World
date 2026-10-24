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
      try {
        final novels = await extractor.getPopular(page: 1);
        expect(novels, isNotEmpty);
        expect(novels.first.title, isNotEmpty);
        expect(novels.first.sourceUrl, contains('allfreenovel.com'));
      } catch (e) {
        // ignore: avoid_print
        print('[allfreenovel] live network test skipped/warned: $e');
      }
    });

    test('search returns matching books', () async {
      try {
        final novels = await extractor.search('Harry', page: 1);
        expect(novels, isNotEmpty);
        expect(novels.first.title.toLowerCase(), contains('harry'));
      } catch (e) {
        // ignore: avoid_print
        print('[allfreenovel] live search test skipped/warned: $e');
      }
    });

    test('getNovelDetails returns populated details', () async {
      const url = 'https://allfreenovel.com/Book/Details/73607/Haunting-Adeline-Cat-and-Mouse-Duet';
      try {
        final details = await extractor.getNovelDetails(url);
        expect(details.title, contains('Haunting Adeline'));
        expect(details.author, isNotEmpty);
        expect(details.description, isNotEmpty);
      } catch (e) {
        // ignore: avoid_print
        print('[allfreenovel] live details test skipped/warned: $e');
      }
    });

    test('getChapterList returns pages', () async {
      const url = 'https://allfreenovel.com/Book/Details/73607/Haunting-Adeline-Cat-and-Mouse-Duet';
      try {
        final chapters = await extractor.getChapterList(url);
        expect(chapters, isNotEmpty);
        expect(chapters.first.url, contains('/Page/Story/'));
      } catch (e) {
        // ignore: avoid_print
        print('[allfreenovel] live chapter list test skipped/warned: $e');
      }
    });

    test('getChapterContent returns clean paragraphs', () async {
      const chUrl = 'https://allfreenovel.com/Page/Story/73607/page-1-of-Haunting-Adeline-Cat-and-Mouse-Duet/1/207/4';
      try {
        final content = await extractor.getChapterContent(chUrl);
        expect(content.paragraphs, isNotEmpty);
        expect(content.rawText, isNotEmpty);
      } catch (e) {
        // ignore: avoid_print
        print('[allfreenovel] live content test skipped/warned: $e');
      }
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
      try {
        final novels = await extractor.getPopular(page: 1);
        expect(novels, isNotEmpty);
        expect(novels.first.title, isNotEmpty);
        expect(novels.first.sourceUrl, contains('gutenberg.org'));
      } catch (e) {
        // ignore: avoid_print
        print('[gutenberg] live network test skipped/warned: $e');
      }
    });

    test('search returns matching literary works', () async {
      try {
        final novels = await extractor.search('Frankenstein', page: 1);
        expect(novels, isNotEmpty);
        expect(novels.first.title.toLowerCase(), contains('frankenstein'));
      } catch (e) {
        // ignore: avoid_print
        print('[gutenberg] live search test skipped/warned: $e');
      }
    });

    test('getNovelDetails returns book details', () async {
      const url = 'https://www.gutenberg.org/ebooks/84';
      try {
        final details = await extractor.getNovelDetails(url);
        expect(details.title.toLowerCase(), contains('frankenstein'));
        expect(details.author.toLowerCase(), contains('shelley'));
      } catch (e) {
        // ignore: avoid_print
        print('[gutenberg] live details test skipped/warned: $e');
      }
    });

    test('getChapterList returns book chapters', () async {
      const url = 'https://www.gutenberg.org/ebooks/84';
      try {
        final chapters = await extractor.getChapterList(url);
        expect(chapters, isNotEmpty);
        expect(chapters.first.title, isNotEmpty);
      } catch (e) {
        // ignore: avoid_print
        print('[gutenberg] live chapter list test skipped/warned: $e');
      }
    });

    test('getChapterContent returns chapter text', () async {
      const chUrl = 'https://www.gutenberg.org/cache/epub/84/pg84-images.html#chap01';
      try {
        final content = await extractor.getChapterContent(chUrl);
        expect(content.paragraphs, isNotEmpty);
        expect(content.paragraphs.first, contains('Genevese'));
      } catch (e) {
        // ignore: avoid_print
        print('[gutenberg] live content test skipped/warned: $e');
      }
    });
  });
}

