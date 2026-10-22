import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/services/epub_service.dart';
import 'package:novels_world/extractors/bespoke/local_epub_extractor.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  group('Local EPUB Reader & Service Tests', () {
    late Directory tempDir;
    late File sampleEpub;
    final extractor = LocalEpubExtractor();

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('epub_test_');
      sampleEpub = File('test/fixtures/sample_classic.epub');
      expect(await sampleEpub.exists(), isTrue, reason: 'Test fixture must exist');
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Registry contains local_epub source', () {
      final source = SourceRegistry.getSource('local_epub');
      expect(source, isNotNull);
      expect(source!.name, 'Local EPUB');
    });

    test('EpubService imports and extracts EPUB metadata & spine', () async {
      final novel = await EpubService().importEpub(sampleEpub, targetDir: tempDir);

      expect(novel.id, startsWith('local_epub_'));
      expect(novel.sourceId, 'local_epub');
      expect(novel.title, 'A Study in Scarlet');
      expect(novel.author, 'Arthur Conan Doyle');
      expect(novel.description, contains('Sherlock Holmes'));
      expect(novel.inLibrary, isTrue);

      final bookDir = Directory(Uri.parse(novel.sourceUrl).toFilePath());
      expect(await bookDir.exists(), isTrue);

      final metaFile = File('${bookDir.path}/metadata.json');
      expect(await metaFile.exists(), isTrue);
    });

    test('LocalEpubExtractor loads details, chapters, and content', () async {
      final novel = await EpubService().importEpub(sampleEpub, targetDir: tempDir);

      // 1. Details
      final details = await extractor.getNovelDetails(novel.sourceUrl);
      expect(details.title, 'A Study in Scarlet');
      expect(details.author, 'Arthur Conan Doyle');

      // 2. Chapters
      final chapters = await extractor.getChapterList(novel.sourceUrl);
      expect(chapters.length, 2);
      expect(chapters[0].title, contains('Mr. Sherlock Holmes'));
      expect(chapters[1].title, contains('Science of Deduction'));

      // 3. Content Chapter 1
      final content1 = await extractor.getChapterContent(chapters[0].url);
      expect(content1.paragraphs.length, 2);
      expect(content1.paragraphs[0], contains('Doctor of Medicine'));
      expect(content1.paragraphs[1], contains('free as air'));

      // 4. Content Chapter 2
      final content2 = await extractor.getChapterContent(chapters[1].url);
      expect(content2.paragraphs.length, 2);
      expect(content2.paragraphs[0], contains('221B, Baker Street'));
    });
  });
}
