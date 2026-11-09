import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/readwn_extractor.dart';

void main() {
  group('WuxiaBox / ReadWn Chapter Parsing Tests', () {
    test('Correctly parses chapter content when paragraphs are separated by <br> instead of <p>', () {
      final extractor = ReadWnExtractor(
        id: 'wuxiabox',
        name: 'WuxiaBox',
        baseUrl: 'https://www.wuxiabox.com',
        lang: 'en',
      );

      const html = '''
<!DOCTYPE html>
<html>
<head><title>Chapter 1</title></head>
<body>
<main>
  <article>
    <header>
      <h2>Chapter 1 Qiao's family has a fake daughter</h2>
    </header>
    <div class="chapter-content">
      <div align="center"><script>ad();</script></div>
      Chapter 1 Qiao's family has a fake daughter<br><br>
      The June sky around the city was like a furnace. The scorching sun formed layers of heat waves on the asphalt road.<br><br>
      Qiao Nian came out of the room dragging her newly packed luggage.<br><br>
      Before going downstairs, I heard Qiao Chen chirping downstairs.<br><br>
      "Mom and Dad, are Qiao Nian's biological parents really coming to pick her up?"<br><br>
      Father Qiao asked her strictly, "Why do you care about this?"<br><br>
      This life is ruined!<br><br>
      (End of this chapter)
    </div>
  </article>
</main>
</body>
</html>
''';

      final content = extractor.parseChapterContent(
        'https://www.wuxiabox.com/novel/madams-identities-shocks-the-entire-city-again_1.html',
        html,
      );

      expect(content.paragraphs.isNotEmpty, isTrue);
      expect(content.paragraphs.length, greaterThanOrEqualTo(5));
      expect(content.paragraphs[0], contains("Qiao's family has a fake daughter"));
      expect(content.paragraphs[1], contains("The June sky around the city"));
      expect(content.toSentences().isNotEmpty, isTrue);
    });

    test('Correctly parses chapter content when standard <p> tags are used', () {
      final extractor = ReadWnExtractor(
        id: 'wuxiabox',
        name: 'WuxiaBox',
        baseUrl: 'https://www.wuxiabox.com',
        lang: 'en',
      );

      const html = '''
<div class="chapter-content">
  <p>Standard paragraph one with good prose.</p>
  <p>Standard paragraph two continuing the epic journey.</p>
  <p>Standard paragraph three concluding the chapter.</p>
</div>
''';

      final content = extractor.parseChapterContent('https://example.com/ch1', html);
      expect(content.paragraphs.length, equals(3));
      expect(content.paragraphs[0], equals('Standard paragraph one with good prose.'));
    });
  });
}
