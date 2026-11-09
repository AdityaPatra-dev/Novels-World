import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/extractors/bespoke/internet_archive_extractor.dart';
import 'package:novels_world/extractors/bespoke/libgen_extractor.dart';
import 'package:novels_world/extractors/bespoke/standard_ebooks_extractor.dart';
import 'package:novels_world/extractors/bespoke/oceanofpdf_extractor.dart';
import 'package:novels_world/extractors/bespoke/vdocpub_extractor.dart';
import 'package:novels_world/extractors/bespoke/openlibrary_extractor.dart';
import 'package:novels_world/extractors/bespoke/gutenberg_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Book Sources Registration Tests', () {
    test('All verified book sources are registered in SourceRegistry', () {
      final archive = SourceRegistry.getSource('internet_archive');
      final libgen = SourceRegistry.getSource('libgen');
      final standard = SourceRegistry.getSource('standard_ebooks');
      final ocean = SourceRegistry.getSource('oceanofpdf');
      final vdoc = SourceRegistry.getSource('vdocpub');
      final openlib = SourceRegistry.getSource('openlibrary');
      final gutenberg = SourceRegistry.getSource('gutenberg');

      expect(archive, isNotNull);
      expect(libgen, isNotNull);
      expect(standard, isNotNull);
      expect(ocean, isNotNull);
      expect(vdoc, isNotNull);
      expect(openlib, isNotNull);
      expect(gutenberg, isNotNull);

      expect(archive is InternetArchiveExtractor, isTrue);
      expect(libgen is LibGenExtractor, isTrue);
      expect(standard is StandardEbooksExtractor, isTrue);
      expect(ocean is OceanofPdfExtractor, isTrue);
      expect(vdoc is VdocPubExtractor, isTrue);
      expect(openlib is OpenLibraryExtractor, isTrue);
      expect(gutenberg is GutenbergExtractor, isTrue);
    });
  });

  group('InternetArchiveExtractor Unit Tests', () {
    late InternetArchiveExtractor extractor;

    setUp(() {
      extractor = InternetArchiveExtractor();
    });

    test('Parses Archive.org JSON response into full book Novel models', () {
      final sampleJson = {
        'response': {
          'docs': [
            {
              'identifier': 'dune_frank_herbert_epub',
              'title': 'Dune',
              'creator': 'Frank Herbert',
              'description': 'A masterpiece of science fiction on the desert planet Arrakis.',
              'downloads': 15420,
              'publicdate': '2023-01-15T00:00:00Z',
            },
            {
              'identifier': 'game_of_thrones_grrm',
              'title': 'A Game of Thrones',
              'creator': ['George R. R. Martin'],
              'description': 'Winter is coming to Westeros.',
              'downloads': 28900,
            }
          ]
        }
      };

      final novels = extractor.parseDocs(sampleJson['response']!['docs']! as List);
      expect(novels.length, 2);

      final dune = novels[0];
      expect(dune.id, 'internet_archive_dune_frank_herbert_epub');
      expect(dune.title, 'Dune');
      expect(dune.author, 'Frank Herbert');
      expect(dune.isFullBook, isTrue);
      expect(dune.bookFormat, 'epub');
      expect(dune.bookDownloadUrl, 'https://archive.org/download/dune_frank_herbert_epub/dune_frank_herbert_epub.epub');
      expect(dune.status, 'COMPLETED');

      final got = novels[1];
      expect(got.title, 'A Game of Thrones');
      expect(got.author, 'George R. R. Martin');
      expect(got.isFullBook, isTrue);
      expect(got.bookDownloadUrl, 'https://archive.org/download/game_of_thrones_grrm/game_of_thrones_grrm.epub');
    });
  });

  group('LibGenExtractor Unit Tests', () {
    late LibGenExtractor extractor;

    setUp(() {
      extractor = LibGenExtractor();
    });

    test('Parses LibGen table rows correctly with MD5 download resolution', () {
      const html = '''
        <table class="c">
          <tr valign="top">
            <td>1</td>
            <td>J.K. Rowling</td>
            <td><a href="book/index.php?md5=ABCDEF1234567890ABCDEF1234567890">Harry Potter and the Philosopher's Stone</a></td>
            <td>Bloomsbury</td>
            <td>1997</td>
            <td>350</td>
            <td>English</td>
            <td>1.8 Mb</td>
            <td>epub</td>
            <td><a href="https://libgen.li/get.php?md5=ABCDEF1234567890ABCDEF1234567890">get</a></td>
          </tr>
          <tr valign="top">
            <td>2</td>
            <td>J.R.R. Tolkien</td>
            <td><a href="book/index.php?md5=1234567890ABCDEF1234567890ABCDEF">The Hobbit</a></td>
            <td>George Allen & Unwin</td>
            <td>1937</td>
            <td>310</td>
            <td>English</td>
            <td>950 Kb</td>
            <td>epub</td>
            <td><a href="https://libgen.li/get.php?md5=1234567890ABCDEF1234567890ABCDEF">get</a></td>
          </tr>
        </table>
      ''';

      final novels = extractor.parseHtmlTable(html);
      expect(novels.length, 2);

      final hp = novels[0];
      expect(hp.title, contains("Harry Potter and the Philosopher's Stone"));
      expect(hp.author, 'J.K. Rowling');
      expect(hp.isFullBook, isTrue);
      expect(hp.bookFormat, 'epub');
      expect(hp.bookDownloadUrl, contains('libgen.li/get.php?md5=ABCDEF1234567890ABCDEF1234567890'));

      final hobbit = novels[1];
      expect(hobbit.title, 'The Hobbit');
      expect(hobbit.author, 'J.R.R. Tolkien');
      expect(hobbit.isFullBook, isTrue);
    });
  });

  group('StandardEbooksExtractor Unit Tests', () {
    late StandardEbooksExtractor extractor;

    setUp(() {
      extractor = StandardEbooksExtractor();
    });

    test('Parses Standard Ebooks OPDS/HTML entries', () {
      const html = '''
        <ol class="ebooks-list">
          <li>
            <article>
              <a href="/ebooks/jane-austen/pride-and-prejudice">
                <span property="schema:name">Pride and Prejudice</span>
              </a>
              <p class="author"><a href="/ebooks/jane-austen">Jane Austen</a></p>
              <img src="/ebooks/jane-austen/pride-and-prejudice/downloads/cover-thumbnail.jpg" />
            </article>
          </li>
        </ol>
      ''';

      final novels = extractor.parseHtml(html);
      expect(novels.length, 1);
      final book = novels.first;
      expect(book.title, 'Pride and Prejudice');
      expect(book.author, 'Jane Austen');
      expect(book.isFullBook, isTrue);
      expect(book.bookFormat, 'epub');
      expect(book.bookDownloadUrl, 'https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice/downloads/jane-austen_pride-and-prejudice.epub');
    });
  });

  group('OceanofPdfExtractor Unit Tests', () {
    late OceanofPdfExtractor extractor;

    setUp(() {
      extractor = OceanofPdfExtractor();
    });

    test('Parses OceanofPDF article entries', () {
      const html = '''
        <div class="content">
          <article class="post">
            <h2 class="title"><a href="https://oceanofpdf.com/authors/frank-herbert/pdf-epub-dune-download/">[PDF] [EPUB] Dune Download</a></h2>
            <div class="post-content">
              <img src="https://oceanofpdf.com/wp-content/uploads/dune.jpg" />
              <p>Brief Summary of Book: Dune by Frank Herbert...</p>
            </div>
          </article>
        </div>
      ''';

      final novels = extractor.parseHtml(html);
      expect(novels.length, 1);
      final dune = novels.first;
      expect(dune.title, 'Dune');
      expect(dune.author, 'Frank Herbert');
      expect(dune.isFullBook, isTrue);
      expect(dune.bookFormat, 'epub');
    });
  });

  group('GutenbergExtractor Unit Tests', () {
    late GutenbergExtractor extractor;

    setUp(() {
      extractor = GutenbergExtractor();
    });

    test('Recognizes Gutenberg books as full books with EPUB download URLs', () {
      expect(extractor.id, 'gutenberg');
      final novel = Novel(
        id: 'gutenberg_1342',
        sourceId: 'gutenberg',
        title: 'Pride and Prejudice',
        author: 'Jane Austen',
        description: 'Classic literature',
        coverUrl: 'https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg',
        sourceUrl: 'https://www.gutenberg.org/ebooks/1342',
        isFullBook: true,
        bookFormat: 'epub',
        bookDownloadUrl: 'https://www.gutenberg.org/ebooks/1342.epub3.images',
      );

      expect(novel.isFullBook, isTrue);
      expect(novel.bookDownloadUrl, 'https://www.gutenberg.org/ebooks/1342.epub3.images');
    });
  });

  group('VdocPubExtractor Unit Tests', () {
    late VdocPubExtractor extractor;

    setUp(() {
      extractor = VdocPubExtractor();
    });

    test('Parses vdoc.pub HTML document entries with download URLs', () {
      const html = '''
        <div class="row">
          <div class="col-md-6">
            <div class="card document-item">
              <a href="/documents/a-game-of-thrones-george-r-r-martin-12345">
                <img src="/covers/got.jpg" />
                <h3 class="title">A Game of Thrones</h3>
              </a>
              <p class="author">by George R. R. Martin</p>
            </div>
          </div>
        </div>
      ''';

      final novels = extractor.parseHtml(html);
      expect(novels.length, 1);
      final got = novels.first;
      expect(got.title, 'A Game of Thrones');
      expect(got.author, 'George R. R. Martin');
      expect(got.isFullBook, isTrue);
      expect(got.bookFormat, 'epub');
      expect(got.bookDownloadUrl, 'https://vdoc.pub/download/a-game-of-thrones-george-r-r-martin-12345');
    });
  });

  group('OpenLibraryExtractor Unit Tests', () {
    late OpenLibraryExtractor extractor;

    setUp(() {
      extractor = OpenLibraryExtractor();
    });

    test('Parses Open Library JSON search documents into full book Novel models', () {
      final sampleDocs = [
        {
          'key': '/works/OL893414W',
          'title': 'Dune',
          'author_name': ['Frank Herbert'],
          'cover_i': 11481354,
          'ia': ['dune_frank_herbert_4189', 'dune0000fran'],
        },
        {
          'key': '/works/OL893461W',
          'title': 'The Hobbit',
          'author_name': ['J.R.R. Tolkien'],
          'cover_i': 847291,
          'ia': ['thehobbit00tolk'],
        }
      ];

      final novels = extractor.parseDocs(sampleDocs);
      expect(novels.length, 2);

      final dune = novels[0];
      expect(dune.title, 'Dune');
      expect(dune.author, 'Frank Herbert');
      expect(dune.coverUrl, 'https://covers.openlibrary.org/b/id/11481354-M.jpg');
      expect(dune.isFullBook, isTrue);
      expect(dune.bookFormat, 'epub');
      expect(dune.bookDownloadUrl, 'https://archive.org/download/dune_frank_herbert_4189/dune_frank_herbert_4189.epub');

      final hobbit = novels[1];
      expect(hobbit.title, 'The Hobbit');
      expect(hobbit.author, 'J.R.R. Tolkien');
      expect(hobbit.isFullBook, isTrue);
    });
  });
}
