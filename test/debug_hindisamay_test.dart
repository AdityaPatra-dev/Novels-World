import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/utils/http_client_factory.dart';

Uri parseSafeUri(String url) {
  var clean = url.trim();
  if (clean.startsWith('http://')) {
    clean = 'https://${clean.substring(7)}';
  }
  try {
    return Uri.parse(clean);
  } catch (_) {
    try {
      final schemeMatch = RegExp(r'^(https?://[^/]+)(.*)$').firstMatch(clean);
      if (schemeMatch != null) {
        final prefix = schemeMatch.group(1)!;
        final pathAndQuery = schemeMatch.group(2)!;
        final encodedPath = Uri.encodeFull(pathAndQuery);
        return Uri.parse('$prefix$encodedPath');
      }
    } catch (_) {}
    return Uri.parse(Uri.encodeFull(clean));
  }
}

void main() {
  test('Test safe URI encoding for Hindi Samay .cspx URL', () async {
    final client = createPlatformHttpClient();
    final url = 'http://www.hindisamay.com/content/196/1/शरतचंद्र-चट्टोपाध्याय-उपन्‍यास-पथ-के-दावेदार.cspx';
    final safeUri = parseSafeUri(url);
    print('Resulting safe URI: $safeUri');
    final resp = await client.get(safeUri, headers: {
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'text/html',
    });
    print('Status: ${resp.statusCode}, body length: ${resp.body.length}');
    expect(resp.statusCode, 200);
    expect(resp.body.length > 10000, true);
  });
}
