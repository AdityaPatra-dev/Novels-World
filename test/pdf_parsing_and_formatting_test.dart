import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/services/epub_service.dart';

void main() {
  group('PDF Text Formatting Tests', () {
    test('formatPdfTextToParagraphs joins wrapped lines into single paragraphs', () {
      const rawText = '''
This is the first sentence of the book. It wraps across
multiple lines because PDF content has fixed line widths.
And here is another sentence in the same paragraph.

This is a separate paragraph that starts after an empty
line in the document.
''';

      final paragraphs = EpubService.formatPdfTextToParagraphs(rawText);
      expect(paragraphs.length, 2);
      expect(
        paragraphs[0],
        'This is the first sentence of the book. It wraps across multiple lines because PDF content has fixed line widths. And here is another sentence in the same paragraph.',
      );
      expect(
        paragraphs[1],
        'This is a separate paragraph that starts after an empty line in the document.',
      );
    });

    test('formatPdfTextToParagraphs joins hyphenated words across lines', () {
      const rawText = '''
This is an extraor-
dinary discovery in the field of litera-
ture.
''';

      final paragraphs = EpubService.formatPdfTextToParagraphs(rawText);
      expect(paragraphs.length, 1);
      expect(paragraphs[0], 'This is an extraordinary discovery in the field of literature.');
    });

    test('formatPdfTextToParagraphs filters digitizer watermarks and page numbers', () {
      const rawText = '''
Odia Bibhaba
Chapter 1: The Historical Tale
ପୃଷ୍ଠା ୧୨
ଏହା ଏକ ଐତିହାସିକ ଉପନ୍ୟାସ ଅଟେ। ଏଥିରେ ପ୍ରାଚୀନ ଉତ୍କଳର
ବୀରତ୍ୱ ବର୍ଣ୍ଣିତ ହୋଇଅଛି।
Page 12
Digitized by Archive.org
''';

      final paragraphs = EpubService.formatPdfTextToParagraphs(rawText);
      expect(paragraphs.length, 2);
      expect(paragraphs[0], 'Chapter 1: The Historical Tale');
      expect(paragraphs[1], 'ଏହା ଏକ ଐତିହାସିକ ଉପନ୍ୟାସ ଅଟେ। ଏଥିରେ ପ୍ରାଚୀନ ଉତ୍କଳର ବୀରତ୍ୱ ବର୍ଣ୍ଣିତ ହୋଇଅଛି।');
    });

    test('formatPdfTextToParagraphs respects Odia Purna Viram punctuation', () {
      const rawText = '''
ପ୍ରଥମ ଅଧ୍ୟାୟ।
ରାଜା ମୁକୁନ୍ଦ ଦେବ ସିଂହାସନରେ ବିଜେ କଲେ।
ତତ୍ପରେ ସେ ମନ୍ତ୍ରୀଙ୍କୁ ଆଦେଶ ଦେଲେ।
''';

      final paragraphs = EpubService.formatPdfTextToParagraphs(rawText);
      expect(paragraphs.isNotEmpty, isTrue);
      expect(paragraphs.any((p) => p.contains('ମୁକୁନ୍ଦ ଦେବ')), isTrue);
    });
  });

  group('PdfBookParser Tests', () {
    test('extracts and decodes UTF-16BE hex strings properly', () {
      // PDF stream with UTF-16BE hex string (BOM FEFF + Odia "ଓଡ଼ିଆ" = 0B13 0B21 0B3C 0B3F 0B06)
      // "FEFF 0B13 0B21 0B3C 0B3F 0B06"
      const hexOdia = 'FEFF0B130B210B3C0B3F0B06';
      final streamContent = '<$hexOdia> Tj\n';
      final compressed = zlib.encode(latin1.encode(streamContent));

      final fakePdf = <int>[
        ...latin1.encode('1 0 obj\n<< /Length ${compressed.length} /FlateDecode >>\nstream\n'),
        ...compressed,
        ...latin1.encode('\nendstream\nendobj\n'),
      ];

      final pages = PdfBookParser.extractPages(fakePdf);
      expect(pages.isNotEmpty, isTrue);
      expect(pages[0].contains('ଓଡ଼ିଆ'), isTrue);
    });

    test('extracts hex tokens inside TJ arrays', () {
      // TJ array with mixed literal and hex: [(Hello ) -50 <4F646961>] TJ
      final streamContent = '[(Hello ) -50 <4F646961>] TJ\n';
      final compressed = zlib.encode(latin1.encode(streamContent));

      final fakePdf = <int>[
        ...latin1.encode('1 0 obj\n<< /Length ${compressed.length} /FlateDecode >>\nstream\n'),
        ...compressed,
        ...latin1.encode('\nendstream\nendobj\n'),
      ];

      final pages = PdfBookParser.extractPages(fakePdf);
      expect(pages.isNotEmpty, isTrue);
      expect(pages[0].contains('Hello Odia'), isTrue);
    });
  });
}
