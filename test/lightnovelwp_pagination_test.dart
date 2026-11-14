import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/lightnovelwp_extractor.dart';

void main() {
  group('LightNovelWP & KolNovel Chapter Parsing Tests', () {
    test('Correctly parses KnoxT / standard Themesia chapter items', () {
      final extractor = LightNovelWpExtractor(
        id: 'knoxt',
        name: 'KnoxT',
        baseUrl: 'https://knoxt.space',
        lang: 'en',
      );

      const html = '''
<div class="eplister">
  <ul>
    <li>
      <a href="https://knoxt.space/caretaker-of-a-fierce-merman-chapter-1/">
        <div class="epl-num">Ch. 1</div>
        <div class="epl-title">CFM Chapter 1</div>
        <div class="epl-date">October 20, 2026</div>
      </a>
    </li>
    <li>
      <a href="https://knoxt.space/caretaker-of-a-fierce-merman-chapter-2/">
        <div class="epl-num">Ch. 2</div>
        <div class="epl-title">CFM Chapter 2</div>
        <div class="epl-date">October 22, 2026</div>
      </a>
    </li>
  </ul>
</div>
''';

      final chapters = extractor.parseChapterList(
        'https://knoxt.space/caretaker-of-a-fierce-merman/',
        html,
      );

      expect(chapters.length, equals(2));
      expect(chapters[0].title, equals('Ch. 1: CFM Chapter 1'));
      expect(chapters[0].chapterNumber, equals(1.0));
      expect(chapters[1].title, equals('Ch. 2: CFM Chapter 2'));
      expect(chapters[1].chapterNumber, equals(2.0));
    });

    test('Correctly parses KolNovel Arabic editorial chapter table items', () {
      final extractor = LightNovelWpExtractor(
        id: 'kolnovel',
        name: 'Kol Novel',
        baseUrl: 'https://kolnovel.com',
        lang: 'ar',
      );

      const kolHtml = '''
<div class="kol-series-editorial__chapter-table">
  <a href="https://kolnovel.com/series/reincarnation-of-the-strongest-sword-god/?chapter_volume=__kol_all__&chapter_search&chapter_order=newest&chapter_page=1#chapters">عرض فصول هذا المجلد</a>
  <a href="https://kolnovel.com/shaag24reincarnation-of-the-strongest-sword-godz435ggye-303867/">
    فصل 1556: تاجر NPC برتبة 3 نجوم
  </a>
  <a href="https://kolnovel.com/shaag24reincarnation-of-the-strongest-sword-godz435ggye-303866/">
    فصل 1555: المزايا الداخلية
  </a>
</div>
''';

      final chapters = extractor.parseChapterList(
        'https://kolnovel.com/series/reincarnation-of-the-strongest-sword-god/',
        kolHtml,
      );

      expect(chapters.length, equals(2));
      expect(chapters[0].title, contains('فصل 1555'));
      expect(chapters[1].title, contains('فصل 1556'));
      expect(chapters[0].chapterNumber, equals(1555.0));
      expect(chapters[1].chapterNumber, equals(1556.0));
    });
  });
}
