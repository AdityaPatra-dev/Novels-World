import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/utils/text_cleaner.dart';

void main() {
  group('TextCleaner.isValidCoverUrl Tests', () {
    test('filters out website logos and brand headers', () {
      expect(TextCleaner.isValidCoverUrl('https://example.com/logo.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/images/header-logo.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/site-logo.svg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/main_logo.jpg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/assets/logo_light.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/logo.webp'), isFalse);
    });

    test('filters out favicons, site icons, and avatars', () {
      expect(TextCleaner.isValidCoverUrl('https://example.com/favicon.ico'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/favicon.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/author-avatar.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/user_avatar.jpg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/app-icon.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/site-icon.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/icon.png'), isFalse);
    });

    test('filters out placeholders, default covers, banners, and dummy data', () {
      expect(TextCleaner.isValidCoverUrl('https://example.com/cover-placeholder.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/default-cover.jpg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/no-cover.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/nocover.jpg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://royalroad.com/dist/img/anon-art.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/dflazy.jpg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/blank.gif'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/dummy.jpg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/header-banner.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/top-banner.jpg'), isFalse);
      expect(TextCleaner.isValidCoverUrl('data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'), isFalse);
      expect(TextCleaner.isValidCoverUrl(''), isFalse);
      expect(TextCleaner.isValidCoverUrl('   '), isFalse);
      expect(TextCleaner.isValidCoverUrl(null), isFalse);
    });

    test('accepts genuine novel book covers', () {
      expect(TextCleaner.isValidCoverUrl('https://cdn.example.com/covers/solo-leveling.jpg'), isTrue);
      expect(TextCleaner.isValidCoverUrl('https://example.com/wp-content/uploads/2024/05/lord_of_the_mysteries.webp'), isTrue);
      expect(TextCleaner.isValidCoverUrl('https://allfreenovel.com/Covers/12345.jpg'), isTrue);
      expect(TextCleaner.isValidCoverUrl('https://readwn.com/files/article/image/1/123/123s.jpg'), isTrue);
      expect(TextCleaner.isValidCoverUrl('file:///storage/emulated/0/Novels/cover.jpg'), isTrue);
    });

    test('Novel model and cover preservation logic prevents logo overwrite', () {
      const cardCoverUrl = 'https://cdn.example.com/covers/shadow-slave.jpg';
      const logoCoverUrl = 'https://example.com/assets/header-logo.png';

      final initialNovel = Novel(
        id: 'test_1',
        title: 'Shadow Slave',
        author: 'Guiltythree',
        sourceId: 'src_1',
        sourceUrl: 'https://example.com/shadow-slave',
        coverUrl: cardCoverUrl,
      );

      // Simulates getNovelDetails returning metadata with the site logo
      final fullNovelFromSite = Novel(
        id: 'test_1',
        title: 'Shadow Slave - Full',
        author: 'Guiltythree',
        sourceId: 'src_1',
        sourceUrl: 'https://example.com/shadow-slave',
        coverUrl: logoCoverUrl,
      );

      // The preservation logic in NovelDetailScreen:
      String bestCover = fullNovelFromSite.coverUrl.trim();
      if (!TextCleaner.isValidCoverUrl(bestCover)) {
        if (TextCleaner.isValidCoverUrl(initialNovel.coverUrl)) {
          bestCover = initialNovel.coverUrl.trim();
        }
      }

      final merged = fullNovelFromSite.copyWith(
        id: initialNovel.id,
        coverUrl: bestCover,
      );

      // Verify that the genuine cover from the card was preserved and the logo was rejected!
      expect(merged.coverUrl, equals(cardCoverUrl));
      expect(merged.coverUrl.contains('logo'), isFalse);
    });
  });
}
