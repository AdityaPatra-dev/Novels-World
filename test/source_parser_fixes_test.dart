import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novels_world/core/utils/text_cleaner.dart';
import 'package:novels_world/extractors/novelfull_extractor.dart';
import 'package:novels_world/extractors/madara_extractor.dart';
import 'package:novels_world/extractors/readwn_extractor.dart';
import 'package:novels_world/extractors/bespoke/scribblehub_extractor.dart';

void main() {
  group('Genre Panel & URL Filter Verification', () {
    test('Rejects standard genre names as novel titles', () {
      expect(TextCleaner.isValidNovelTitle('Action', 'https://novelfull.com/novel/action-hero.html'), isFalse);
      expect(TextCleaner.isValidNovelTitle('Fantasy', 'https://novelfull.com/novel/fantasy-world.html'), isFalse);
      expect(TextCleaner.isValidNovelTitle('Romance', 'https://novelfull.com/novel/sweet-romance.html'), isFalse);
      expect(TextCleaner.isValidNovelTitle('Harem', 'https://novelfull.com/novel/harem-king.html'), isFalse);
      expect(TextCleaner.isValidNovelTitle('Sci-fi', 'https://novelfull.com/novel/scifi-future.html'), isFalse);
      expect(TextCleaner.isValidNovelTitle('Xianxia', 'https://novelfull.com/novel/immortal-dao.html'), isFalse);
      expect(TextCleaner.isValidNovelTitle('Completed Novels', 'https://novelfull.com/completed'), isFalse);
      expect(TextCleaner.isValidNovelTitle('Latest Release', 'https://novelfull.com/latest'), isFalse);
    });

    test('Rejects genre, category, tag, author, and filter URLs', () {
      expect(TextCleaner.isGenreOrCategoryUrl('https://novelfull.com/genre/action'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('https://novelfull.com/genres/fantasy.html'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('https://boxnovel.com/category/martial-arts/'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('https://knoxt.space/categories/urban/'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('https://wuxiabox.com/tag/overpowered-protagonist'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('https://testmadara.com/manga-tag/isekai/'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('https://novelfull.com/sort/most-popular'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('https://novelfull.com/author/cuttlefish'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('#'), isTrue);
      expect(TextCleaner.isGenreOrCategoryUrl('/'), isTrue);

      // Legitimate novel URLs must NOT be flagged
      expect(TextCleaner.isGenreOrCategoryUrl('https://novelfull.com/lord-of-the-mysteries.html'), isFalse);
      expect(TextCleaner.isGenreOrCategoryUrl('https://boxnovel.com/novel/shadow-slave/'), isFalse);
      expect(TextCleaner.isGenreOrCategoryUrl('https://www.wuxiabox.com/novel/reverend-insanity.html'), isFalse);
    });

    test('Accepts valid novel titles with normal URLs', () {
      expect(TextCleaner.isValidNovelTitle('Lord of the Mysteries', 'https://novelfull.com/lord-of-the-mysteries.html'), isTrue);
      expect(TextCleaner.isValidNovelTitle('Shadow Slave', 'https://boxnovel.com/novel/shadow-slave/'), isTrue);
      expect(TextCleaner.isValidNovelTitle('Reverend Insanity', 'https://www.wuxiabox.com/novel/reverend-insanity.html'), isTrue);
    });
  });

  group('NovelFull 100+ Chapter Resolution', () {
    test('Fetches all chapters from AJAX chapter archive even when static HTML has preview chapters', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('lord-of-the-mysteries.html')) {
          // Static page has rating container with data-novel-id and only 2 preview chapters
          return http.Response('''
            <html>
              <body>
                <h1 class="novel-title">Lord of the Mysteries</h1>
                <div id="rating" data-novel-id="4567"></div>
                <ul class="list-chapter">
                  <li><a href="/novel/lord-of-the-mysteries/chapter-1.html">Chapter 1</a></li>
                  <li><a href="/novel/lord-of-the-mysteries/chapter-2.html">Chapter 2</a></li>
                </ul>
              </body>
            </html>
          ''', 200);
        } else if (request.url.path.contains('/ajax/chapter-archive')) {
          expect(request.url.queryParameters['novelId'], '4567');
          // AJAX returns all 150 chapters
          final buffer = StringBuffer('<ul class="list-chapter">');
          for (int i = 1; i <= 150; i++) {
            buffer.write('<li><a href="/novel/lord-of-the-mysteries/chapter-$i.html">Chapter $i</a></li>');
          }
          buffer.write('</ul>');
          return http.Response(buffer.toString(), 200);
        }
        return http.Response('Not Found', 404);
      });

      final extractor = NovelFullExtractor(
        id: 'novelfull',
        name: 'NovelFull',
        baseUrl: 'https://novelfull.com',
        client: mockClient,
      );

      final chapters = await extractor.getChapterList('https://novelfull.com/lord-of-the-mysteries.html');
      expect(chapters.length, 150);
      expect(chapters.first.title, 'Chapter 1');
      expect(chapters.last.title, 'Chapter 150');
    });

    test('Throws on genre/category URL in getChapterList and getNovelDetails', () async {
      final extractor = NovelFullExtractor(
        id: 'novelfull',
        name: 'NovelFull',
        baseUrl: 'https://novelfull.com',
        client: MockClient((_) async => http.Response('', 200)),
      );

      expect(
        () => extractor.getChapterList('https://novelfull.com/genre/action'),
        throwsA(isA<Exception>()),
      );
      expect(
        () => extractor.getNovelDetails('https://novelfull.com/category/fantasy'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Madara Complete Chapter & Order Resolution', () {
    test('Prioritizes AJAX full chapter list over static preview chapters and orders Chapter 1 first', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/novel/shadow-slave/') {
          // Static page has only 3 preview chapters in sidebar
          return http.Response('''
            <html>
              <body>
                <div class="post-title"><h1>Shadow Slave</h1></div>
                <input type="hidden" id="wp-manga-post-id" value="9876" />
                <ul class="main version-chap">
                  <li class="wp-manga-chapter"><a href="https://testmadara.com/novel/shadow-slave/chapter-3/">Chapter 3</a></li>
                  <li class="wp-manga-chapter"><a href="https://testmadara.com/novel/shadow-slave/chapter-2/">Chapter 2</a></li>
                  <li class="wp-manga-chapter"><a href="https://testmadara.com/novel/shadow-slave/chapter-1/">Chapter 1</a></li>
                </ul>
              </body>
            </html>
          ''', 200);
        } else if (request.url.path.contains('/ajax/chapters/')) {
          // AJAX endpoint returns 250 chapters, listed newest-first (as standard in Madara)
          final buffer = StringBuffer('<ul class="main version-chap">');
          for (int i = 250; i >= 1; i--) {
            buffer.write('<li class="wp-manga-chapter"><a href="https://testmadara.com/novel/shadow-slave/chapter-$i/">Chapter $i</a></li>');
          }
          buffer.write('</ul>');
          return http.Response(buffer.toString(), 200);
        }
        return http.Response('Not Found', 404);
      });

      final extractor = MadaraExtractor(
        id: 'testmadara',
        name: 'Test Madara',
        baseUrl: 'https://testmadara.com',
        client: mockClient,
      );

      final chapters = await extractor.getChapterList('https://testmadara.com/novel/shadow-slave/');
      expect(chapters.length, 250);
      // Ensure reading order is sequential from Chapter 1 to Chapter 250
      expect(chapters.first.title, 'Chapter 1');
      expect(chapters[1].title, 'Chapter 2');
      expect(chapters.last.title, 'Chapter 250');
    });
  });

  group('ReadWn Multi-Page Chapter Pagination', () {
    test('Follows pagination and loads all chapters beyond 100', () async {
      final mockClient = MockClient((request) async {
        if (request.url.queryParameters['page'] == '2') {
          // Page 2 has another 70 chapters (total 130)
          final buffer = StringBuffer('''
            <html>
              <body>
                <div class="chapter-list">
          ''');
          for (int i = 61; i <= 130; i++) {
            buffer.write('<a href="/novel/warlock-of-the-magus-world/chapter-$i.html">Chapter $i</a>');
          }
          buffer.write('''
                </div>
              </body>
            </html>
          ''');
          return http.Response(buffer.toString(), 200);
        } else if (request.url.path == '/novel/warlock-of-the-magus-world.html') {
          // Page 1 has 60 chapters and pagination link to page 2
          final buffer = StringBuffer('''
            <html>
              <body>
                <h1>Warlock of the Magus World</h1>
                <div class="chapter-list">
          ''');
          for (int i = 1; i <= 60; i++) {
            buffer.write('<a href="/novel/warlock-of-the-magus-world/chapter-$i.html">Chapter $i</a>');
          }
          buffer.write('''
                </div>
                <ul class="pagination">
                  <li><a href="https://www.wuxiabox.com/novel/warlock-of-the-magus-world.html?page=2">2</a></li>
                </ul>
              </body>
            </html>
          ''');
          return http.Response(buffer.toString(), 200);
        }
        return http.Response('Not Found', 404);
      });

      final extractor = ReadWnExtractor(
        id: 'wuxiabox',
        name: 'WuxiaBox',
        baseUrl: 'https://www.wuxiabox.com',
        client: mockClient,
      );

      final chapters = await extractor.getChapterList('https://www.wuxiabox.com/novel/warlock-of-the-magus-world.html');
      expect(chapters.length, 130);
      expect(chapters.first.title, 'Chapter 1');
      expect(chapters.last.title, 'Chapter 130');
    });
  });

  group('ScribbleHub Multi-Page AJAX Pagination', () {
    test('Iterates wi_getreleases_pagination and retrieves all chapter pages', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/series/12345/my-story/') {
          // Novel page with mypostid
          return http.Response('''
            <html>
              <body>
                <h1 class="fic_title">My Story</h1>
                <input type="hidden" id="mypostid" value="12345" />
                <ol class="toc_ol">
                  <li><a href="https://www.scribblehub.com/read/12345/chapter/1/">Chapter 1</a></li>
                </ol>
              </body>
            </html>
          ''', 200);
        } else if (request.url.path.contains('admin-ajax.php')) {
          final body = request.body;
          if (body.contains('pagenum=1')) {
            return http.Response('''
              <ol class="toc_ol">
                <li><a href="https://www.scribblehub.com/read/12345/chapter/20/">Chapter 20</a></li>
                <li><a href="https://www.scribblehub.com/read/12345/chapter/19/">Chapter 19</a></li>
              </ol>
            ''', 200);
          } else if (body.contains('pagenum=2')) {
            return http.Response('''
              <ol class="toc_ol">
                <li><a href="https://www.scribblehub.com/read/12345/chapter/18/">Chapter 18</a></li>
                <li><a href="https://www.scribblehub.com/read/12345/chapter/1/">Chapter 1</a></li>
              </ol>
            ''', 200);
          }
          return http.Response('', 200);
        }
        return http.Response('Not Found', 404);
      });

      final extractor = ScribbleHubExtractor(client: mockClient);
      final chapters = await extractor.getChapterList('https://www.scribblehub.com/series/12345/my-story/');
      expect(chapters.length, 4);
      // Ensure reading order is sequential (Chapter 1 first)
      expect(chapters.first.title, 'Chapter 1');
      expect(chapters.last.title, 'Chapter 20');
    });
  });
}
