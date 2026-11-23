import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/novelfull_extractor.dart';

void main() {
  test('test NovelFull getChapterList returns all 1,600+ chapters', () async {
    final extractor = NovelFullExtractor(
      id: 'novelfull',
      name: 'NovelFull',
      baseUrl: 'https://novelfull.com',
    );
    int batchCount = 0;
    final chapters = await extractor.getChapterList(
      'https://novelfull.com/battle-through-the-heavens.html',
      onBatchLoaded: (batch) {
        batchCount = batch.length;
        print('Batch loaded: $batchCount chapters');
      },
    );
    print('Final NovelFull total chapters: ${chapters.length}');
    expect(chapters.length, greaterThanOrEqualTo(1648));
    expect(chapters.first.title.toLowerCase().contains('chapter 1'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('test FreeWebNovel getChapterList returns all 1,600+ chapters', () async {
    final extractor = NovelFullExtractor(
      id: 'freewebnovel',
      name: 'FreeWebNovel',
      baseUrl: 'https://freewebnovel.com',
    );
    int batchCount = 0;
    final chapters = await extractor.getChapterList(
      'https://freewebnovel.com/novel/battle-through-the-heavens-novel',
      onBatchLoaded: (batch) {
        batchCount = batch.length;
        print('Batch loaded: $batchCount chapters');
      },
    );
    print('Final FreeWebNovel total chapters: ${chapters.length}');
    expect(chapters.length, greaterThanOrEqualTo(1648));
    expect(chapters.first.title.toLowerCase().contains('chapter 1'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
