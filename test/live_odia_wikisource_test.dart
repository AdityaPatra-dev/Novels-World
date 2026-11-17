import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/or_wikisource_extractor.dart';

void main() {
  test('Search in Odia Wikisource', () async {
    final extractor = OdiaWikisourceExtractor();
    final results = await extractor.search('ଛମାଣ ଆଠଗୁଣ୍ଠ');
    print('Search results count: ${results.length}');
    for (int i = 0; i < results.length && i < 10; i++) {
      print('  [$i] Title: "${results[i].title}" | ID: ${results[i].id} | URL: ${results[i].sourceUrl}');
    }
  });

  test('Search for Darabar in Odia Wikisource', () async {
    final extractor = OdiaWikisourceExtractor();
    final results = await extractor.search('ଦରବାର');
    print('Search results for Darabar count: ${results.length}');
    for (int i = 0; i < results.length && i < 10; i++) {
      print('  [$i] Title: "${results[i].title}" | ID: ${results[i].id} | URL: ${results[i].sourceUrl}');
    }
    if (results.isNotEmpty) {
      final chapters = await extractor.getChapterList(results[0].sourceUrl);
      print('First result chapters: ${chapters.length}');
      if (chapters.isNotEmpty) {
        final content = await extractor.getChapterContent(chapters[0].url);
        print('Content text length: ${content.rawText.length}, paragraphs: ${content.paragraphs.length}');
      }
    }
  });
}
