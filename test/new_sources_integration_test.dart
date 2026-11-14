import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/bespoke/woopread_extractor.dart';
import 'package:novels_world/extractors/bespoke/relibrary_extractor.dart';
import 'package:novels_world/extractors/bespoke/clarkesworld_extractor.dart';
import 'package:novels_world/extractors/bespoke/lightspeed_extractor.dart';
import 'package:novels_world/extractors/bespoke/eastoftheweb_extractor.dart';
import 'package:novels_world/extractors/bespoke/uncanny_extractor.dart';
import 'package:novels_world/extractors/bespoke/strangehorizons_extractor.dart';
import 'package:novels_world/extractors/bespoke/fadedpage_extractor.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  group('WoopReadExtractor Unit Tests', () {
    late WoopReadExtractor extractor;

    setUp(() {
      extractor = WoopReadExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('woopread');
      expect(source, isNotNull);
      expect(source!.id, equals('woopread'));
      expect(source.name, equals('Woopread'));
      expect(source.lang, equals('en'));
    });

    test('parseNovelList extracts novels with clean cover URL and title', () {
      const html = '''
      <div>
        <a class="block" href="/series/as-long-as-you-are-happy">
          <div class="relative w-full">
            <img alt="As Long As You Are Happy" class="object-cover" src="/_next/image?url=https%3A%2F%2Fimgcdn.woopread.com%2Fwp-content%2Fuploads%2F2024%2F11%2Fcover_1731659281.webp&amp;w=3840&amp;q=75" />
          </div>
          <h3>As Long As You Are Happy</h3>
        </a>
        <a class="block" href="/series/bastian">
          <img alt="Bastian" src="https://imgcdn.woopread.com/bastian.jpg" />
        </a>
      </div>
      ''';

      final list = extractor.parseNovelList(html);
      expect(list.length, equals(2));
      expect(list[0].title, equals('As Long As You Are Happy'));
      expect(list[0].sourceUrl, equals('https://woopread.com/series/as-long-as-you-are-happy'));
      expect(list[0].coverUrl, equals('https://imgcdn.woopread.com/wp-content/uploads/2024/11/cover_1731659281.webp'));
      expect(list[1].title, equals('Bastian'));
    });

    test('parseNovelDetails extracts title, cover, desc, and author', () {
      const html = '''
      <html>
        <head>
          <meta property="og:title" content="As Long As You Are Happy" />
          <meta property="og:description" content="Living a life where she could not die. Rhett found herself in the slums." />
          <meta property="og:image" content="https://imgcdn.woopread.com/cover.webp" />
        </head>
        <body>
          <h1>As Long As You Are Happy</h1>
          <a href="/author/solche">Solche</a>
          <a href="/genre/romance">Romance</a>
          <a href="/genre/fantasy">Fantasy</a>
          <p class="text-text">Living a life where she could not die. Rhett found herself in the slums.</p>
        </body>
      </html>
      ''';

      final novel = extractor.parseNovelDetails('https://woopread.com/series/as-long-as-you-are-happy', html);
      expect(novel.title, equals('As Long As You Are Happy'));
      expect(novel.author, equals('Solche'));
      expect(novel.genres, contains('Romance'));
      expect(novel.genres, contains('Fantasy'));
      expect(novel.description, contains('Living a life where she could not die'));
    });

    test('parseChapterList extracts and sorts chapter URLs', () {
      const html = '''
      <div>
        <a href="/series/sample-novel/chapter-2">Chapter 2 2 days ago</a>
        <a href="/series/sample-novel/chapter-1">Chapter 1 3 days ago</a>
        <a href="/series/sample-novel/chapter-10">Chapter 10 1 hour ago</a>
      </div>
      ''';

      final chapters = extractor.parseChapterList('https://woopread.com/series/sample-novel', html);
      expect(chapters.length, equals(3));
      // Should be sorted ascending
      expect(chapters[0].title, equals('Chapter 1'));
      expect(chapters[0].url, equals('https://woopread.com/series/sample-novel/chapter-1'));
      expect(chapters[1].title, equals('Chapter 2'));
      expect(chapters[2].title, equals('Chapter 10'));
    });

    test('parseChapterContent cleans paragraphs in text-text', () {
      const html = '''
      <html>
        <body>
          <h1>Chapter 1: The Beginning</h1>
          <div class="text-text">
            <script>alert("ad");</script>
            <p>It had been days of misery.</p>
            <p>She closed her eyes and waited for the night to pass.</p>
            <div class="adsbygoogle">Ad content</div>
          </div>
        </body>
      </html>
      ''';

      final content = extractor.parseChapterContent(
        'https://woopread.com/series/sample-novel/chapter-1',
        html,
      );
      expect(content.title, equals('Chapter 1: The Beginning'));
      expect(content.paragraphs.length, equals(2));
      expect(content.paragraphs[0], equals('It had been days of misery.'));
      expect(content.paragraphs[1], equals('She closed her eyes and waited for the night to pass.'));
    });
  });

  group('ReLibraryExtractor Unit Tests', () {
    late ReLibraryExtractor extractor;

    setUp(() {
      extractor = ReLibraryExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('relibrary');
      expect(source, isNotNull);
      expect(source!.id, equals('relibrary'));
      expect(source.name, equals('Re:Library'));
      expect(source.lang, equals('en'));
    });

    test('parseNovelList extracts novels from repi-item articles', () {
      const html = '''
      <div>
        <article class="repi-item">
          <a href="https://re-library.com/translations/alchemist-startover/">Alchemist Startover</a>
          <img src="https://re-library.com/wp-content/uploads/cover.jpg" />
        </article>
        <article class="repi-item">
          <a href="https://re-library.com/translations/blue-sky/">Blue Sky</a>
          <img src="https://re-library.com/wp-content/uploads/blue.jpg" />
        </article>
      </div>
      ''';

      final list = extractor.parseNovelList(html);
      expect(list.length, equals(2));
      expect(list[0].title, equals('Alchemist Startover'));
      expect(list[0].sourceUrl, equals('https://re-library.com/translations/alchemist-startover/'));
      expect(list[0].coverUrl, equals('https://re-library.com/wp-content/uploads/cover.jpg'));
    });

    test('parseNovelDetails extracts title, author, and description', () {
      const html = '''
      <html>
        <head>
          <meta property="og:title" content="Alchemist Startover - Re:Library" />
          <meta property="og:image" content="https://re-library.com/cover.jpg" />
        </head>
        <body>
          <h1 class="entry-title">Alchemist Startover</h1>
          <div class="entry-content">
            <p>Author: Eltria</p>
            <p>Translator: Tunandir</p>
            <p>Once an orphan turned street child, the genius alchemist walked a life of misfortune.</p>
            <p><a href="https://re-library.com/translations/alchemist-startover/volume-1/chapter-1/">Chapter 1</a></p>
          </div>
          <a rel="tag" href="https://re-library.com/tag/fantasy/">Fantasy</a>
        </body>
      </html>
      ''';

      final novel = extractor.parseNovelDetails('https://re-library.com/translations/alchemist-startover/', html);
      expect(novel.title, equals('Alchemist Startover'));
      expect(novel.author, equals('Eltria'));
      expect(novel.description, contains('Once an orphan turned street child'));
      expect(novel.genres, contains('Fantasy'));
    });

    test('parseChapterList extracts chapter links and filters non-chapters', () {
      const html = '''
      <div class="entry-content">
        <a href="https://www.novelupdates.com/series/alchemist-startover/">Novel Updates</a>
        <a href="https://re-library.com/translations/alchemist-startover/volume-1/chapter-1-life-and-death/">Chapter 1: Life and Death</a>
        <a href="https://re-library.com/translations/alchemist-startover/volume-1/chapter-2-death-penalty/">Chapter 2: Death Penalty</a>
        <a href="https://re-library.com/translations/alchemist-startover/?share=facebook">Facebook</a>
      </div>
      ''';

      final chapters = extractor.parseChapterList('https://re-library.com/translations/alchemist-startover/', html);
      expect(chapters.length, equals(2));
      expect(chapters[0].title, equals('Chapter 1: Life and Death'));
      expect(chapters[0].chapterNumber, equals(1.0));
      expect(chapters[1].title, equals('Chapter 2: Death Penalty'));
      expect(chapters[1].chapterNumber, equals(2.0));
    });

    test('parseChapterContent removes nav, ads, and cleans narrative', () {
      const html = '''
      <div class="entry-content">
        <p>Leave a comment</p>
        <p>Next ⇒⌈ Index ⌋</p>
        <p>My body drifted in warm water.</p>
        <p>“I wish I could sleep like this forever…”</p>
        <div class="sharedaddy">Share buttons</div>
      </div>
      ''';

      final content = extractor.parseChapterContent('https://re-library.com/chapter-1', html);
      expect(content.paragraphs.length, equals(2));
      expect(content.paragraphs[0], equals('My body drifted in warm water.'));
      expect(content.paragraphs[1], equals('"I wish I could sleep like this forever..."'));
    });
  });

  group('ClarkesworldExtractor Unit Tests', () {
    late ClarkesworldExtractor extractor;

    setUp(() {
      extractor = ClarkesworldExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('clarkesworld');
      expect(source, isNotNull);
      expect(source!.id, equals('clarkesworld'));
      expect(source.name, equals('Clarkesworld'));
    });

    test('parseNovelList extracts stories from h2 links', () {
      const html = '''
      <div>
        <article>
          <h2><a href="https://clarkesworldmagazine.com/yang_11_26/">Twenty-Two Steps to Become Us</a></h2>
          <p class="story-author">by Hannah Yang</p>
        </article>
        <article>
          <h2><a href="https://clarkesworldmagazine.com/kim_11_26/">The Meat Market</a></h2>
          <p class="story-author">by J. Kim</p>
        </article>
      </div>
      ''';

      final list = extractor.parseNovelList(html);
      expect(list.length, equals(2));
      expect(list[0].title, equals('Twenty-Two Steps to Become Us'));
      expect(list[0].author, equals('Hannah Yang'));
      expect(list[0].sourceUrl, equals('https://clarkesworldmagazine.com/yang_11_26/'));
      expect(list[1].title, equals('The Meat Market'));
    });

    test('parseNovelDetails extracts title and author from story page', () {
      const html = '''
      <html>
        <head>
          <title>Twenty-Two Steps to Become Us by Hannah Yang : Clarkesworld Magazine</title>
          <meta property="og:title" content="Twenty-Two Steps to Become Us by Hannah Yang : Clarkesworld Magazine" />
        </head>
        <body>
          <p class="story-author">by Hannah Yang</p>
          <p class="story-description">5490 words, short story</p>
          <div class="story-text">
            <p>There are a dozen copies of my mother playing Candy Crush in the living room.</p>
          </div>
        </body>
      </html>
      ''';

      final novel = extractor.parseNovelDetails('https://clarkesworldmagazine.com/yang_11_26/', html);
      expect(novel.title, equals('Twenty-Two Steps to Become Us'));
      expect(novel.author, equals('Hannah Yang'));
      expect(novel.description, equals('5490 words, short story'));
      expect(novel.genres, contains('Science Fiction'));
    });

    test('parseChapterContent strips author bio and extracts narrative', () {
      const html = '''
      <html>
        <head>
          <title>Twenty-Two Steps to Become Us by Hannah Yang : Clarkesworld Magazine</title>
        </head>
        <body>
          <div class="story-text">
            <p class="issue-heading">Issue 242 – November 2026</p>
            <p class="story-author">by Hannah Yang</p>
            <p class="audio-text">AUDIO VERSION</p>
            <p>There are a dozen copies of my mother playing Candy Crush in the living room.</p>
            <p>The Learners have her hooded eyelids, which they keep firm.</p>
            <div class="author-bio">Hannah Yang is a speculative fiction author.</div>
          </div>
        </body>
      </html>
      ''';

      final content = extractor.parseChapterContent('https://clarkesworldmagazine.com/yang_11_26/', html);
      expect(content.title, equals('Twenty-Two Steps to Become Us'));
      expect(content.paragraphs.length, equals(2));
      expect(content.paragraphs[0], equals('There are a dozen copies of my mother playing Candy Crush in the living room.'));
      expect(content.paragraphs[1], equals('The Learners have her hooded eyelids, which they keep firm.'));
    });
  });

  group('LightspeedExtractor Unit Tests', () {
    late LightspeedExtractor extractor;

    setUp(() {
      extractor = LightspeedExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('lightspeed');
      expect(source, isNotNull);
      expect(source!.id, equals('lightspeed'));
      expect(source.name, equals('Lightspeed'));
    });

    test('parseNovelList extracts fiction items', () {
      const html = '''
      <div>
        <h2><a href="https://www.lightspeedmagazine.com/fiction/the-tongue-that-makes-the-mountain-sing/">The Tongue That Makes the Mountain Sing</a></h2>
        <h2><a href="https://www.lightspeedmagazine.com/fiction/repentance-in-blue/">Repentance in Blue</a></h2>
      </div>
      ''';

      final list = extractor.parseNovelList(html);
      expect(list.length, equals(2));
      expect(list[0].title, equals('The Tongue That Makes the Mountain Sing'));
      expect(list[0].sourceUrl, equals('https://www.lightspeedmagazine.com/fiction/the-tongue-that-makes-the-mountain-sing/'));
      expect(list[1].title, equals('Repentance in Blue'));
    });

    test('parseNovelDetails extracts title, author, and description', () {
      const html = '''
      <html>
        <head>
          <meta property="og:title" content="The Tongue That Makes the Mountain Sing - Lightspeed Magazine" />
          <meta property="og:image" content="https://www.lightspeedmagazine.com/cover.png" />
        </head>
        <body>
          <h1 class="posttitle">The Tongue That Makes the Mountain Sing</h1>
          <h2>Nibedita Sen</h2>
          <div class="entry-content">
            <p>The Dartmouth Speculative Fiction Project paired faculty members.</p>
          </div>
        </body>
      </html>
      ''';

      final novel = extractor.parseNovelDetails('https://www.lightspeedmagazine.com/fiction/sample/', html);
      expect(novel.title, equals('The Tongue That Makes the Mountain Sing'));
      expect(novel.author, equals('Nibedita Sen'));
      expect(novel.description, contains('Dartmouth Speculative Fiction'));
    });

    test('parseChapterContent cleans entry-content', () {
      const html = '''
      <div class="entry-content">
        <p>The Dartmouth Speculative Fiction Project paired eight faculty-members.</p>
        <p>They climbed the rocky summit together.</p>
        <p>Subscribe to Lightspeed for more great stories.</p>
      </div>
      ''';

      final content = extractor.parseChapterContent('https://www.lightspeedmagazine.com/fiction/sample/', html);
      expect(content.paragraphs.length, equals(2));
      expect(content.paragraphs[0], equals('The Dartmouth Speculative Fiction Project paired eight faculty-members.'));
      expect(content.paragraphs[1], equals('They climbed the rocky summit together.'));
    });
  });

  group('EastOfTheWebExtractor Unit Tests', () {
    late EastOfTheWebExtractor extractor;

    setUp(() {
      extractor = EastOfTheWebExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('eastoftheweb');
      expect(source, isNotNull);
      expect(source!.id, equals('eastoftheweb'));
      expect(source.name, equals('East of the Web'));
    });

    test('parseNovelList extracts short story links', () {
      const html = '''
      <div>
        <a href="/short-stories/UBooks/WildWeed1379.shtml">Wild Weeds</a>
        <a href="/short-stories/UBooks/LookBack1411.shtml">Looking Back</a>
      </div>
      ''';

      final list = extractor.parseNovelList(html);
      expect(list.length, equals(2));
      expect(list[0].title, equals('Wild Weeds'));
      expect(list[0].sourceUrl, equals('https://www.eastoftheweb.com/short-stories/UBooks/WildWeed1379.shtml'));
      expect(list[1].title, equals('Looking Back'));
    });

    test('parseNovelDetails extracts title and author', () {
      const html = '''
      <html>
        <body>
          <h1>Wild Weeds</h1>
          <div class="field--name-field-author">Douglas Young</div>
          <div class="page-story-body">
            <p>The dinner invitation was totally unexpected since Josiah had not heard from him.</p>
          </div>
        </body>
      </html>
      ''';

      final novel = extractor.parseNovelDetails('https://www.eastoftheweb.com/short-stories/UBooks/WildWeed1379.shtml', html);
      expect(novel.title, equals('Wild Weeds'));
      expect(novel.author, equals('Douglas Young'));
      expect(novel.description, contains('The dinner invitation was totally unexpected'));
    });

    test('parseChapterContent cleans narrative paragraphs', () {
      const html = '''
      <div class="page-story-body">
        <div class="block-story-left-links-block">View Comments</div>
        <p>The dinner invitation was totally unexpected.</p>
        <p>Upon getting his business degree, Josiah remained in town.</p>
      </div>
      ''';

      final content = extractor.parseChapterContent('https://www.eastoftheweb.com/sample', html);
      expect(content.paragraphs.length, equals(2));
      expect(content.paragraphs[0], equals('The dinner invitation was totally unexpected.'));
      expect(content.paragraphs[1], equals('Upon getting his business degree, Josiah remained in town.'));
    });
  });

  group('UncannyExtractor Unit Tests', () {
    late UncannyExtractor extractor;

    setUp(() {
      extractor = UncannyExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('uncannymagazine');
      expect(source, isNotNull);
      expect(source!.id, equals('uncannymagazine'));
      expect(source.name, equals('Uncanny Magazine'));
    });

    test('parseNovelList extracts article links', () {
      const html = '''
      <div>
        <h2 class="entry-title"><a href="https://www.uncannymagazine.com/article/the-godless/">The Godless</a></h2>
        <h2 class="entry-title"><a href="https://www.uncannymagazine.com/article/home-body/">Home/Body</a></h2>
      </div>
      ''';

      final list = extractor.parseNovelList(html);
      expect(list.length, equals(2));
      expect(list[0].title, equals('The Godless'));
      expect(list[0].sourceUrl, equals('https://www.uncannymagazine.com/article/the-godless/'));
      expect(list[1].title, equals('Home/Body'));
    });

    test('parseNovelDetails extracts title and author', () {
      const html = '''
      <html>
        <head>
          <meta property="og:title" content="The Godless - Uncanny Magazine" />
        </head>
        <body>
          <h2 class="entry-title">The Godless</h2>
          <h2>Lavie Tidhar</h2>
          <div class="entry-content">
            <p>The desert was vast and silent beneath the copper stars.</p>
          </div>
        </body>
      </html>
      ''';

      final novel = extractor.parseNovelDetails('https://www.uncannymagazine.com/article/the-godless/', html);
      expect(novel.title, equals('The Godless'));
      expect(novel.author, equals('Lavie Tidhar'));
      expect(novel.description, contains('The desert was vast and silent'));
    });

    test('parseChapterContent cleans entry-content', () {
      const html = '''
      <div class="entry-content">
        <h3 class="section_header">Listen to the Podcast</h3>
        <p>The desert was vast and silent beneath the copper stars.</p>
        <p>A solitary traveler walked across the ancient sands.</p>
        <p>Buy This Issue on Amazon</p>
      </div>
      ''';

      final content = extractor.parseChapterContent('https://www.uncannymagazine.com/article/the-godless/', html);
      expect(content.paragraphs.length, equals(2));
      expect(content.paragraphs[0], equals('The desert was vast and silent beneath the copper stars.'));
      expect(content.paragraphs[1], equals('A solitary traveler walked across the ancient sands.'));
    });
  });

  group('StrangeHorizonsExtractor Unit Tests', () {
    late StrangeHorizonsExtractor extractor;

    setUp(() {
      extractor = StrangeHorizonsExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('strangehorizons');
      expect(source, isNotNull);
      expect(source!.id, equals('strangehorizons'));
      expect(source.name, equals('Strange Horizons'));
    });

    test('parseNovelList extracts fiction links', () {
      const html = '''
      <div>
        <a href="https://strangehorizons.com/wordpress/fiction/welcome-home/">Welcome Home</a>
        <a href="https://strangehorizons.com/wordpress/fiction/the-ghost-station/">The Ghost Station</a>
      </div>
      ''';

      final list = extractor.parseNovelList(html);
      expect(list.length, equals(2));
      expect(list[0].title, equals('Welcome Home'));
      expect(list[0].sourceUrl, equals('https://strangehorizons.com/wordpress/fiction/welcome-home/'));
      expect(list[1].title, equals('The Ghost Station'));
    });

    test('parseNovelDetails extracts title and author', () {
      const html = '''
      <html>
        <head>
          <title>Strange Horizons - Welcome Home By Andrew Kozma</title>
        </head>
        <body>
          <h1 class="entry-title">Welcome Home</h1>
          <div class="author">By Andrew Kozma</div>
          <div class="sizeable-content">
            <p>I was having a bad day and so I entered Harriet’s Café.</p>
          </div>
        </body>
      </html>
      ''';

      final novel = extractor.parseNovelDetails('https://strangehorizons.com/wordpress/fiction/welcome-home/', html);
      expect(novel.title, equals('Welcome Home'));
      expect(novel.author, equals('Andrew Kozma'));
      expect(novel.description, contains('I was having a bad day'));
    });

    test('parseChapterContent cleans narrative in sizeable-content', () {
      const html = '''
      <div class="sizeable-content">
        <p>Content warning: Show warnings</p>
        <p>I was having a bad day—okay, a bad life—and so I entered Harriet’s Café.</p>
        <p>There was a solitary barista behind the counter.</p>
      </div>
      ''';

      final content = extractor.parseChapterContent('https://strangehorizons.com/sample', html);
      expect(content.paragraphs.length, equals(2));
      expect(content.paragraphs[0], contains("Harriet's Café"));
      expect(content.paragraphs[1], contains('solitary barista'));
    });
  });

  group('FadedPageExtractor Unit Tests', () {
    late FadedPageExtractor extractor;

    setUp(() {
      extractor = FadedPageExtractor();
    });

    test('Source registration is active', () {
      final source = SourceRegistry.getSource('fadedpage');
      expect(source, isNotNull);
      expect(source!.id, equals('fadedpage'));
      expect(source.name, equals('Faded Page'));
      expect(source.lang, equals('en'));
    });

    test('Full book properties are configured', () async {
      final chapters = await extractor.getChapterList('https://www.fadedpage.com/showbook.php?pid=20190433');
      expect(chapters.isNotEmpty, isTrue);
      expect(chapters.first.title, contains('Full Book'));
      expect(chapters.first.url, contains('link.php?file=20190433.epub'));
    });
  });

  group('Madara New Sources Registration Tests', () {
    test('BoxNovel and RainOfSnow registered in registry', () {
      final boxnovel = SourceRegistry.getSource('boxnovel');
      expect(boxnovel, isNotNull);
      expect(boxnovel!.id, equals('boxnovel'));
      expect(boxnovel.baseUrl, equals('https://boxnovel.com'));

      final rainofsnow = SourceRegistry.getSource('rainofsnow');
      expect(rainofsnow, isNotNull);
      expect(rainofsnow!.id, equals('rainofsnow'));
      expect(rainofsnow.baseUrl, equals('https://rainofsnow.com'));
    });
  });
}
