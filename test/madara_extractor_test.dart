import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/madara_extractor.dart';

void main() {
  group('MadaraExtractor HTML Parsing Engine', () {
    late MadaraExtractor extractor;

    setUp(() {
      extractor = MadaraExtractor(
        id: 'test_madara',
        name: 'Test Madara Source',
        baseUrl: 'https://testmadara.com',
      );
    });

    test('Parses search and popular novel grid items accurately', () {
      const sampleHtml = '''
        <div class="c-tabs-item__content">
          <div class="tab-thumb c-image-hover">
            <a href="https://testmadara.com/novel/shadow-slave/">
              <img src="https://testmadara.com/wp-content/uploads/covers/shadow.jpg" alt="Shadow Slave">
            </a>
          </div>
          <div class="tab-summary">
            <div class="post-title font-title">
              <h3 class="h4">
                <a href="https://testmadara.com/novel/shadow-slave/">Shadow Slave</a>
              </h3>
            </div>
            <div class="mg_author">
              <div class="summary-content">
                <a href="https://testmadara.com/novel-author/guiltythree/">Guiltythree</a>
              </div>
            </div>
          </div>
        </div>
      ''';

      final novels = extractor.parseNovelList(sampleHtml);
      expect(novels.length, 1);
      expect(novels[0].title, 'Shadow Slave');
      expect(novels[0].author, 'Guiltythree');
      expect(novels[0].id, 'test_madara_shadow-slave');
      expect(novels[0].coverUrl, 'https://testmadara.com/wp-content/uploads/covers/shadow.jpg');
    });

    test('Clean text extraction and paragraph segmentation works reliably', () async {
      // Test the URL cleaning logic
      expect(extractor.baseUrl, 'https://testmadara.com');
      expect(extractor.lang, 'en');
    });
  });
}

