import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';

void main() {
  test('debug LibGen getNovelDetails', () async {
    final client = http.Client();
    final ext = LibGenExtractor(client: client);
    final targetUrl = 'https://libgen.li/ads.php?md5=f7841e44df83a55b916ef711ceea6061';
    print('Calling get on $targetUrl ...');
    try {
      final res = await client.get(
        Uri.parse(targetUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Referer': 'https://libgen.li/',
        },
      ).timeout(const Duration(seconds: 12));
      print('Status: ${res.statusCode}');
      print('Body length: ${res.body.length}');
      print('Body preview: ${res.body.substring(0, res.body.length > 300 ? 300 : res.body.length)}');

      final detailed = await ext.getNovelDetails(targetUrl);
      print('Detailed Title: ${detailed.title}');
      print('Detailed Author: ${detailed.author}');
      print('Detailed DownloadUrl: ${detailed.bookDownloadUrl}');
    } catch (e, st) {
      print('Error: $e\n$st');
    }
  });
}
