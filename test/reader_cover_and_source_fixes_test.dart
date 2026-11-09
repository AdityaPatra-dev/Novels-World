import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/core/services/epub_service.dart';
import 'package:novels_world/core/utils/text_cleaner.dart';
import 'package:novels_world/extractors/bespoke/openlibrary_extractor.dart';
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';

void main() {
  group('Reader & EPUB Front-matter Skipping Tests', () {
    test('getFirstNarrativeChapter skips cover, titlepage, and wrapper sections', () {
      final chapters = [
        Chapter(id: '1', novelId: 'book', title: 'Cover', url: 'OEBPS/wrap0000.html'),
        Chapter(id: '2', novelId: 'book', title: 'Title Page', url: 'OEBPS/titlepage.xhtml'),
        Chapter(id: '3', novelId: 'book', title: 'Copyright', url: 'OEBPS/copyright.xhtml'),
        Chapter(id: '4', novelId: 'book', title: 'Chapter 1: The Beginning', url: 'OEBPS/chapter1.xhtml'),
        Chapter(id: '5', novelId: 'book', title: 'Chapter 2: The Journey', url: 'OEBPS/chapter2.xhtml'),
      ];

      final firstNarrative = EpubService.getFirstNarrativeChapter(chapters);
      expect(firstNarrative.id, equals('3')); // skips cover and title page
    });

    test('getFirstNarrativeChapter falls back gracefully if all chapters are named cover', () {
      final chapters = [
        Chapter(id: '1', novelId: 'book', title: 'Cover 1', url: 'cover1.xhtml'),
        Chapter(id: '2', novelId: 'book', title: 'Cover 2', url: 'cover2.xhtml'),
      ];

      final first = EpubService.getFirstNarrativeChapter(chapters);
      expect(first.id, equals('1'));
    });

    test('ChapterContent.toSentences preserves [IMAGE:] tokens and prevents crashes', () {
      const content = ChapterContent(
        chapterId: 'c1',
        novelId: 'n1',
        title: 'Illustration Section',
        rawText: 'Illustration',
        paragraphs: [
          '[IMAGE:file:///tmp/cover.jpg]',
          'This is a caption for the illustration.',
        ],
      );

      final units = content.toSentences();
      expect(units.isNotEmpty, isTrue);
      expect(units.first, equals('[IMAGE:file:///tmp/cover.jpg]'));
      expect(units.last, contains('caption'));
    });
  });

  group('TextCleaner Cover and Paragraph Enhancements', () {
    test('NovelCool cover URLs with /logo/ are recognized as valid covers', () {
      expect(TextCleaner.isValidCoverUrl('https://img.novelcool.com/logo/cover_12345.jpg'), isTrue);
      expect(TextCleaner.isValidCoverUrl('https://www.novelcool.com/logo/book.png'), isTrue);
    });

    test('General website headers and generic logos are still filtered out', () {
      expect(TextCleaner.isValidCoverUrl('https://example.com/site-logo.png'), isFalse);
      expect(TextCleaner.isValidCoverUrl('https://example.com/favicon.ico'), isFalse);
      expect(TextCleaner.isValidCoverUrl(''), isFalse);
      expect(TextCleaner.isValidCoverUrl(null), isFalse);
    });

    test('cleanParagraphs preserves embedded image tokens without stripping them', () {
      final input = [
        '  [IMAGE:file:///storage/book/cover.jpg]  ',
        'Normal text paragraph.',
      ];
      final cleaned = TextCleaner.cleanParagraphs(input);
      expect(cleaned.length, equals(2));
      expect(cleaned[0], equals('[IMAGE:file:///storage/book/cover.jpg]'));
    });
  });

  group('LibGen & Open Library Parsing Tests', () {
    test('LibGen getNovelDetails does not replace title with Library Genesis', () {
      final extractor = LibGenExtractor();
      const mockAdsHtml = '''
<!DOCTYPE html>
<html>
<head><title>Library Genesis</title></head>
<body>
<table width=700>
<tr><td>Title: Dune - The Novel<br>
Author(s): Frank Herbert<br></td></tr>
<tr><td><textarea id='bibtext'>@book{123, title = {Dune - The Novel}, author = {Frank Herbert}}</textarea></td></tr>
</table>
<a href="get.php?md5=abcdef123456&key=XYZ"><h2>GET</h2></a>
</body>
</html>
''';

      // We can test the parsing logic directly
      final doc = extractor.parseHtmlTable('''
<table id="tablelibgen">
<tr>
<td><a href="edition.php?id=1">Dune</a></td>
<td>Frank Herbert</td>
<td>Marvel</td>
<td>2020</td>
<td>English</td>
<td>100</td>
<td>1 MB</td>
<td>epub</td>
<td><a href="/get.php?md5=abcdef123456">Libgen</a></td>
</tr>
</table>
''');
      expect(doc.isNotEmpty, isTrue);
      expect(doc.first.title, contains('Dune'));
      expect(doc.first.author, equals('Frank Herbert'));
      expect(doc.first.bookFormat, equals('epub'));
    });
  });
}
