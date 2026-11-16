import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/extractors/bespoke/gadyakosh_extractor.dart';
import 'package:novels_world/extractors/bespoke/or_wikisource_extractor.dart';
import 'package:novels_world/extractors/bespoke/hindisamay_extractor.dart';
import 'package:novels_world/extractors/bespoke/epustakalay_extractor.dart';
import 'package:novels_world/extractors/bespoke/odiabibhaba_extractor.dart';
import 'package:novels_world/extractors/bespoke/kavitakosh_extractor.dart';

void main() {
  group('Indic Sources Registration & Metadata Tests', () {
    test('Gadya Kosh extractor is registered with proper metadata', () {
      final source = SourceRegistry.getSource('gadyakosh');
      expect(source, isNotNull);
      expect(source, isA<GadyaKoshExtractor>());
      expect(source!.name, contains('गद्य कोश'));
      expect(source.lang, 'hi');
      expect(source.baseUrl, contains('gadyakosh.org'));
      expect(source.estimatedNovelCount, 15000);
    });

    test('Odia Wikisource extractor is registered with proper metadata', () {
      final source = SourceRegistry.getSource('or_wikisource');
      expect(source, isNotNull);
      expect(source, isA<OdiaWikisourceExtractor>());
      expect(source!.name, contains('ଓଡ଼ିଆ ଉଇକିପାଠାଗାର'));
      expect(source.lang, 'or');
      expect(source.baseUrl, contains('or.wikisource.org'));
      expect(source.estimatedNovelCount, 5000);
    });

    test('Hindi Samay extractor is registered with proper metadata', () {
      final source = SourceRegistry.getSource('hindisamay');
      expect(source, isNotNull);
      expect(source, isA<HindiSamayExtractor>());
      expect(source!.name, contains('हिंदी समय'));
      expect(source.lang, 'hi');
      expect(source.baseUrl, contains('hindisamay.com'));
      expect(source.estimatedNovelCount, 10000);
    });

    test('ePustakalay extractor is registered with proper metadata', () {
      final source = SourceRegistry.getSource('epustakalay');
      expect(source, isNotNull);
      expect(source, isA<EPustakalayExtractor>());
      expect(source!.name, contains('ई-पुस्तकालय'));
      expect(source.lang, 'hi');
      expect(source.baseUrl, contains('epustakalay.com'));
      expect(source.estimatedNovelCount, 40000);
    });

    test('Odia Bibhaba extractor is registered with proper metadata', () {
      final source = SourceRegistry.getSource('odiabibhaba');
      expect(source, isNotNull);
      expect(source, isA<OdiaBibhabaExtractor>());
      expect(source!.name, contains('ଓଡ଼ିଆ ବିଭବ'));
      expect(source.lang, 'or');
      expect(source.baseUrl, contains('odiabibhaba.in'));
      expect(source.estimatedNovelCount, 10000);
    });

    test('Kavita Kosh extractor is registered with proper metadata', () {
      final source = SourceRegistry.getSource('kavitakosh');
      expect(source, isNotNull);
      expect(source, isA<KavitaKoshExtractor>());
      expect(source!.name, contains('कविता कोश'));
      expect(source.lang, 'hi');
      expect(source.baseUrl, contains('kavitakosh.org'));
      expect(source.estimatedNovelCount, 25000);
    });

    test('All sources sorting preserves English on top and groups Hindi and Odia correctly', () {
      final all = SourceRegistry.getAllSources();
      expect(all, isNotEmpty);

      // Verify English sources remain at the top
      expect(all.first.lang, 'en');

      // Verify Hindi sources are present and sorted by estimated count
      final hindiSources = all.where((s) => s.lang == 'hi').toList();
      expect(hindiSources.length, greaterThanOrEqualTo(4));
      // First hindi source should have the highest catalog count
      expect(hindiSources.first.estimatedNovelCount, greaterThanOrEqualTo(hindiSources.last.estimatedNovelCount));

      // Verify Odia sources are present and sorted by estimated count
      final odiaSources = all.where((s) => s.lang == 'or').toList();
      expect(odiaSources.length, greaterThanOrEqualTo(2));
      expect(odiaSources.first.estimatedNovelCount, greaterThanOrEqualTo(odiaSources.last.estimatedNovelCount));
    });
  });

  group('Extractor Unit Parsing Tests', () {
    test('GadyaKoshExtractor parseSearchResults parses titles and authors correctly', () {
      final extractor = GadyaKoshExtractor();
      final mockData = [
        {
          'title': 'गोदान / प्रेमचंद',
          'snippet': 'प्रसिद्ध उपन्यास गोदान का मुख्य पात्र होरी है।'
        },
        {
          'title': 'तगादा / प्रेमचंद',
          'snippet': 'सेठ चेतराम ने स्नान किया और सोटा लेकर तगादे पर चले।'
        },
        {
          'title': 'श्रेणी:उपन्यास',
          'snippet': 'श्रेणी सूची'
        }
      ];

      final novels = extractor.parseSearchResults(mockData);
      expect(novels.length, 2);
      expect(novels[0].title, 'गोदान');
      expect(novels[0].author, 'प्रेमचंद');
      expect(novels[0].description, contains('होरी'));
      expect(novels[1].title, 'तगादा');
      expect(novels[1].author, 'प्रेमचंद');
    });

    test('OdiaWikisourceExtractor parseSearchResults parses Odia classics correctly', () {
      final extractor = OdiaWikisourceExtractor();
      final mockData = [
        {
          'title': 'ଛମାଣ ଆଠଗୁଣ୍ଠ',
          'snippet': 'ଫକୀର ମୋହନ ସେନାପତିଙ୍କ ରଚିତ ଉପନ୍ୟାସ'
        },
        {
          'title': 'ଲେଖକ:ରାଧାନାଥ ରାୟ',
          'snippet': 'କବିବର ରାଧାନାଥ ରାୟଙ୍କ ରଚନାବଳୀ'
        },
        {
          'title': 'ଶ୍ରେଣୀ:ଓଡ଼ିଆ ପୁସ୍ତକ',
          'snippet': 'ଉଇକିପାଠାଗାର ଶ୍ରେଣୀ'
        }
      ];

      final novels = extractor.parseSearchResults(mockData);
      expect(novels.length, 2);
      expect(novels[0].title, 'ଛମାଣ ଆଠଗୁଣ୍ଠ');
      expect(novels[0].sourceId, 'or_wikisource');
      expect(novels[1].title, 'ରାଧାନାଥ ରାୟ');
      expect(novels[1].author, 'ରାଧାନାଥ ରାୟ');
    });

    test('KavitaKoshExtractor parseSearchResults parses epic poems correctly', () {
      final extractor = KavitaKoshExtractor();
      final mockData = [
        {
          'title': 'रश्मिरथी / रामधारी सिंह "दिनकर"',
          'snippet': 'रामधारी सिंह दिनकर का सुप्रसिद्ध खंडकाव्य'
        },
        {
          'title': 'मधुशाला / हरिवंशराय बच्चन',
          'snippet': 'मदिरालय जाने को घर से चलता है पीनेवला'
        }
      ];

      final novels = extractor.parseSearchResults(mockData);
      expect(novels.length, 2);
      expect(novels[0].title, 'रश्मिरथी');
      expect(novels[0].author, 'रामधारी सिंह "दिनकर"');
      expect(novels[1].title, 'मधुशाला');
      expect(novels[1].author, 'हरिवंशराय बच्चन');
    });
  });

  group('Live Network Integration Tests for Indic Sources', () {
    test('Gadya Kosh live search returns authentic Premchand works', () async {
      final extractor = GadyaKoshExtractor();
      final results = await extractor.search('प्रेमचंद');
      expect(results, isNotEmpty);
      expect(results.first.title, isNotEmpty);
      expect(results.first.sourceUrl, contains('gadyakosh.org'));
    });

    test('Odia Wikisource live search returns Fakir Mohan Senapati works', () async {
      final extractor = OdiaWikisourceExtractor();
      final results = await extractor.search('ଫକୀର ମୋହନ');
      expect(results, isNotEmpty);
      expect(results.first.title, isNotEmpty);
      expect(results.first.sourceUrl, contains('or.wikisource.org'));
    });

    test('Odia Bibhaba live API returns books catalog', () async {
      final extractor = OdiaBibhabaExtractor();
      final results = await extractor.getPopular(page: 1);
      expect(results, isNotEmpty);
      expect(results.first.title, isNotEmpty);
      expect(results.first.isFullBook, isTrue);
      expect(results.first.bookFormat, 'pdf');
      expect(results.first.bookDownloadUrl, anyOf(contains('.pdf'), contains('/stream')));
    });

    test('ePustakalay live catalog returns Hindi books with download URLs', () async {
      final extractor = EPustakalayExtractor();
      final results = await extractor.getPopular(page: 1);
      expect(results, isNotEmpty);
      expect(results.first.title, isNotEmpty);
      expect(results.first.isFullBook, isTrue);
      expect(results.first.bookFormat, 'pdf');
    });

    test('Hindi Samay live catalog returns Hindi classics', () async {
      final extractor = HindiSamayExtractor();
      final results = await extractor.getPopular(page: 1);
      expect(results, isNotEmpty);
      expect(results.first.title, isNotEmpty);
      expect(results.first.sourceUrl, contains('hindisamay.com'));
    });

    test('Kavita Kosh live search returns Dinkar and Rashmirathi poetry', () async {
      final extractor = KavitaKoshExtractor();
      final results = await extractor.search('रश्मिरथी');
      expect(results, isNotEmpty);
      expect(results.first.title, isNotEmpty);
      expect(results.first.sourceUrl, contains('kavitakosh.org'));
    });
  });
}
