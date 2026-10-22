import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/lightnovelwp_extractor.dart';
import 'package:novels_world/extractors/novelfull_extractor.dart';
import 'package:novels_world/extractors/bespoke/royalroad_extractor.dart';
import 'package:novels_world/extractors/bespoke/scribblehub_extractor.dart';
import 'package:novels_world/extractors/readwn_extractor.dart';
import 'package:novels_world/extractors/fictioneer_extractor.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  group('LightNovelWpExtractor Tests', () {
    late LightNovelWpExtractor extractor;

    setUp(() {
      extractor = LightNovelWpExtractor(
        id: 'test_lnwp',
        name: 'Test LightNovelWP',
        baseUrl: 'https://example-lnwp.com',
      );
    });

    test('parseNovelList extracts novels correctly from LightNovelWP HTML', () {
      const html = '''
        <div class="listupd">
          <div class="bsx">
            <a href="https://example-lnwp.com/series/shadow-monarch/" title="Shadow Monarch">
              <div class="limit">
                <img src="https://example-lnwp.com/covers/shadow.jpg" alt="Shadow Monarch" />
              </div>
              <div class="bigor">
                <div class="tt">Shadow Monarch</div>
                <div class="status">Ongoing</div>
              </div>
            </a>
          </div>
          <div class="bsx">
            <a href="https://example-lnwp.com/series/dragon-king/" title="Dragon King">
              <img src="https://example-lnwp.com/covers/dragon.jpg" />
              <div class="tt">Dragon King</div>
            </a>
          </div>
        </div>
      ''';

      final novels = extractor.parseNovelList(html);
      expect(novels.length, 2);
      expect(novels[0].id, 'test_lnwp_shadow-monarch');
      expect(novels[0].title, 'Shadow Monarch');
      expect(novels[0].coverUrl, 'https://example-lnwp.com/covers/shadow.jpg');
      expect(novels[1].title, 'Dragon King');
    });

    test('parseNovelDetails extracts metadata correctly', () {
      const html = '''
        <div class="postbody">
          <h1 class="entry-title">The Legendary Mechanic</h1>
          <div class="thumbook">
            <div class="thumb">
              <img src="https://example-lnwp.com/covers/mechanic.jpg" />
            </div>
          </div>
          <div class="infox">
            <div class="spe">
              <span><b>Author:</b> Chocolion</span>
              <span><b>Status:</b> Completed</span>
            </div>
            <div class="genretags">
              <a href="#">Action</a>
              <a href="#">Sci-Fi</a>
              <a href="#">LitRPG</a>
            </div>
          </div>
          <div class="entry-content" itemprop="description">
            <p>What happens when a gamer wakes up in the game he spent 10 years playing?</p>
            <div class="sharedaddy">Share this</div>
          </div>
        </div>
      ''';

      final novel = extractor.parseNovelDetails('https://example-lnwp.com/series/the-legendary-mechanic/', html);
      expect(novel.title, 'The Legendary Mechanic');
      expect(novel.author, 'Chocolion');
      expect(novel.status, 'COMPLETED');
      expect(novel.genres, containsAll(['Action', 'Sci-Fi', 'LitRPG']));
      expect(novel.coverUrl, 'https://example-lnwp.com/covers/mechanic.jpg');
      expect(novel.description, contains('What happens when a gamer wakes up'));
      expect(novel.description, isNot(contains('Share this')));
    });

    test('parseChapterList extracts and orders chapters ascending', () {
      const html = '''
        <div class="eplister" id="chapterlist">
          <ul class="clstyle">
            <li>
              <a href="https://example-lnwp.com/series/mech-chapter-2/">
                <span class="epl-num">Chapter 2</span>
                <span class="epl-title">Starting from Scratch</span>
                <span class="epl-date">October 10, 2026</span>
              </a>
            </li>
            <li>
              <a href="https://example-lnwp.com/series/mech-chapter-1/">
                <span class="epl-num">Chapter 1</span>
                <span class="epl-title">Rebirth in the Laboratory</span>
                <span class="epl-date">October 09, 2026</span>
              </a>
            </li>
          </ul>
        </div>
      ''';

      final chapters = extractor.parseChapterList('https://example-lnwp.com/series/mech/', html);
      expect(chapters.length, 2);
      // Verify reversed so chapter 1 is first
      expect(chapters[0].title, 'Chapter 1: Rebirth in the Laboratory');
      expect(chapters[0].chapterNumber, 1.0);
      expect(chapters[1].title, 'Chapter 2: Starting from Scratch');
      expect(chapters[1].chapterNumber, 2.0);
    });

    test('parseChapterContent cleans scripts and ads', () {
      const html = '''
        <div class="epcontent entry-content">
          <script>console.log("ad");</script>
          <p>Han Xiao opened his eyes to cold steel and the smell of grease.</p>
          <div class="code-block adsbygoogle">Advertisement</div>
          <p>The system interface floated quietly before his retina.</p>
          <div class="navigation"><a href="#">Next Chapter</a></div>
        </div>
      ''';

      final content = extractor.parseChapterContent('https://example-lnwp.com/mech-chapter-1/', html);
      expect(content.paragraphs.length, 2);
      expect(content.paragraphs[0], 'Han Xiao opened his eyes to cold steel and the smell of grease.');
      expect(content.paragraphs[1], 'The system interface floated quietly before his retina.');
      expect(content.rawText, isNot(contains('Advertisement')));
      expect(content.rawText, isNot(contains('Next Chapter')));
    });
  });

  group('NovelFullExtractor Tests', () {
    late NovelFullExtractor extractor;

    setUp(() {
      extractor = NovelFullExtractor(
        id: 'test_novelfull',
        name: 'Test NovelFull',
        baseUrl: 'https://novelfull.test',
      );
    });

    test('parseNovelList extracts aggregator items', () {
      const html = '''
        <div class="list list-novel col-xs-12">
          <div class="row">
            <div class="col-xs-3">
              <img src="/media/lord-of-mysteries.jpg" class="cover" alt="Lord of Mysteries">
            </div>
            <div class="col-xs-7">
              <h3 class="novel-title"><a href="/lord-of-mysteries.html">Lord of the Mysteries</a></h3>
              <span class="author">Cuttlefish That Loves Diving</span>
            </div>
          </div>
        </div>
      ''';

      final novels = extractor.parseNovelList(html);
      expect(novels.length, 1);
      expect(novels[0].title, 'Lord of the Mysteries');
      expect(novels[0].author, 'Cuttlefish That Loves Diving');
      expect(novels[0].coverUrl, 'https://novelfull.test/media/lord-of-mysteries.jpg');
      expect(novels[0].id, 'test_novelfull_lord-of-mysteries');
    });

    test('parseNovelList extracts items from FreeWebNovel and NovelFire templates', () {
      const html = '''
        <div class="ul-list1">
          <div class="li-row">
            <div class="pic"><a href="/novel/shadow-slave"><img src="/files/cover.jpg" alt="Shadow Slave"></a></div>
            <div class="txt">
              <h3 class="tit"><a href="/novel/shadow-slave" title="Shadow Slave">Shadow Slave</a></h3>
              <div class="right"><em class="e1"><a class="novel" href="#">Guiltythree</a></em></div>
            </div>
          </div>
          <li class="novel-item">
            <a href="/book/reverend-insanity" title="Reverend Insanity">
              <img src="/covers/reverend.jpg" alt="Reverend Insanity">
              <h4 class="novel-title">Reverend Insanity</h4>
            </a>
            <span class="author">Gu Zhen Ren</span>
          </li>
        </div>
      ''';

      final novels = extractor.parseNovelList(html);
      expect(novels.length, 2);
      expect(novels[0].title, 'Shadow Slave');
      expect(novels[0].coverUrl, 'https://novelfull.test/files/cover.jpg');
      expect(novels[1].title, 'Reverend Insanity');
      expect(novels[1].coverUrl, 'https://novelfull.test/covers/reverend.jpg');
    });

    test('parseNovelDetails extracts genres and ongoing status', () {
      const html = '''
        <div class="col-info-desc">
          <h3 class="title">Lord of the Mysteries</h3>
          <div class="info">
            <div><h3>Author:</h3> <a href="/author/cuttlefish">Cuttlefish</a></div>
            <div><h3>Genre:</h3> <a href="/genre/mystery">Mystery</a>, <a href="/genre/fantasy">Fantasy</a></div>
            <div><h3>Status:</h3> <a href="/status/completed">Completed</a></div>
          </div>
          <div class="desc-text">
            <p>With the rising of the red moon, crimson waves rolled across the sky.</p>
          </div>
        </div>
      ''';

      final novel = extractor.parseNovelDetails('https://novelfull.test/lord-of-mysteries.html', html);
      expect(novel.title, 'Lord of the Mysteries');
      expect(novel.author, 'Cuttlefish');
      expect(novel.status, 'COMPLETED');
      expect(novel.genres, containsAll(['Mystery', 'Fantasy']));
      expect(novel.description, contains('With the rising of the red moon'));
    });

    test('parseChapterContent filters aggregator watermark text', () {
      const html = '''
        <div id="chr-content" class="chr-content">
          <p>Klein Moretti awoke with a throbbing headache.</p>
          <p>Find authorized novels in Webnovel, faster updates, better experience.</p>
          <p>He found himself sitting at a wooden desk with a revolver next to his notebook.</p>
          <p>Visit novelfull for more chapters if you find any errors.</p>
        </div>
      ''';

      final content = extractor.parseChapterContent('https://novelfull.test/lord-of-mysteries/chapter-1.html', html);
      expect(content.paragraphs.length, 2);
      expect(content.paragraphs[0], 'Klein Moretti awoke with a throbbing headache.');
      expect(content.paragraphs[1], 'He found himself sitting at a wooden desk with a revolver next to his notebook.');
      expect(content.rawText, isNot(contains('Find authorized novels')));
      expect(content.rawText, isNot(contains('Visit novelfull')));
    });
  });

  group('RoyalRoadExtractor Tests', () {
    late RoyalRoadExtractor extractor;

    setUp(() {
      extractor = RoyalRoadExtractor();
    });

    test('parseNovelList extracts fiction items', () {
      const html = '''
        <div class="fiction-list-item row">
          <div class="col-sm-2">
            <img src="/dist/img/covers/primal-hunter.jpg" />
          </div>
          <div class="col-sm-10">
            <h2 class="fiction-title"><a href="/fiction/36049/the-primal-hunter">The Primal Hunter</a></h2>
            <div class="author"><a href="/profile/101">Zogarth</a></div>
            <div class="tags">
              <a class="fiction-tag" href="#">Action</a>
              <a class="fiction-tag" href="#">Progression</a>
            </div>
          </div>
        </div>
      ''';

      final novels = extractor.parseNovelList(html);
      expect(novels.length, 1);
      expect(novels[0].title, 'The Primal Hunter');
      expect(novels[0].author, 'Zogarth');
      expect(novels[0].id, 'royalroad_36049');
      expect(novels[0].genres, containsAll(['Action', 'Progression']));
    });

    test('parseChapterList extracts chapter table rows', () {
      const html = '''
        <table id="chapters">
          <tbody>
            <tr class="chapter-row" data-url="/fiction/36049/the-primal-hunter/chapter/542918/chapter-1-the-hunt-begins">
              <td>
                <a href="/fiction/36049/the-primal-hunter/chapter/542918/chapter-1-the-hunt-begins">
                  Chapter 1: The Hunt Begins
                </a>
              </td>
              <td class="text-right">
                <time title="2020-09-15 14:00:00">Sep 15, 2020</time>
              </td>
            </tr>
          </tbody>
        </table>
      ''';

      final chapters = extractor.parseChapterList('https://www.royalroad.com/fiction/36049/the-primal-hunter', html);
      expect(chapters.length, 1);
      expect(chapters[0].title, 'Chapter 1: The Hunt Begins');
      expect(chapters[0].chapterNumber, 1.0);
      expect(chapters[0].id, 'royalroad_36049_542918');
      expect(chapters[0].releaseDate, '2020-09-15 14:00:00');
    });

    test('parseChapterContent strips author note portlets', () {
      const html = '''
        <div class="chapter-inner chapter-content">
          <div class="author-note-portlet">Thanks for reading! Check my Patreon.</div>
          <p>Jake sat on his office chair, staring at the monitor.</p>
          <p>Then, the sky cracked like glass.</p>
        </div>
      ''';

      final content = extractor.parseChapterContent(
        'https://www.royalroad.com/fiction/36049/the-primal-hunter/chapter/542918/chapter-1',
        html,
      );
      expect(content.paragraphs.length, 2);
      expect(content.paragraphs[0], 'Jake sat on his office chair, staring at the monitor.');
      expect(content.rawText, isNot(contains('Patreon')));
    });
  });

  group('ScribbleHubExtractor Tests', () {
    late ScribbleHubExtractor extractor;

    setUp(() {
      extractor = ScribbleHubExtractor();
    });

    test('parseNovelList extracts series search box', () {
      const html = '''
        <div class="search_main_box">
          <div class="search_img">
            <img src="https://www.scribblehub.com/covers/dungeon.jpg" />
          </div>
          <div class="search_title">
            <a href="https://www.scribblehub.com/series/1001/dungeon-life/">Dungeon Life</a>
          </div>
          <div class="search_author">
            <a href="#">Khenal</a>
          </div>
          <div class="search_genre">
            <a href="#">Fantasy</a>
            <a href="#">Isekai</a>
          </div>
        </div>
      ''';

      final novels = extractor.parseNovelList(html);
      expect(novels.length, 1);
      expect(novels[0].title, 'Dungeon Life');
      expect(novels[0].author, 'Khenal');
      expect(novels[0].id, 'scribblehub_1001');
      expect(novels[0].genres, containsAll(['Fantasy', 'Isekai']));
    });

    test('parseChapterList extracts ol.toc_ol entries', () {
      const html = '''
        <ol class="toc_ol">
          <li>
            <a href="https://www.scribblehub.com/read/1001-dungeon-life/chapter/10001/">
              Chapter 1: The Core
            </a>
          </li>
          <li>
            <a href="https://www.scribblehub.com/read/1001-dungeon-life/chapter/10002/">
              Chapter 2: The First Spawner
            </a>
          </li>
        </ol>
      ''';

      final chapters = extractor.parseChapterList('https://www.scribblehub.com/series/1001/dungeon-life/', html);
      expect(chapters.length, 2);
      expect(chapters[0].title, 'Chapter 1: The Core');
      expect(chapters[0].chapterNumber, 1.0);
      expect(chapters[1].title, 'Chapter 2: The First Spawner');
      expect(chapters[1].chapterNumber, 2.0);
    });

    test('parseChapterContent removes author notes', () {
      const html = '''
        <div class="chp_raw">
          <div class="wi_authornotes">Author Note: Hope you like this chapter!</div>
          <p>I woke up without a body.</p>
          <p>I was a glowing orb in the middle of a dirt cavern.</p>
        </div>
      ''';

      final content = extractor.parseChapterContent(
        'https://www.scribblehub.com/read/1001-dungeon-life/chapter/10001/',
        html,
      );
      expect(content.paragraphs.length, 2);
      expect(content.paragraphs[0], 'I woke up without a body.');
      expect(content.paragraphs[1], 'I was a glowing orb in the middle of a dirt cavern.');
      expect(content.rawText, isNot(contains('Author Note')));
    });
  });

  group('ReadWnExtractor Tests', () {
    late ReadWnExtractor extractor;

    setUp(() {
      extractor = ReadWnExtractor(
        id: 'test_readwn',
        name: 'Test ReadWN',
        baseUrl: 'https://example-readwn.com',
      );
    });

    test('parseNovelList extracts novels from WuxiaBox/ReadWN HTML', () {
      const html = '''
        <ul class="content-list">
          <li class="item">
            <a class="name" href="/novel/ancient-godly-monarch.html" title="Ancient Godly Monarch">
              Ancient Godly Monarch
            </a>
            <img src="https://example.com/cover.jpg" />
          </li>
        </ul>
      ''';

      final novels = extractor.parseNovelList(html);
      expect(novels.length, 1);
      expect(novels.first.id, 'test_readwn_ancient-godly-monarch');
      expect(novels.first.title, 'Ancient Godly Monarch');
      expect(novels.first.sourceUrl, 'https://example-readwn.com/novel/ancient-godly-monarch.html');
      expect(novels.first.coverUrl, 'https://example.com/cover.jpg');
    });

    test('parseChapterContent cleans and extracts paragraphs', () {
      const html = '''
        <div class="chapter-content">
          <h1>Chapter 1: The Beginning</h1>
          <p>The dawn rose over the ancient temple.</p>
          <p>Read latest chapters at badsite.com</p>
          <p>A young disciple opened his eyes.</p>
        </div>
      ''';

      final content = extractor.parseChapterContent('https://example-readwn.com/ch1.html', html);
      expect(content.paragraphs.length, 2);
      expect(content.paragraphs[0], 'The dawn rose over the ancient temple.');
      expect(content.paragraphs[1], 'A young disciple opened his eyes.');
      expect(content.rawText, isNot(contains('badsite.com')));
    });
  });

  group('FictioneerExtractor Tests', () {
    test('parseNovelList extracts novels with cards', () {
      final ext = FictioneerExtractor(
        id: 'test_fict',
        name: 'Test Fictioneer',
        baseUrl: 'https://example-fict.com',
      );

      const html = '''
        <div class="custom-vertical-card">
          <a class="custom-cover-wrapper" href="https://example-fict.com/story/legendary-sword/">
            <img class="custom-cover-image" src="https://example-fict.com/cover.jpg" />
          </a>
          <h3 class="custom-story-title">
            <a class="title-link" href="https://example-fict.com/story/legendary-sword/">Legendary Sword</a>
          </h3>
        </div>
      ''';

      final list = ext.parseNovelList(html);
      expect(list.length, 1);
      expect(list.first.title, 'Legendary Sword');
      expect(list.first.coverUrl, 'https://example-fict.com/cover.jpg');
      expect(list.first.sourceUrl, 'https://example-fict.com/story/legendary-sword/');
    });
  });

  group('SourceRegistry Verification', () {
    test('contains expected multi-template sources', () {
      final sources = SourceRegistry.getAllSources();
      expect(sources.length, greaterThanOrEqualTo(10));

      final sourceIds = sources.map((s) => s.id).toSet();
      // Madara
      expect(sourceIds, contains('sonicmtl'));
      expect(sourceIds, contains('vanovel'));
      expect(sourceIds, contains('webnoveloku'));
      expect(sourceIds, contains('novelpdf'));
      expect(sourceIds, contains('wondernovels'));
      expect(sourceIds, contains('lullobox'));
      // LightNovelWP
      expect(sourceIds, contains('kolnovel'));
      expect(sourceIds, contains('knoxt'));
      // Fictioneer
      expect(sourceIds, contains('novelib'));
      // ReadWN / WuxiaBox
      expect(sourceIds, contains('wuxiabox'));
      expect(sourceIds, contains('wuxiaspace'));
      // NovelFull
      expect(sourceIds, contains('readnovelfull'));
      expect(sourceIds, contains('novelfull'));
      expect(sourceIds, contains('novgo'));
      expect(sourceIds, contains('libread'));
      expect(sourceIds, contains('allnovelfull'));
      // Bespoke
      expect(sourceIds, contains('novelcool'));
      expect(sourceIds, contains('roliascan'));
      expect(sourceIds, contains('asurascans'));
      expect(sourceIds, contains('allfreenovel'));
      expect(sourceIds, contains('gutenberg'));
      expect(sourceIds, contains('local_epub'));
    });
  });
}

