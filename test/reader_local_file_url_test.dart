import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/services/epub_service.dart';
import 'package:novels_world/extractors/bespoke/gutenberg_extractor.dart';
import 'package:novels_world/extractors/bespoke/openlibrary_extractor.dart';
import 'package:novels_world/extractors/bespoke/standard_ebooks_extractor.dart';
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';

void main() {
  test('Local file:// chapter URLs load via bespoke extractors without URI host error', () async {
    final tempDir = await Directory.systemTemp.createTemp('ch_test_');
    try {
      final sampleChapterFile = File('${tempDir.path}/test_chapter.html');
      await sampleChapterFile.writeAsString('''
<!DOCTYPE html>
<html>
<head><title>Chapter 1: The Awakening</title></head>
<body>
<h1>Chapter 1: The Awakening</h1>
<p>The dawn broke slowly over the silent forest, casting golden rays through the ancient trees.</p>
<p>He stood at the edge of the clearing, listening to the whispered rumors of the wind.</p>
</body>
</html>
''');

      final fileUrl = Uri.file(sampleChapterFile.path).toString();
      expect(fileUrl.startsWith('file://'), isTrue);

      // 1. Direct EpubService test
      final epubContent = await EpubService().loadChapterContent(fileUrl);
      expect(epubContent.title, contains('Awakening'));
      expect(epubContent.paragraphs.length, equals(2));
      expect(epubContent.paragraphs.first, contains('dawn broke'));

      // 2. GutenbergExtractor delegation test
      final gutenbergContent = await GutenbergExtractor().getChapterContent(fileUrl);
      expect(gutenbergContent.paragraphs.length, equals(2));

      // 3. OpenLibraryExtractor delegation test
      final olContent = await OpenLibraryExtractor().getChapterContent(fileUrl);
      expect(olContent.paragraphs.length, equals(2));

      // 4. StandardEbooksExtractor delegation test
      final seContent = await StandardEbooksExtractor().getChapterContent(fileUrl);
      expect(seContent.paragraphs.length, equals(2));

      // 5. LibGenExtractor delegation test
      final lgContent = await LibGenExtractor().getChapterContent(fileUrl);
      expect(lgContent.paragraphs.length, equals(2));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
