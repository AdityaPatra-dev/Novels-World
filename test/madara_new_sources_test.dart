import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/madara_extractor.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  final candidates = [
    {
      'id': 'riwyat',
      'name': 'Riwyat',
      'baseUrl': 'https://cenele.com',
      'lang': 'ar',
      'popularPath': '/cont/',
      'searchQuery': 'صاحب',
    },
    {
      'id': 'wondernovels',
      'name': 'Wonder Novels',
      'baseUrl': 'https://wondernovels.com',
      'lang': 'en',
      'popularPath': '/novels/',
      'searchQuery': 'villain',
    },
    {
      'id': 'novelshort',
      'name': 'Novel Short',
      'baseUrl': 'https://novel-short.com',
      'lang': 'en',
      'popularPath': '/novel/',
      'searchQuery': 'chance',
    },
    {
      'id': 'etudetranslations',
      'name': 'Etude Translations',
      'baseUrl': 'https://etudetranslations.com',
      'lang': 'en',
      'popularPath': '/novel/',
      'searchQuery': 'talent',
    },
    {
      'id': 'anslid',
      'name': 'Anslid',
      'baseUrl': 'https://anslid.com',
      'lang': 'es',
      'popularPath': '/novela/',
      'searchQuery': 'sucesor',
    },
    {
      'id': 'lullobox',
      'name': 'Lullobox',
      'baseUrl': 'https://lullobox.com',
      'lang': 'en',
      'popularPath': '/manga/',
      'searchQuery': 'boss',
    },
  ];

  for (final c in candidates) {
    test('Verify Madara source [${c['id']}] end-to-end live', () async {
      final extractor = MadaraExtractor(
        id: c['id']!,
        name: c['name']!,
        baseUrl: c['baseUrl']!,
        lang: c['lang']!,
        customPopularPath: c['popularPath'],
      );

      // 1. Popular
      print('\n--- TESTING ${c['name']} POPULAR ---');
      final popular = await extractor.getPopular(page: 1);
      print('${c['name']} Popular count: ${popular.length}');
      expect(popular.isNotEmpty, isTrue, reason: '${c['name']} popular list must not be empty');
      final first = popular.first;
      print('First: "${first.title}" -> ${first.sourceUrl}');
      expect(first.title.isNotEmpty, isTrue);

      // 2. Search
      print('--- TESTING ${c['name']} SEARCH ---');
      final searchResults = await extractor.search(c['searchQuery']!);
      print('${c['name']} Search count: ${searchResults.length}');
      expect(searchResults.isNotEmpty, isTrue, reason: '${c['name']} search must return results');
      final searchItem = searchResults.first;
      print('Search item: "${searchItem.title}" -> ${searchItem.sourceUrl}');

      // 3. Novel details
      print('--- TESTING ${c['name']} DETAILS ---');
      final details = await extractor.getNovelDetails(searchItem.sourceUrl);
      print('${c['name']} Details: "${details.title}", author: "${details.author}", genres: ${details.genres.length}, desc: ${details.description.length} chars');
      expect(details.title.isNotEmpty, isTrue);

      // 4. Chapter listing
      print('--- TESTING ${c['name']} CHAPTERS ---');
      final chapters = await extractor.getChapterList(searchItem.sourceUrl);
      print('${c['name']} Chapters count: ${chapters.length}');
      expect(chapters.isNotEmpty, isTrue, reason: '${c['name']} chapter list must not be empty');
      final firstCh = chapters.first;
      print('First chapter: "${firstCh.title}" -> ${firstCh.url}');
      expect(firstCh.url.startsWith('http'), isTrue);

      // 5. Chapter content
      print('--- TESTING ${c['name']} CONTENT ---');
      final content = await extractor.getChapterContent(firstCh.url);
      print('${c['name']} Paragraph count: ${content.paragraphs.length}');
      expect(content.paragraphs.isNotEmpty, isTrue, reason: '${c['name']} chapter content must have paragraphs');
      print('Sample: ${content.paragraphs.first.substring(0, content.paragraphs.first.length > 60 ? 60 : content.paragraphs.first.length)}...');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

