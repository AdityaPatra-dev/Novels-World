# Novel Reading Websites & Extractor Architecture Analysis

> **Context**: This document builds directly upon the architecture strategy outlined in [ChatGPT-Design Novel Reading App-20261012-2358.md](file:///home/adityapatra/Documents/GitHub/Novels-World/ChatGPT-Design%20Novel%20Reading%20App-20261012-2358.md#L24), which recommends:
> *"Complete the offline reader, library, and one working extractor first. Then integrate the bundled TTS engine and prove it works with the internet disabled. Once that foundation works, the rest of the application can be built systematically."*

---

## 1. Executive Strategy: The "Multi-Source" Template Approach

Writing custom scrapers for every single novel site is unsustainable because:
1. Domains frequently get blocked, move to new TLDs, or update minor styling.
2. Writing 100+ bespoke scrapers leads to extreme code duplication and maintenance hell.

**The Solution**: The vast majority (~75%+) of novel reading websites do **not** build custom web applications from scratch. Instead, they run on off-the-shelf Content Management Systems (CMS) and pre-built commercial themes.

By building **Template-Based Generic Extractors** (MultiSrc engines), we can write the extraction logic **once** for a template and immediately support dozens of websites by simply feeding a config file (`sources.json`) containing the site's base URL and minor selector overrides.

---

## 2. Template Market Share & Widely Used Ranking

| Rank | CMS / Template Name | Estimated Share | Primary Target? | Characteristics |
| :--- | :--- | :--- | :--- | :--- |
| **#1** | **WordPress + Madara Theme** (`wp-manga`) | **~45%** | **TARGET FIRST (Phase 1)** | AJAX chapter pagination (`/wp-admin/admin-ajax.php`), uniform HTML classes (`.post-title`, `.reading-content`). Powers 76+ prominent novel & translation sites. |
| **#2** | **WordPress + LightNovelWP Theme** (Themesia) | **~20%** | **Target in Phase 2** | Text-novel specific WordPress theme (`.eplister`, `.epcontent`). Powers 36+ popular webnovel portals. |
| **#3** | **NovelFull / NovelBin Family** | **~12%** | **Target in Phase 2** | Custom PHP/Node engine with AJAX chapter archives (`/ajax/chapter-archive?novelId=`). Powers high-traffic aggregator sites. |
| **#4** | **ReadWN / WuxiaBox MTL Family** | **~7%** | **Target in Phase 2** | High-volume machine translation networks with simple DOM and AJAX lists. |
| **#5** | **WebNovelPub / LightNovelCave Family** | **~4%** | **Target in Phase 3** | Modern SSR/SPA layout with clean chapter reading containers. |
| **#6** | **Fictioneer WordPress Theme** | **~3%** | **Target in Phase 3** | Semantic HTML5 webfiction theme used by independent translation collectives. |
| **#7** | **MTLNovel Multi-language Family** | **~3%** | **Target in Phase 3** | Domain network sharing identical table-of-contents and multi-language subdomains. |
| **#8** | **Bespoke / Standalone Platforms** (Royal Road, Wuxiaworld, Webnovel, ScribbleHub, AO3, etc.) | **~6%** | **Handle Individually (Phase 4)** | Custom architectures, proprietary APIs, encrypted text, or strict Cloudflare/anti-bot protection. |

---

## 3. The Primary Target: WordPress Madara Theme

### Why Madara is the Widely Used Standard
Madara was originally created as a manga WordPress theme by MangaStream/WP-Manga, but because it has built-in chapter management, rating, bookmarking, and SEO structures, it became the de facto standard for light novel translation groups and novel aggregators worldwide.

### Architectural Blueprint of a Madara Site
1. **Novel Details Page**:
   - Title: `div.post-title h1` or `.post-title`
   - Author: `.author-content a`
   - Artist: `.artist-content a`
   - Genres: `.genres-content a`
   - Synopsis: `.summary__content`, `.description-summary`, or `.manga-excerpt`
   - Cover Image: `.summary_image img` (extract `src` or `data-src`)
   - Novel Status: `.post-status .post-content_item:contains("Status") .summary-content`

2. **Chapter Listing (The Madara Signature)**:
   - *Static*: Listed inside `ul.main.version-chap li.wp-manga-chapter a`
   - *Dynamic (AJAX)*: If the site lazy-loads chapters to save bandwidth, Madara exposes standard endpoints:
     - **POST** `${siteUrl}/wp-admin/admin-ajax.php` with form data:
       - `action: manga_get_chapters`
       - `manga: {manga_id}`
     - Or the newer REST endpoint: `${siteUrl}/wp-json/manga/v1/episodes?manga_id={id}`
   - Each chapter item contains:
     - URL: `a[href]`
     - Title: `a.text()`
     - Release Date: `span.chapter-release-date`

3. **Chapter Content / Text Reader**:
   - Text container: `div.text-left`, `div.reading-content`, or `div.entry-content`
   - Text paragraphs: `p` tags inside the container (stripping out script tags, ads, and navigation buttons).

4. **Search**:
   - `GET ${siteUrl}/?s={query}&post_type=wp-manga` or `GET ${siteUrl}/page/{page}/?s={query}&post_type=wp-manga`

---

## 4. Complete Catalog of Novel Reading Websites

### Group 1: WordPress Madara Theme Sites (Target First - 76+ Sources)
*All of these can be extracted using a single `MadaraExtractor` base engine with site-specific configuration:*

| Website Name | URL | Language / Type |
| :--- | :--- | :--- |
| **NovelTranslate** | `https://noveltranslate.com/` | English / Aggregator & MTL |
| **FirstKissNovel** | `https://1stkissnovel.org/` | English / Korean & Chinese Romance/Action |
| **LunarLetters** | `https://lunarletters.com/` | English / Translations |
| **SleepyTranslations** | `https://sleepytranslations.com/` | English / Korean & Japanese Translations |
| **DaoNovel** | `https://daonovel.co/` | English / Cultivation & Xuanhuan |
| **MostNovel** | `https://mostnovel.com/` | English / Webnovels |
| **NovelMultiverse** | `https://www.novelmultiverse.com/` | English / Translation Group |
| **LightNovelHeaven** | `https://lightnovelheaven.com/` | English / Light Novels |
| **Foxaholic** | `https://www.foxaholic.com/` | English / High-volume Asian Novel Translations |
| **WuxiaWorld.Site** | `https://wuxiaworld.site/` | English / Aggregator (not the official .com) |
| **SonicMTL** | `https://www.sonicmtl.com/` | English / Machine Translation |
| **NeoSekai Translations** | `https://www.neosekaitranslations.com/` | English / Japanese Light Novels |
| **MeioNovel** | `https://meionovels.com/` | Portuguese / Webnovels |
| **Zetro Translation** | `https://zetrotranslation.com/` | English / Light Novels |
| **ArNovel** | `https://ar-no.com/` | Arabic / Translated Novels |
| **WebNovelLover** | `https://www.webnovelover.com/` | English / Webnovels |
| **WBNovel** | `https://wbnovel.com/` | English / Webnovels (Active in App) |
| **MysticalSeries** | `https://mysticalmerries.com/` | English / Romance & Fantasy |
| **Vanovel** | `https://vanovel.com/` | Turkish / Light Novels |
| **HizoManga** | `https://hizomanga.net/` | Arabic / Novel & Manga |
| **Riwyat** | `https://cenele.com/` | Arabic / Novels (Active in App) |
| **Wonder Novels** | `https://wondernovels.com/` | English / Translations (Active in App) |
| **Novel Short** | `https://novel-short.com/` | English / Webnovels (Active in App) |
| **Etude Translations** | `https://etudetranslations.com/` | English / Light & Webnovels (Active in App) |
| **Anslid** | `https://anslid.com/` | Spanish / Webnovels (Active in App) |
| **Lullobox** | `https://lullobox.com/` | English / Webnovels (Active in App) |
| **Novel4Up** | `https://novel4up.com/` | Arabic / Novels (Hijacked Domain) |
| **TurkceLightNovels** | `https://turkcelightnovels.com/` | Turkish / Light Novels |
| **Guavaread** | `https://guavaread.com/` | English / Korean & Chinese Novels |
| **MTL-Novel** | `https://mtl-novel.com/` | English / MTL |
| **WebNovelOku** | `https://www.webnoveloku.com/` | Turkish / Webnovels |
| **Light Novel Updates** | `https://www.lightnovelupdates.com/` | English / Novels |
| **Nitro Manga** | `https://nitromanga.com/` | English / Novels & Manga |
| **Kiniga** | `https://kiniga.com/` | English / Novels |
| **Pancho Translations** | `https://panchotranslations.com/` | English / Translations |
| **Salmon Latte** | `https://salmonlatte.com/` | English / Japanese Novels |
| **Srank Manga** | `https://srankmanga.com/` | English / Novels |
| **Novel Lucky** | `https://novel-lucky.com/` | Thai / Webnovels (Active in App) |
| **Fans Translations** | `https://fanstranslations.com/` | English / Fan Translations |
| **WorldNovel** | `https://world-novel.fr/` | French / Light Novels |
| **Hiraeth Translation** | `https://hiraethtranslation.com/` | English / Korean Novels |
| **Novel PDF** | `https://novelpdf.xyz/` | English / Webnovels |
| **Azora** | `https://azoramoon.com/` | Arabic / Novels |
| **TranslatinOtaku** | `https://translatinotaku.net/` | English / Japanese Light Novels |
| **Nocturne Translations** | `https://nocturnetls.net/` | English / Korean & Chinese Novels |
| **Yousum** | `https://yousum.me/` | English / Webnovels |
| **Top Light Novel** | `https://toplightnovel.com/` | English / Novels |
| **BoxNovel** | `https://boxnovel.com/` | English / Webnovels (Active in App) |
| **WordExcerpt** | `https://wordexcerpt.com/` | English / Korean & Japanese Licensors |
| **Crush Novel** | `https://crushnovel.com/` | English / Webnovels |
| **Novel Crusher** | `https://novelcrusher.com/` | English / Webnovels |
| **Reaper Scans Novels** | `https://reaperscans.com/` | English / Webnovels & Manhwa |
| **Flame Scans/Comics** | `https://flamecomics.me/` | English / Webnovels |
| **Asura Scans Novels** | `https://asurascans.com/` | English / Korean Webnovels |
| **Leviatan Scans** | `https://en.leviatanscans.com/` | English / Webnovels |

---

### Group 2: WordPress LightNovelWP Theme Sites (Phase 2 Target - 36+ Sources)
*Specialized novel theme using `.eplister` and `.epcontent`:*

| Website Name | URL | Language / Region |
| :--- | :--- | :--- |
| **Kol Novel** | `https://kolnovel.com/` | Arabic / Top Arabic Novel Site |
| **Free Kol Novel** | `https://free.kolnovel.com/` | Arabic / Free mirror |
| **Light Novel FR** | `https://lightnovelfr.com/` | French / Top French Light Novel Portal |
| **KnoxT** | `https://knoxt.space/` | English / Korean & Chinese Translations |
| **Baca Light Novel** | `https://bacalightnovel.co/` | Indonesian / Light Novels |
| **AllNovelRead** | `https://allnovelread.com/` | English / Aggregator |
| **DaoTranslate** | `https://daotranslate.com/` | English / Xianxia & Cultivation |
| **Novels Paradise** | `https://novelsparadise.site/` | English / Webnovels |
| **Sakura Novel** | `https://sakuranovel.id/` | Indonesian / Light Novels |
| **Meio Novel (WP)** | `https://meionovel.id/` | Indonesian / Webnovels |
| **Novelas Ligeras** | `https://novelasligeras.net/` | Spanish / Light Novels |
| **MoreNovel** | `https://morenovel.net/` | English / Aggregator |
| **NovelPlanet (Clone)**| `https://novelplanet.com/` | English / Aggregator |
| **Ragna Novel** | `https://ragnanovel.com/` | English / Fantasy Novels |
| **Kuro Novel** | `https://kuronovel.com/` | English / Japanese Light Novels |

---

### Group 3: ReadNovelFull / NovelFull / NovelBin Family (Phase 2 Target)
*High-volume aggregator network running custom CMS with AJAX chapter lists:*

| Website Name | URL | Core Features |
| :--- | :--- | :--- |
| **NovelFull** | `https://novelfull.com/` | Huge library, standard `#chr-content`, AJAX archive |
| **Novel Bin** | `https://novelbin.com/` | High traffic, clean reading layout (Active in App) |
| **ReadNovelFull** | `https://readnovelfull.com/` | Sister to NovelFull |
| **Lib Read** | `https://libread.com/` | NovelFull clone layout |
| **AllNovelFull** | `https://novgo.net/` | Fast chapter loading |
| **LightNovelPlus** | `https://lightnovelplus.com/` | NovelFull layout clone |
| **Novel Ping** | `https://novelping.com/` | NovelFull layout clone |
| **AllNovel** | `https://allnovel.net/` | NovelFull engine variant |

---

### Group 4: ReadWN / WuxiaBox MTL Family (Phase 2 Target)
*Chinese webnovel machine-translation platforms with clean, simple DOM:*

| Website Name | URL | Special Notes |
| :--- | :--- | :--- |
| **WuxiaBox** | `https://www.wuxiabox.com` | High-speed MTL aggregation |
| **WuxiaFox** | `https://www.wuxiafox.com` | Mirror of WuxiaBox |
| **Ltnovel** | `https://www.ltnovels.com` | Fast raw/MTL translations |
| **FanMTL** | `https://www.fanmtl.com` | Fan machine translations (Active in App) |
| **Wuxia Space** | `https://www.wuxiaspot.com` | Xianxia / Wuxia focus |
| **WuxiaV** | `https://www.wuxiav.com` | Raw translation archive |

---

### Group 5: WebNovelPub / LightNovelCave Family (Phase 3 Target)
*Modern responsive reader layouts with clean infinite scroll:*

| Website Name | URL | Layout Type |
| :--- | :--- | :--- |
| **Web Novel World** | `https://www.webnovelworld.org/` | Nuxt/SSR clean reader |
| **LightNovelPub** | `https://lightnovelpub.vip/` | High UX score, clean chapter container |
| **LightNovelCave** | `https://www.lightnovelcave.com/` | Mirror of LightNovelPub |
| **FreeWebNovel** | `https://freewebnovel.com/` | Clean aggregator reader |

---

### Group 6: Fictioneer WordPress Theme Sites (Phase 3 Target)
*Modern semantic HTML5 theme built by and for independent web novelists:*

| Website Name | URL | Genre Focus |
| :--- | :--- | :--- |
| **Daoist Quest** | `https://daoist.quest` | Original progression fantasy |
| **NovelLib** | `https://novelib.com` | Web fiction |
| **Lily on the Valley** | `https://lilyonthevalley.com` | Indie translated novels |
| **Penguin Squad** | `https://penguin-squad.com` | Translation group |
| **Prizma Translation** | `https://prizmatranslation.com` | Korean romance & fantasy |
| **Dearest Rosalie** | `https://dearestrosalie.com` | Web novel translations |
| **Cherry Mist Cafe** | `https://cherrymist.cafe/` | Indie romance novels |
| **Illusia** | `https://illusia.com.br` | Portuguese translations |

---

### Group 7: MTLNovel Multi-language Network (Phase 3 Target)
*Single backend serving multiple language subdomains with identical TOC and chapter structure:*

| Domain | Language | URL |
| :--- | :--- | :--- |
| **MTL Novel (EN)** | English | `https://www.mtlnovels.com/` |
| **MTL Novel (FR)** | French | `https://fr.mtlnovels.com/` |
| **MTL Novel (ES)** | Spanish | `https://es.mtlnovels.com/` |
| **MTL Novel (ID)** | Indonesian | `https://id.mtlnovels.com/` |
| **MTL Novel (PT)** | Portuguese | `https://pt.mtlnovels.com/` |
| **MTL Novel (RU)** | Russian | `https://ru.mtlnovels.com/` |

---

## 5. Bespoke & Platform-Specific Sites (To Handle Individually in Phase 4)

These platforms cannot be scraped using off-the-shelf template extractors because they feature custom architectures, authentication, anti-bot guards, or encrypted fonts:

### A. Major Western Web Fiction Platforms
1. **Royal Road (`https://www.royalroad.com`)**:
   - *Why Bespoke*: Custom ASP.NET MVC architecture, Cloudflare Turnstile, strict anti-scraper policies, custom pagination and author notes layout.
   - *Selectors*: Title: `.fiction-title`, Author: `h4 span a`, Content: `.chapter-inner.chapter-content`.
2. **Scribble Hub (`https://www.scribblehub.com`)**:
   - *Why Bespoke*: Sister platform to NovelUpdates. Custom AJAX pagination for chapter index (`mypost.php`), custom TOC tabs.
   - *Selectors*: Content: `.chp_raw`, TOC: `#chapter_list`.
3. **Archive of Our Own - AO3 (`https://archiveofourown.org`)**:
   - *Why Bespoke*: Open-source Ruby on Rails backend (Otis). Requires adult confirmation cookies, supports entire novel extraction via `?view_full_work=true`.
   - *Selectors*: Content: `#chapters .userstuff`.
4. **Wattpad (`https://www.wattpad.com`)**:
   - *Why Bespoke*: Single Page Application (React/Next). Best handled via internal mobile API (`/v4/parts/{id}`) rather than scraping HTML DOM.

### B. Major Commercial Asian Platforms
1. **Wuxiaworld (`https://www.wuxiaworld.com`)**:
   - *Why Bespoke*: Proprietary React/Next.js frontend with GraphQL backend. Freemium paywalls (Karma / VIP lock) for advance chapters; public chapters require clean JSON extraction.
2. **Webnovel / Qidian International (`https://www.webnovel.com`)**:
   - *Why Bespoke*: Aggressive anti-scraping, dynamic SVG/encrypted font glyph mappings to deter copy-paste, paywalled "Spirit Stones". Requires token generation or mobile API reverse engineering.
3. **NovelUpdates (`https://www.novelupdates.com`)**:
   - *Note*: NovelUpdates is **not** a reading host; it is an index/directory. Scrapers usually use NovelUpdates only for metadata/series discovery and follow the outbound redirect links to the real host.

### C. Large Independent Aggregators
1. **Ranobes (`https://ranobes.top`, `https://ranobes.com`)**:
   - Custom Russian/English platform with nested volume support, EPUB download endpoints, and unique chapter hierarchy.
2. **NovelCool (`https://www.novelcool.com`)**:
   - Hybrid manga/novel portal with dynamic chapter pagination.
3. **NovelFire / Novel Phoenix (`https://novelfire.net/`, `https://novelphoenix.com/`)**:
   - Clean, lightweight reader layout with custom book navigation.
4. **NovelBuddy (`https://novelbuddy.com`)**:
   - Modern manga/novel hybrid engine with AJAX pagination.
5. **NovelHall (`https://novelhall.com`)**:
   - Fast plain-HTML aggregator with straightforward table-of-contents.
6. **WTR-LAB (`https://wtr-lab.com`)**:
   - Modern AI-assisted translation portal with clean JSON endpoints and raw source comparisons.
7. **Just Light Novels (`https://justlightnovels.com`)**:
   - High-quality officially formatted light novel archive with volume downloads and illustrations.
8. **Fenrir Translations (`https://fenrirtranslations.com`)**:
   - Fast-growing human translation group for popular Japanese and Korean light novels (WordPress Madara).
9. **Chichome MTL (`https://chichome.com`)**:
   - Popular high-speed raw machine-translation reader for Chinese progression fantasy.
10. **Moonlight Novels (`https://moonlightnovels.com`)**:
    - Dedicated romance and villainess web fiction translation collective (WordPress Madara).
11. **NovelToT (`https://noveltot.com`)**:
    - Clean, ad-light aggregator with fast mobile chapter rendering.
12. **Shousetsuka ni Narou - Syosetu (`https://ncode.syosetu.com`)**:
    - The legendary Japanese user-generated web fiction platform where *Re:Zero*, *Slime*, and *Mushoku Tensei* originated.
13. **Kakuyomu (`https://kakuyomu.jp`)**:
    - Kadokawa's official web novel publication portal for serialized Japanese light novels.

### D. Scanlation & Translator Blogs (Obfuscation & Custom CMS)
1. **Chrysanthemum Garden (`https://chrysanthemumgarden.com`)**:
   - *Challenge*: Employs a custom font cipher that scrambles text characters in the DOM unless paired with their proprietary web font. Requires a font descrambler / glyph map decoder.
2. **Divine Dao Library (`https://www.divinedaolibrary.com`)**:
   - WordPress blog with standard post format (chapters are WordPress blog posts).
3. **Skythewood (`https://skythewood.blogspot.com`)**:
   - Google Blogger / Blogspot layout with nested labels and manual TOC pages.
4. **Rain of Snow (`https://rainofsnow.com`)**:
   - Custom coin-gated translation reader.

---

## 6. Target Extractor Architecture: The MultiSrc Engine

To fulfill the design prompt from `ChatGPT-Design Novel Reading App-20261012-2358.md`, the app should define a clean, universal extractor interface:

### 1. Unified Interface Model
```typescript
export interface Novel {
  id: string;
  sourceId: string;
  title: string;
  author?: string;
  artist?: string;
  description?: string;
  coverUrl?: string;
  genres: string[];
  status: 'ONGOING' | 'COMPLETED' | 'UNKNOWN';
  url: string;
}

export interface Chapter {
  id: string;
  novelId: string;
  title: string;
  chapterNumber?: number;
  url: string;
  releaseDate?: string;
}

export interface ChapterContent {
  chapterId: string;
  novelId: string;
  title: string;
  text: string;           // Clean sanitized text for reader & offline TTS
  html?: string;          // Optional formatted HTML
}

export interface NovelSource {
  id: string;
  name: string;
  baseUrl: string;
  search(query: string, page?: number): Promise<Novel[]>;
  getNovelDetails(novelUrl: string): Promise<Novel>;
  getChapterList(novelUrl: string): Promise<Chapter[]>;
  getChapterContent(chapterUrl: string): Promise<ChapterContent>;
}
```

### 2. The Universal Madara Template Engine (`MadaraExtractor.ts`)
```typescript
export interface MadaraOptions {
  id: string;
  name: string;
  baseUrl: string;
  useNewChapterEndpoint?: boolean;
  chapterAjaxEndpoint?: string;
  contentSelector?: string;
}

export class MadaraExtractor implements NovelSource {
  id: string;
  name: string;
  baseUrl: string;
  private options: MadaraOptions;

  constructor(options: MadaraOptions) {
    this.id = options.id;
    this.name = options.name;
    this.baseUrl = options.baseUrl;
    this.options = options;
  }

  async search(query: string, page = 1): Promise<Novel[]> {
    const url = `${this.baseUrl}/page/${page}/?s=${encodeURIComponent(query)}&post_type=wp-manga`;
    const html = await fetchHtml(url);
    // Parse .c-tabs-item__content or .row.c-tabs-item__content
    return parseMadaraSearchResults(html, this.id, this.baseUrl);
  }

  async getNovelDetails(novelUrl: string): Promise<Novel> {
    const html = await fetchHtml(novelUrl);
    // Parse .post-title, .summary_content, .genres-content, .summary_image
    return parseMadaraDetails(html, novelUrl, this.id);
  }

  async getChapterList(novelUrl: string): Promise<Chapter[]> {
    // 1. Check if chapters are in the initial DOM (ul.main.version-chap)
    let html = await fetchHtml(novelUrl);
    let chapters = parseMadaraChapterDom(html, novelUrl);
    
    // 2. If lazy loaded, call the standard Madara AJAX endpoint
    if (chapters.length === 0) {
      const mangaId = extractMangaIdFromHtml(html);
      const ajaxEndpoint = this.options.chapterAjaxEndpoint || `${this.baseUrl}/wp-admin/admin-ajax.php`;
      const ajaxHtml = await postFormData(ajaxEndpoint, {
        action: 'manga_get_chapters',
        manga: mangaId
      });
      chapters = parseMadaraChapterDom(ajaxHtml, novelUrl);
    }
    return chapters;
  }

  async getChapterContent(chapterUrl: string): Promise<ChapterContent> {
    const html = await fetchHtml(chapterUrl);
    const selector = this.options.contentSelector || '.text-left, .reading-content, .entry-content';
    const text = extractCleanText(html, selector);
    return {
      chapterId: chapterUrl,
      novelId: '',
      title: extractTitle(html),
      text: text // Ready for offline reading and TTS synthesis
    };
  }
}
```

---

## 7. Phased Implementation Roadmap

```
  ┌───────────────────────────────────────────────────────────┐
  │  PHASE 1: Foundation & The Widely Used Target (Madara)    │
  │  ───────────────────────────────────────────────────────  │
  │  1. Implement Universal MadaraExtractor engine            │
  │  2. Test with 3 high-reliability Madara sources:          │
  │     • FirstKissNovel (1stkissnovel.org)                  │
  │     • LunarLetters (lunarletters.com)                     │
  │     • NovelTranslate (noveltranslate.com)                 │
  │  3. Integrate Offline Reader & Bundled TTS engine         │
  │  4. Verify reading + TTS completely offline               │
  └─────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
  ┌───────────────────────────────────────────────────────────┐
  │  PHASE 2: Multi-Source Scaling (100+ Sites)               │
  │  ───────────────────────────────────────────────────────  │
  │  1. Implement LightNovelWPExtractor (KolNovel, KnoxT)     │
  │  2. Implement NovelFullExtractor (NovelFull, NovelBin)    │
  │  3. Implement ReadWNExtractor (WuxiaBox, Ltnovel)         │
  │  4. Ingest full sources.json registries into app catalog  │
  └─────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
  ┌───────────────────────────────────────────────────────────┐
  │  PHASE 3: Tier 2 Engines & Machine Translation Sites      │
  │  ───────────────────────────────────────────────────────  │
  │  1. WebNovelPub / LightNovelCave extractor                │
  │  2. MTLNovel multi-language engine                        │
  │  3. Fictioneer engine (indie author platforms)            │
  └─────────────────────────────┬─────────────────────────────┘
                                │
                                ▼
  ┌───────────────────────────────────────────────────────────┐
  │  PHASE 4: Bespoke Platform Handlers                       │
  │  ───────────────────────────────────────────────────────  │
  │  1. Royal Road bespoke extractor + Cloudflare solver      │
  │  2. Scribble Hub bespoke extractor                        │
  │  3. AO3 full-work extractor                               │
  │  4. Chrysanthemum Garden font de-obfuscation decoder      │
  │  5. Wuxiaworld free-tier API client                       │
  └───────────────────────────────────────────────────────────┘
```

---

## 8. Summary & Next Steps

- **Widely Used Template Selected**: **WordPress Madara Theme** (`wp-manga`).
- **Initial Verification Sites**: `FirstKissNovel` & `NovelTranslate`.
- **Reasoning**: Covers ~45% of available web novel sources with unified AJAX endpoints, zero UI pagination quirks, and standard CSS selectors.
- **Immediate Next Step**: Build `MadaraExtractor` along with the core storage model, reader UI, and offline TTS engine as requested in the app specification.
