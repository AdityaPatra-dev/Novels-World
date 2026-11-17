import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/utils/http_client_factory.dart';

void main() {
  test('Check with index.php?title=', () async {
    final client = createPlatformHttpClient();
    final url = 'http://kavitakosh.org/kk/index.php?title=%E0%A4%B0%E0%A4%B6%E0%A5%8D%E0%A4%AE%E0%A4%BF%E0%A4%B0%E0%A4%A5%E0%A5%80_/_%E0%A4%AA%E0%A5%8D%E0%A4%B0%E0%A4%A5%E0%A4%AE_%E0%A4%B8%E0%A4%B0%E0%A5%8D%E0%A4%97_/_%E0%A4%AD%E0%A4%BE%E0%A4%97_1';
    final resp = await client.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'text/html',
    });
    print('Status with index.php?title=: ${resp.statusCode}, body: ${resp.body.length}');
    expect(resp.statusCode, 200);
  });
}
