import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  group('Verified Fixes Audit Tests', () {
    test('Hindi Samay search returns works for Premchand with author and chapters', () async {
      final source = SourceRegistry.getSource('hindisamay')!;
      final search = await source.search('प्रेमचंद', page: 1);
      expect(search.isNotEmpty, isTrue);
      expect(search.first.title.isNotEmpty, isTrue);
      expect(search.first.author, contains('प्रेमचंद'));

      final details = await source.getNovelDetails(search.first.sourceUrl);
      expect(details.title, isNot(equals('Hindi Novel')));
      expect(details.title, isNot(equals('Untitled')));
      expect(details.author, contains('प्रेमचंद'));

      final chapters = await source.getChapterList(search.first.sourceUrl);
      expect(chapters.isNotEmpty, isTrue);
    });

    test('ePustakalay search returns books for Premchand and provides reading shell', () async {
      final source = SourceRegistry.getSource('epustakalay')!;
      final search = await source.search('प्रेमचंद', page: 1);
      expect(search.isNotEmpty, isTrue);
      expect(search.first.title.isNotEmpty, isTrue);

      final chaps = await source.getChapterList(search.first.sourceUrl);
      expect(chaps.length, equals(1));
      expect(chaps.first.title, contains('सम्पूर्ण पुस्तक'));

      final content = await source.getChapterContent(search.first.sourceUrl);
      expect(content.paragraphs.isNotEmpty, isTrue);
    });

    test('Kavita Kosh & Gadya Kosh chapter lists exclude language bar dialect links', () async {
      final kk = SourceRegistry.getSource('kavitakosh')!;
      final gk = SourceRegistry.getSource('gadyakosh')!;

      final kkPopular = await kk.getPopular(page: 1);
      expect(kkPopular.isNotEmpty, isTrue);
      final kkChaps = await kk.getChapterList(kkPopular.first.sourceUrl);
      expect(kkChaps.isNotEmpty, isTrue);
      // Ensure dialect links like 'अवधी', 'ब्रजभाषा' are not in the chapter list
      expect(kkChaps.any((c) => c.title == 'अवधी' || c.title == 'ब्रजभाषा'), isFalse);

      final gkPopular = await gk.getPopular(page: 1);
      expect(gkPopular.isNotEmpty, isTrue);
      final gkChaps = await gk.getChapterList(gkPopular.first.sourceUrl);
      expect(gkChaps.isNotEmpty, isTrue);
      expect(gkChaps.any((c) => c.title == 'अवधी' || c.title == 'भोजपुरी'), isFalse);
    });

    test('Full-book sources (OpenLibrary, Internet Archive, Standard Ebooks, LibGen) provide reading shells', () async {
      final ol = SourceRegistry.getSource('openlibrary')!;
      final ia = SourceRegistry.getSource('internet_archive')!;
      final se = SourceRegistry.getSource('standard_ebooks')!;
      final lg = SourceRegistry.getSource('libgen')!;

      final olChaps = await ol.getChapterList('https://openlibrary.org/works/OL45804W/Fantastic_Mr_Fox');
      expect(olChaps.length, equals(1));
      expect(olChaps.first.title, contains('Complete Book'));

      final iaChaps = await ia.getChapterList('https://archive.org/details/alicesadventures00carruoft');
      expect(iaChaps.length, equals(1));

      final seChaps = await se.getChapterList('https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice');
      expect(seChaps.length, equals(1));

      final lgChaps = await lg.getChapterList('http://libgen.is/book/index.php?md5=D814BFF67A42');
      expect(lgChaps.length, equals(1));
    });

    test('Strange Horizons cleans author metadata without issue/wordcount clutter', () async {
      final sh = SourceRegistry.getSource('strangehorizons')!;
      final popular = await sh.getPopular(page: 1);
      expect(popular.isNotEmpty, isTrue);

      final details = await sh.getNovelDetails(popular.first.sourceUrl);
      expect(details.author, isNot(contains('Issue:')));
      expect(details.author, isNot(contains('words')));
      expect(details.author, isNot(equals('Unknown Author')));

      final chapters = await sh.getChapterList(popular.first.sourceUrl);
      expect(chapters.isNotEmpty, isTrue);

      final content = await sh.getChapterContent(chapters.first.url);
      expect(content.paragraphs.isNotEmpty, isTrue);
    });
  });
}
