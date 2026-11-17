import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/hindisamay_extractor.dart';

void main() {
  test('Live Hindi Samay test for Popular and Novel details', () async {
    final extractor = HindiSamayExtractor();
    final popular = await extractor.getPopular(page: 1);
    print('Popular count: ${popular.length}');
    for (int i = 0; i < popular.length && i < 8; i++) {
      print('  [$i] Title: "${popular[i].title}" by "${popular[i].author}" | URL: ${popular[i].sourceUrl}');
    }

    if (popular.isNotEmpty) {
      final novel = await extractor.getNovelDetails(popular[0].sourceUrl);
      print('Detailed novel 0: "${novel.title}" by "${novel.author}"');
      final chapters = await extractor.getChapterList(popular[0].sourceUrl);
      print('Chapters count for novel 0: ${chapters.length}');
      if (chapters.isNotEmpty) {
        print('  First chapter: "${chapters[0].title}" | URL: ${chapters[0].url}');
        final content = await extractor.getChapterContent(chapters[0].url);
        print('  Content: title="${content.title}", paragraphs=${content.paragraphs.length}, textLen=${content.rawText.length}');
      }
    }
  });

  test('Live Hindi Samay test for Search Godan', () async {
    final extractor = HindiSamayExtractor();
    final results = await extractor.search('गोदान');
    print('Search Godan count: ${results.length}');
    for (int i = 0; i < results.length && i < 5; i++) {
      print('  [$i] "${results[i].title}" by "${results[i].author}" | ${results[i].sourceUrl}');
    }
  });
}
