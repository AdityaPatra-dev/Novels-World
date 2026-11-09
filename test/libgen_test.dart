import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';

void main() {
  test('LibGenExtractor parseHtmlTable prioritizes EPUBs and preserves metadata', () {
    final extractor = LibGenExtractor();
    const sampleHtml = '''
    <table id="tablelibgen">
      <tr>
        <td><a href="edition.php?id=123" id="title">Tales of Dune</a><span class="badge badge-secondary">f 10105216</span></td>
        <td>Frank Herbert</td>
        <td>Smashwords</td>
        <td>2011</td>
        <td>English</td>
        <td>epub</td>
        <td><a href="ads.php?md5=f7841e44df83a55b916ef711ceea6061">GET</a></td>
      </tr>
      <tr>
        <td><a href="edition.php?id=456" id="title">Fantasy Essays</a><span class="badge badge-secondary">l 1510172</span></td>
        <td>Leslie Stratyner</td>
        <td>McFarland</td>
        <td>2007</td>
        <td>English</td>
        <td>pdf</td>
        <td><a href="ads.php?md5=6e2c8664443ad0a6c8d539a0fd3dcf1b">GET</a></td>
      </tr>
    </table>
    ''';

    final novels = extractor.parseHtmlTable(sampleHtml, 'https://libgen.li');
    expect(novels.isNotEmpty, true);
    // When EPUBs are present, EPUBs should be returned first
    expect(novels.first.bookFormat, 'epub');
    expect(novels.first.title, 'Tales of Dune');
    expect(novels.first.author, 'Frank Herbert');
    expect(novels.first.coverUrl, 'https://libgen.li/fictioncovers/10105000/f7841e44df83a55b916ef711ceea6061.jpg');
    expect(novels.first.sourceUrl, 'https://libgen.li/ads.php?md5=f7841e44df83a55b916ef711ceea6061');
    expect(novels.first.bookDownloadUrl, 'https://libgen.li/get.php?md5=f7841e44df83a55b916ef711ceea6061');
  });

  test('LibGenExtractor parseHtmlTable prioritizes English editions', () {
    final extractor = LibGenExtractor();
    const sampleHtml = '''
    <table id="tablelibgen">
      <tr>
        <td><a href="edition.php?id=111">Saga Dune 1-6</a><span class="badge badge-secondary">f 3654561</span></td>
        <td>Frank Herbert</td>
        <td>Penguin Spain</td>
        <td>2021</td>
        <td>Spanish</td>
        <td>epub</td>
        <td><a href="ads.php?md5=38d020df68fef15961be13332aa2b79e">GET</a></td>
      </tr>
      <tr>
        <td><a href="edition.php?id=222">Tales of Dune</a><span class="badge badge-secondary">f 10105216</span></td>
        <td>Frank Herbert</td>
        <td>Smashwords</td>
        <td>2011</td>
        <td>English</td>
        <td>epub</td>
        <td><a href="ads.php?md5=f7841e44df83a55b916ef711ceea6061">GET</a></td>
      </tr>
    </table>
    ''';

    final novels = extractor.parseHtmlTable(sampleHtml, 'https://libgen.li');
    expect(novels.length, 2);
    // English edition should be ranked first
    expect(novels.first.title, 'Tales of Dune');
    expect(novels.first.coverUrl, 'https://libgen.li/fictioncovers/10105000/f7841e44df83a55b916ef711ceea6061.jpg');
    expect(novels.last.title, 'Saga Dune 1');
  });

  test('LibGenExtractor live search returns clean EPUB novels with working ads links and covers', () async {
    final extractor = LibGenExtractor();
    final results = await extractor.search('dune');
    expect(results.isNotEmpty, true);
    for (final novel in results) {
      expect(novel.sourceId, 'libgen');
      expect(novel.sourceUrl.contains('ads.php?md5='), true);
      expect(novel.bookFormat, 'epub');
      expect(novel.coverUrl.isNotEmpty, true);
    }
  });
}
