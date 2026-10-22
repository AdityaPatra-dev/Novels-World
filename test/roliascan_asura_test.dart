import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/roliascan_extractor.dart';
import 'package:novels_world/extractors/bespoke/asurascans_extractor.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  group('RoliaScan Extractor Live Tests', () {
    final extractor = RoliaScanExtractor();

    test('Registry contains roliascan', () {
      final source = SourceRegistry.getSource('roliascan');
      expect(source, isNotNull);
      expect(source!.name, 'RoliaScan');
    });

    test('getPopular returns novel list', () async {
      final novels = await extractor.getPopular(page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title, isNotEmpty);
      expect(novels.first.sourceUrl, contains('roliascan.com'));
    });

    test('search returns matching novels', () async {
      final novels = await extractor.search('Dual', page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title.toLowerCase(), contains('dual'));
    });

    test('getNovelDetails returns populated details', () async {
      const url = 'https://roliascan.com/manga/regnum-aetern-dual-rebirth-novel/';
      final details = await extractor.getNovelDetails(url);
      expect(details.title, isNotEmpty);
      expect(details.author, isNotEmpty);
    });

    test('getChapterList returns chapters', () async {
      const url = 'https://roliascan.com/manga/regnum-aetern-dual-rebirth-novel/';
      final chapters = await extractor.getChapterList(url);
      expect(chapters, isNotEmpty);
      expect(chapters.first.url, contains('roliascan.com/read/'));
    });

    test('getChapterContent returns paragraphs', () async {
      const chUrl = 'https://roliascan.com/read/regnum-aetern-dual-rebirth-novel/ch1-288742/';
      final content = await extractor.getChapterContent(chUrl);
      expect(content.paragraphs, isNotEmpty);
      expect(content.paragraphs.first, contains('Daniel'));
      expect(content.rawText, isNotEmpty);
    });
  });

  group('Asura Scans Extractor Live Tests', () {
    final extractor = AsuraScansExtractor();

    test('Registry contains asurascans', () {
      final source = SourceRegistry.getSource('asurascans');
      expect(source, isNotNull);
      expect(source!.name, 'Asura Scans');
    });

    test('getPopular returns novel list', () async {
      final novels = await extractor.getPopular(page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title, isNotEmpty);
      expect(novels.first.sourceUrl, contains('asurascans.com/novels/'));
    });

    test('search returns matching novels', () async {
      final novels = await extractor.search('Hunter', page: 1);
      expect(novels, isNotEmpty);
      expect(novels.first.title, contains('Hunter'));
    });

    test('getNovelDetails returns populated details', () async {
      const url = 'https://asurascans.com/novels/sss-class-suicide-hunter';
      final details = await extractor.getNovelDetails(url);
      expect(details.title, 'SSS-Class Suicide Hunter');
      expect(details.author, isNotEmpty);
      expect(details.genres, isNotEmpty);
    });

    test('getChapterList returns chapters', () async {
      const url = 'https://asurascans.com/novels/sss-class-suicide-hunter';
      final chapters = await extractor.getChapterList(url);
      expect(chapters, isNotEmpty);
      expect(chapters.first.chapterNumber, 1.0);
    });

    test('getChapterContent returns paragraphs', () async {
      const chUrl = 'https://asurascans.com/novels/sss-class-suicide-hunter/chapter/1';
      final content = await extractor.getChapterContent(chUrl);
      expect(content.paragraphs, isNotEmpty);
      expect(content.paragraphs.first, contains('breaking news'));
      expect(content.rawText, isNotEmpty);
    });
  });
}
