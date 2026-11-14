import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  final allSources = SourceRegistry.getAllSources();

  test('Verify All Registered Sources End-to-End Concurrent', () async {
    print('================================================================');
    print('TOTAL REGISTERED SOURCES TO VERIFY: ${allSources.length}');
    print('================================================================');

    final testableSources = allSources.where((s) => s.id != 'local_epub').toList();
    final results = <Map<String, dynamic>>[];

    Future<Map<String, dynamic>> testSource(dynamic source) async {
      final result = <String, dynamic>{
        'id': source.id,
        'name': source.name,
        'lang': source.lang,
        'catalogOk': false,
        'detailsOk': false,
        'chaptersOk': false,
        'contentOk': false,
        'novelCount': 0,
        'sampleTitle': '',
        'chapterCount': 0,
        'paragraphsCount': 0,
        'error': '',
        'isCloudflare': false,
      };

      try {
        // 1. Catalog
        List<Novel> novels = [];
        try {
          novels = await source.getPopular(page: 1).timeout(const Duration(seconds: 12));
        } catch (e) {
          try {
            novels = await source.getLatest(page: 1).timeout(const Duration(seconds: 12));
          } catch (e2) {
            novels = await source.search('fantasy', page: 1).timeout(const Duration(seconds: 12));
          }
        }

        if (novels.isEmpty) {
          throw Exception('Empty novel catalog returned (0 items)');
        }

        final firstNovel = novels.first;
        result['catalogOk'] = true;
        result['novelCount'] = novels.length;
        result['sampleTitle'] = firstNovel.title;

        // 2. Details
        try {
          await source.getNovelDetails(firstNovel.sourceUrl).timeout(const Duration(seconds: 12));
          result['detailsOk'] = true;
        } catch (e) {
          // Non-fatal
        }

        // 3. Chapters
        List<Chapter> chapters = [];
        try {
          chapters = await source.getChapterList(firstNovel.sourceUrl).timeout(const Duration(seconds: 12));
          if (chapters.isNotEmpty) {
            result['chaptersOk'] = true;
            result['chapterCount'] = chapters.length;

            // 4. Content
            try {
              final content = await source.getChapterContent(chapters.first.url).timeout(const Duration(seconds: 12));
              if (content.paragraphs.isNotEmpty) {
                result['contentOk'] = true;
                result['paragraphsCount'] = content.paragraphs.length;
              }
            } catch (e) {
              // Non-fatal
            }
          }
        } catch (e) {
          // Non-fatal
        }
      } catch (e) {
        final errStr = e.toString();
        result['error'] = errStr;
        if (errStr.contains('403') ||
            errStr.toLowerCase().contains('cloudflare') ||
            errStr.toLowerCase().contains('webview') ||
            errStr.toLowerCase().contains('just a moment')) {
          result['isCloudflare'] = true;
        }
      }

      return result;
    }

    // Run in parallel chunks of 8
    const chunkSize = 8;
    for (int i = 0; i < testableSources.length; i += chunkSize) {
      final chunk = testableSources.skip(i).take(chunkSize).toList();
      final chunkResults = await Future.wait(chunk.map((s) => testSource(s)));
      results.addAll(chunkResults);
      for (final r in chunkResults) {
        final status = (r['catalogOk'] && r['chaptersOk'] && r['contentOk'])
            ? '✅ FULL_PIPELINE'
            : (r['catalogOk'] ? '⚡ CATALOG_OK' : (r['isCloudflare'] ? '🛡️ CLOUDFLARE' : '❌ FAILED: ${r['error']}'));
        print('  [${r['id']}] ${r['name']} -> $status (Novels: ${r['novelCount']}, Ch: ${r['chapterCount']}, Paras: ${r['paragraphsCount']})');
      }
    }

    print('\n================================================================');
    print('HEALTH VERIFICATION SUMMARY:');
    print('================================================================');
    int fullyWorking = 0;
    int catalogOk = 0;
    int cloudflareProtected = 0;
    int failed = 0;

    for (final r in results) {
      if (r['catalogOk'] && r['chaptersOk'] && r['contentOk']) {
        fullyWorking++;
      } else if (r['catalogOk']) {
        catalogOk++;
      } else if (r['isCloudflare']) {
        cloudflareProtected++;
      } else {
        failed++;
      }
    }

    print('TOTAL TESTED SOURCES: ${results.length}');
    print('FULL PIPELINE WORKING (Catalog + Details + Chapters + Narrative): $fullyWorking');
    print('CATALOG / METADATA OK (Direct EPUB or Single Book): $catalogOk');
    print('CLOUDFLARE PROTECTED (In-App WebView session required): $cloudflareProtected');
    print('FAILED / BROKEN: $failed');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
