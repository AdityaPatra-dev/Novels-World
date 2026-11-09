import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/services/epub_service.dart';
import 'package:novels_world/extractors/bespoke/local_epub_extractor.dart';

void main() {
  test('Project Gutenberg EPUB import, chapter extraction, and reading', () async {
    final epubFile = File('/tmp/pg1513.epub');
    if (!await epubFile.exists()) {
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('pg_test_');
    try {
      final epubService = EpubService();
      final novel = await epubService.importEpub(epubFile, targetDir: tempDir);

      expect(novel.title, contains('Romeo and Juliet'));
      expect(novel.author, contains('Shakespeare'));

      final chapters = await LocalEpubExtractor().getChapterList(novel.sourceUrl);
      expect(chapters.isNotEmpty, isTrue);

      // Verify that getFirstNarrativeChapter skips wrap0000.html
      final firstNarrative = EpubService.getFirstNarrativeChapter(chapters);
      expect(firstNarrative.url.contains('wrap0000'), isFalse);

      // Test loading the first chapter content (wrap0000.html) to make sure it handles cover safely
      final coverChapter = chapters.first;
      final coverContent = await epubService.loadChapterContent(coverChapter.url);
      expect(coverContent.paragraphs.isNotEmpty, isTrue);
      // It should contain an [IMAGE: token or text without throwing
      expect(coverContent.paragraphs.first.startsWith('[IMAGE:') || coverContent.paragraphs.first.isNotEmpty, isTrue);

      // Test loading an actual narrative chapter (e.g. Act 1)
      final act1Chapter = chapters.firstWhere((c) => c.title.contains('ACT I') || c.url.contains('1513-h-3'));
      final act1Content = await epubService.loadChapterContent(act1Chapter.url);
      expect(act1Content.paragraphs.isNotEmpty, isTrue);
      expect(act1Content.rawText, contains('SAMPSON'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
