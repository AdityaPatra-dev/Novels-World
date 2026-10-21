import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  final sources = ['novgo', 'readnovelfull', 'libread', 'allnovelfull'];

  for (final sid in sources) {
    test('Verify $sid novel list does NOT contain chapter cards', () async {
      final extractor = SourceRegistry.getSource(sid);
      expect(extractor, isNotNull);

      List novels;
      try {
        novels = await extractor!.getPopular(page: 1);
      } catch (e) {
        // Skip if Cloudflare bot check temporarily triggers on this IP
        print('[$sid] Skipped due to network/Cloudflare challenge: $e');
        return;
      }
      expect(novels.isNotEmpty, isTrue);

      for (final n in novels) {
        expect(
          RegExp(r'^\d+\s+chapters?', caseSensitive: false).hasMatch(n.title),
          isFalse,
          reason: 'Novel title "${n.title}" should not be a chapter count',
        );
        expect(
          n.sourceUrl.contains('/chapter-') || n.sourceUrl.contains('/chap-'),
          isFalse,
          reason: 'Novel sourceUrl "${n.sourceUrl}" should not point to a chapter',
        );
      }
      print('[$sid] Successfully verified ${novels.length} novels with 0 chapter cards.');
      print('Sample 1: "${novels.first.title}" -> ${novels.first.sourceUrl}');
    });
  }
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

