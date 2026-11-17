import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/gadyakosh_extractor.dart';

void main() {
  test('Live Gadya Kosh test for Kafan', () async {
    final extractor = GadyaKoshExtractor();
    final results = await extractor.search('कफ़न');
    print('Search Kafan count: ${results.length}');
    for (int i = 0; i < results.length && i < 5; i++) {
      print('  [$i] "${results[i].title}" by "${results[i].author}" | ${results[i].sourceUrl}');
    }

    if (results.isNotEmpty) {
      final novel = await extractor.getNovelDetails(results[0].sourceUrl);
      print('Novel 0: "${novel.title}" by "${novel.author}"');
      final chapters = await extractor.getChapterList(results[0].sourceUrl);
      print('Chapters count: ${chapters.length}');
      if (chapters.isNotEmpty) {
        print('  First chapter: "${chapters[0].title}" | ${chapters[0].url}');
        final content = await extractor.getChapterContent(chapters[0].url);
        print('  Content: title="${content.title}", paragraphs=${content.paragraphs.length}, textLen=${content.rawText.length}');
        for (int i = 0; i < content.paragraphs.length && i < 3; i++) {
          print('    P[$i]: ${content.paragraphs[i].substring(0, content.paragraphs[i].length > 80 ? 80 : content.paragraphs[i].length)}');
        }
      }
    }
  });
}
