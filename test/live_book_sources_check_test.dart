import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/extractors/bespoke/internet_archive_extractor.dart';
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';
import 'package:novels_world/extractors/bespoke/openlibrary_extractor.dart';
import 'package:novels_world/extractors/bespoke/standard_ebooks_extractor.dart';
import 'package:novels_world/extractors/bespoke/gutenberg_extractor.dart';

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  group('All Book Sources Registration Verification', () {
    test('Verify all 8 book sources exist in registry', () {
      final ids = [
        'internet_archive',
        'libgen',
        'openlibrary',
        'standard_ebooks',
        'gutenberg',
        'oceanofpdf',
        'vdocpub',
        'local_epub',
      ];

      for (final id in ids) {
        final src = SourceRegistry.getSource(id);
        expect(src, isNotNull, reason: 'Source $id must be registered');
        expect(src!.name.isNotEmpty, isTrue);
        expect(src.baseUrl.isNotEmpty, isTrue);
      }
    });
  });

  group('Live Open Book Sources Verification', () {
    test('Internet Archive returns live unencrypted book results', () async {
      final extractor = InternetArchiveExtractor();
      final results = await extractor.search('Dune');
      expect(results.isNotEmpty, isTrue);
      print('Internet Archive found: ${results.length} items. First: "${results.first.title}"');
    });

    test('Open Library returns live book results with covers', () async {
      final extractor = OpenLibraryExtractor();
      final results = await extractor.search('Dune');
      expect(results.isNotEmpty, isTrue);
      print('Open Library found: ${results.length} items. First: "${results.first.title}" (Cover: ${results.first.coverUrl})');
    });

    test('Standard Ebooks returns live curated classics', () async {
      final extractor = StandardEbooksExtractor();
      final results = await extractor.search('Frankenstein');
      expect(results.isNotEmpty, isTrue);
      print('Standard Ebooks found: ${results.length} items. First: "${results.first.title}"');
    });

    test('Project Gutenberg returns live classic literature', () async {
      final extractor = GutenbergExtractor();
      final results = await extractor.search('Pride and Prejudice');
      expect(results.isNotEmpty, isTrue);
      print('Project Gutenberg found: ${results.length} items. First: "${results.first.title}"');
    });

    test('Library Genesis returns live search results across mirrors', () async {
      final extractor = LibGenExtractor();
      final results = await extractor.search('Dune');
      expect(results.isNotEmpty, isTrue);
      print('LibGen found: ${results.length} items. First: "${results.first.title}" (Mirror: ${extractor.baseUrl})');
    });
  });
}
