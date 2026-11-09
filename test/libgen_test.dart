import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';

void main() {
  test('LibGenExtractor parseHtmlTable prioritizes EPUBs and preserves metadata', () {
    final extractor = LibGenExtractor();
    const sampleHtml = '''
    <table id="tablelibgen">
      <tr>
        <td>1</td>
        <td>Frank Herbert</td>
        <td><a href="edition.php?id=123" id="title">Dune</a></td>
        <td>Smashwords</td>
        <td>2011</td>
        <td>epub</td>
        <td><a href="ads.php?md5=f7841e44df83a55b916ef711ceea6061">GET</a></td>
      </tr>
      <tr>
        <td>2</td>
        <td>Leslie Stratyner</td>
        <td><a href="edition.php?id=456" id="title">Fantasy Essays</a></td>
        <td>McFarland</td>
        <td>2007</td>
        <td>pdf</td>
        <td><a href="ads.php?md5=6e2c8664443ad0a6c8d539a0fd3dcf1b">GET</a></td>
      </tr>
    </table>
    ''';

    final novels = extractor.parseHtmlTable(sampleHtml, 'https://libgen.li');
    expect(novels.isNotEmpty, true);
    // When EPUBs are present, EPUBs should be returned first
    expect(novels.first.bookFormat, 'epub');
    expect(novels.first.title, 'Dune');
    expect(novels.first.author, 'Frank Herbert');
    expect(novels.first.sourceUrl, 'https://libgen.li/ads.php?md5=f7841e44df83a55b916ef711ceea6061');
    expect(novels.first.bookDownloadUrl, 'https://libgen.li/get.php?md5=f7841e44df83a55b916ef711ceea6061');
  });

  test('LibGenExtractor live search returns clean EPUB novels with working ads links', () async {
    final extractor = LibGenExtractor();
    final results = await extractor.search('dune');
    expect(results.isNotEmpty, true);
    for (final novel in results) {
      expect(novel.sourceId, 'libgen');
      expect(novel.sourceUrl.contains('ads.php?md5='), true);
      expect(novel.bookFormat, 'epub');
    }
  });
}
