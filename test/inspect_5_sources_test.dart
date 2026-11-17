import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:novels_world/extractors/bespoke/standard_ebooks_extractor.dart';
import 'package:novels_world/extractors/bespoke/epustakalay_extractor.dart';
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';
import 'package:novels_world/extractors/bespoke/openlibrary_extractor.dart';
import 'package:novels_world/extractors/bespoke/internet_archive_extractor.dart';
import 'package:novels_world/extractors/novel_source.dart';

void main() {
  final client = http.Client();

  final sources = <NovelSource>[
    StandardEbooksExtractor(),
    EPustakalayExtractor(),
    LibGenExtractor(),
    OpenLibraryExtractor(),
    InternetArchiveExtractor(),
  ];

  for (final source in sources) {
    test('Inspect source [${source.id}] ${source.name}', () async {
      print('\n========================================');
      print('TESTING SOURCE: [${source.id}] ${source.name}');
      print('========================================');

      // 1. Popular
      final popular = await source.getPopular(page: 1);
      print('Popular count: ${popular.length}');
      expect(popular.isNotEmpty, isTrue, reason: '${source.id} should return popular books');

      final sample = popular.first;
      print('Sample Title: ${sample.title}');
      print('Sample Author: ${sample.author}');
      print('Sample Cover: ${sample.coverUrl}');
      print('Sample SourceUrl: ${sample.sourceUrl}');
      print('Sample isFullBook: ${sample.isFullBook}');
      print('Sample bookFormat: ${sample.bookFormat}');
      print('Sample bookDownloadUrl: ${sample.bookDownloadUrl}');

      // 2. Cover image HTTP check
      if (sample.coverUrl.isNotEmpty) {
        try {
          final imgRes = await client.head(Uri.parse(sample.coverUrl)).timeout(const Duration(seconds: 5));
          print('Cover Image HEAD status: ${imgRes.statusCode}');
        } catch (e) {
          print('Cover Image check error: $e');
        }
      } else {
        print('WARNING: Cover URL is empty for sample!');
      }

      // 3. Novel details
      final details = await source.getNovelDetails(sample.sourceUrl);
      print('Details Title: ${details.title}');
      print('Details Author: ${details.author}');
      print('Details Desc length: ${details.description.length}');
      print('Details DownloadUrl: ${details.bookDownloadUrl}');

      // 4. Chapter list
      final chapters = await source.getChapterList(sample.sourceUrl);
      print('Chapter count: ${chapters.length}');
      if (chapters.isNotEmpty) {
        print('First Chapter Title: ${chapters.first.title}');
        print('First Chapter Url: ${chapters.first.url}');
        final content = await source.getChapterContent(chapters.first.url);
        print('Chapter content paragraphs: ${content.paragraphs.length}');
        print('Chapter content length: ${content.rawText.length}');
        if (content.paragraphs.isNotEmpty) {
          print('First paragraph: "${content.paragraphs.first}"');
        }
      }

      // 5. Check if bookDownloadUrl is reachable
      final dlUrl = details.bookDownloadUrl ?? sample.bookDownloadUrl;
      if (dlUrl != null && dlUrl.isNotEmpty) {
        try {
          final request = http.Request('GET', Uri.parse(dlUrl));
          request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
          if (sample.sourceUrl.isNotEmpty) {
            request.headers['Referer'] = sample.sourceUrl;
          }
          final streamed = await client.send(request).timeout(const Duration(seconds: 10));
          print('Download URL check status: ${streamed.statusCode} (content-length: ${streamed.contentLength})');
        } catch (e) {
          print('Download URL check error: $e');
        }
      } else {
        print('WARNING: No download URL found for ${sample.title}!');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
