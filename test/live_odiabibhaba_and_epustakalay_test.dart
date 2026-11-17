import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/odiabibhaba_extractor.dart';
import 'package:novels_world/extractors/bespoke/epustakalay_extractor.dart';

void main() {
  group('Live Odia Bibhaba & ePustakalay Verification', () {
    test('Odia Bibhaba fetches popular books and details', () async {
      final extractor = OdiaBibhabaExtractor();
      final books = await extractor.getPopular(page: 1);
      expect(books.isNotEmpty, true, reason: 'Odia Bibhaba should return popular books');
      print('Odia Bibhaba returned ${books.length} books');

      final sample = books.first;
      print('First book: ${sample.title} by ${sample.author}');
      expect(sample.title.isNotEmpty, true);
      expect(sample.isFullBook, true);
      expect(sample.bookDownloadUrl?.isNotEmpty, true);

      final details = await extractor.getNovelDetails(sample.sourceUrl);
      print('Details: title="${details.title}", author="${details.author}", desc="${details.description}"');
      expect(details.title.isNotEmpty, true);
      expect(details.author.isNotEmpty, true);

      final chapters = await extractor.getChapterList(sample.sourceUrl);
      expect(chapters.isNotEmpty, true);
      print('Chapters count: ${chapters.length}, first: ${chapters.first.title}');

      final content = await extractor.getChapterContent(chapters.first.url);
      expect(content.paragraphs.isNotEmpty, true);
      expect(content.paragraphs.length >= 4, true);
      print('Odia chapter paragraphs: ${content.paragraphs.length}');
      print('First paragraph: ${content.paragraphs.first}');
    });

    test('ePustakalay fetches popular books and details', () async {
      final extractor = EPustakalayExtractor();
      final books = await extractor.getPopular(page: 1);
      expect(books.isNotEmpty, true, reason: 'ePustakalay should return books');
      print('ePustakalay returned ${books.length} books');

      final sample = books.firstWhere(
        (b) => b.title.contains('गुनाहो का देवता') || b.sourceUrl.contains('gunahon-ka-devata'),
        orElse: () => books.first,
      );
      print('Sample book: ${sample.title} by ${sample.author}, url=${sample.sourceUrl}');
      expect(sample.title.isNotEmpty, true);

      final details = await extractor.getNovelDetails(sample.sourceUrl);
      print('ePustakalay details: title="${details.title}", author="${details.author}", pdfUrl="${details.bookDownloadUrl}"');
      expect(details.title.isNotEmpty, true);
      expect(details.author.isNotEmpty, true);

      final chapters = await extractor.getChapterList(sample.sourceUrl);
      expect(chapters.isNotEmpty, true);

      final content = await extractor.getChapterContent(chapters.first.url);
      expect(content.paragraphs.isNotEmpty, true);
      expect(content.paragraphs.length >= 4, true);
      print('ePustakalay chapter paragraphs: ${content.paragraphs.length}');
      print('First paragraph: ${content.paragraphs.first}');
    });
  });
}
