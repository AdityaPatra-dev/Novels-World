# Candidate Sources Catalog & Inspection Ledger

> **Inspection Guide**: This document catalogues all identified candidate sources categorized by the **Library Taxonomy** to fill your content gaps (LitRPG, Progression Fantasy, Epic/High Fantasy, Hard Sci-Fi, Mystery/Thriller, Romance, Literary Novellas, and Eastern Web Fiction).
>
> **Action Required**: Please inspect each URL, test whether the site is accessible from your network/region, and check the checkbox `[x]` under the **Verified Status** column. Once verified, we will systematically build/enable the extractors for your approved sources.

---

## Summary Matrix of Library Taxonomy Coverage

| # | Taxonomy Category | Current Status in App | Target Source Types |
| :--- | :--- | :--- | :--- |
| **1** | **Western Progression Fantasy & LitRPG** | Severe Gap (Asian Hunter only) | Original Web Fiction Portals, LitRPG communities |
| **2** | **Modern Epic & High Fantasy** | Completely Missing | Open Access libraries, Baen Free, Standard Ebooks |
| **3** | **Science Fiction (Space Opera, Cyberpunk)** | Severe Gap (Vintage only) | Speculative magazines, Sci-Fi serial portals |
| **4** | **Thriller, Mystery, Crime & Detective** | Severe Gap | Public Domain & Free Ebook Mystery archives |
| **5** | **Traditional Romance & Romantasy** | Moderate (AllFreeNovel) | High-volume romance repositories, serial portals |
| **6** | **Literary Fiction & Standalone Novellas** | Completely Missing | Award-winning short fiction digests, curated novellas |
| **7** | **Young Adult (YA) & Coming-of-Age** | Moderate (LN only) | Western YA portals, indie serialized fiction |
| **8** | **Eastern Web Fiction & Light Novels** | Saturated (~85% catalog) | Top verified aggregators & translation collectives |

---

## 1. Western Progression Fantasy, LitRPG & Original Web Fiction

*Target audience: Readers seeking leveling systems, dungeon crawling, progression, cultivation, and Western serials.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **Royal Road** | `https://www.royalroad.com` | Bespoke (`RoyalRoadExtractor`) | The #1 global platform for LitRPG, Progression Fantasy, and Isekai. 50,000+ top-tier original web fictions. Fully supported with WebView bot-protection fallback. | [x] Working |
| **Scribble Hub** | `https://www.scribblehub.com` | Bespoke (`ScribbleHubExtractor`) | High-volume original web serials, LitRPG, Isekai, and Romance Fantasy. Sister site of NovelUpdates. Fully supported with WebView bot-protection fallback. | [x] Working |
| **SpaceBattles (Creative Writing)** | `https://forums.spacebattles.com/forums/creative-writing.18/` | XenForo Forum Threadmarks | Massive repository of epic original sci-fi, Worm fanfiction/clones, space opera, and LitRPG quest serials. | [ ] Working |
| **Sufficient Velocity** | `https://forums.sufficientvelocity.com/forums/user-fiction.2/` | XenForo Forum Threadmarks | Sprawling serialized fiction, quest-based LitRPG, and high-concept fantasy with built-in chapter threadmarks. | [ ] Working |
| **Neovel** | `https://neovel.io` | Modern SPA / REST API | Dedicated modern indie webfiction platform featuring LitRPG, Isekai, and fantasy in multiple languages. | [ ] Working |
| **Honeyfeed** | `https://www.honeyfeed.fm` | Bespoke / Next.js | Community-driven light novel and original webfiction portal backed by Japanese publishers. | [ ] Working |
| **Creative Novels** | `https://creativenovels.com` | WordPress / Custom | Curated original English web fiction, high fantasy, and translated light novels. | [ ] Working |
| **TopWebFiction** | `https://www.topwebfiction.com` | Web Directory / Index | Curated ranking directory indexing top independent web serials (Worm, Practical Guide to Evil, Mother of Learning mirrors). | [ ] Working |
| **Questionable Questing** | `https://forum.questionablequesting.com/forums/creative-writing.3/` | XenForo Forum Threadmarks | Deep archive of creative web fiction, LitRPG, and progression fantasy serials. | [ ] Working |

---

## 2. Modern Epic / High Fantasy & Classic Speculative Fiction

*Target audience: Traditional fantasy readers seeking rich worldbuilding, sword & sorcery, and complete books rather than endless chapters.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **Standard Ebooks** | `https://standardebooks.org` | Open Git / Static HTML / OPDS | High-typography, beautifully typeset public domain modern editions. High fantasy, gothic fantasy, classical worlds. Fully working with direct EPUB pipeline. | [x] Working |
| **Baen Free Library** | `https://www.baen.com/allbooks/category/index/id/2012` | Clean HTML / Free Catalog | Legitimate free, full-length fantasy and sci-fi novels from commercial authors (Mercedes Lackey, David Weber, etc.). | [ ] Inspected |
| **Faded Page** | `https://www.fadedpage.com` | Clean HTML & EPUB archive | Canadian public domain archive covering post-1928 masterworks (Sylvia Plath, Hemingway, Orwell). Note: EPUB downloads gated behind Google reCAPTCHA. | [!] reCAPTCHA Gated |
| **Open Library** | `https://openlibrary.org` | Internet Archive REST API | Millions of digitized books with public open editions across epic fantasy, history, and mythology. Fully working in app. | [x] Working |
| **ManyBooks Fantasy** | `https://manybooks.net/categories/fantasy` | Clean CMS / EPUB | Over 10,000+ curated fantasy novels categorized by epic, historical, and dark fantasy. | [ ] Working |
| **Global Grey Ebooks** | `https://www.globalgreyebooks.com/category/fiction-fantasy/` | WordPress / Static | Cleanly edited classic fantasy, folklore, myths, and speculative epics with zero ad clutter. | [ ] Working |
| **Feedbooks Public Domain** | `https://www.feedbooks.com/publicdomain` | OPDS / Clean HTML | High quality curated public domain fantasy and adventure collections. | [ ] Working |
| **Smashwords Free Fantasy** | `https://www.smashwords.com/books/category/1/newest/0/free/any` | Custom Bookstore API | Thousands of free complete indie high-fantasy, sword and sorcery, and epic trilogy starter novels. | [ ] Working |

---

## 3. Science Fiction (Space Opera, Cyberpunk, Hard Sci-Fi)

*Target audience: Fans of space exploration, AI, cyberpunk dystopias, military sci-fi, and first-contact epics.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **Clarkesworld Magazine** | `https://clarkesworldmagazine.com` | Bespoke (`ClarkesworldExtractor`) | Multi-Hugo & Nebula award-winning monthly sci-fi magazine. Features the highest caliber of contemporary space opera & hard sci-fi. | [x] Working |
| **Lightspeed Magazine** | `https://www.lightspeedmagazine.com` | Bespoke (`LightspeedExtractor`) | Premier digital sci-fi & fantasy monthly publication. Huge searchable archive of hard sci-fi novellas and novelettes. | [x] Working |
| **Daily Science Fiction** | `https://dailysciencefiction.com` | Static HTML archive | Previously daily sci-fi stories; currently parked/inactive domain. | [-] Offline/Parked |
| **Strange Horizons** | `https://strangehorizons.com` | Semantic HTML / Weekly | Hugo-nominated speculative fiction, sociological sci-fi, and futuristic cyberpunk stories published weekly since 2000. | [ ] Inspected |
| **Apex Magazine** | `https://apex-magazine.com` | WordPress / Fiction | Dark sci-fi, biotechnology horror, and near-future cyberpunk speculative fiction. | [ ] Inspected |
| **Escape Pod** | `https://escapepod.org` | WordPress / Text + Audio | The world's premier weekly science fiction short fiction venue with full text releases accompanying each audio release. | [ ] Inspected |
| **Uncanny Magazine** | `https://www.uncannymagazine.com` | Bespoke (`UncannyExtractor`) | Hugo-winning modern space opera, AI, and diverse speculative fiction stories and novellas. | [x] Working |
| **Free SF Online** | `https://www.freesfonline.net` | Indexer / Directory | Exhaustive catalog index linking thousands of legally free science fiction stories by major authors across the web. | [ ] Working |

---

## 4. Thriller, Mystery, Crime Noir & Detective Fiction

*Target audience: Readers who love whodunits, psychological suspense, forensic mysteries, espionage, and crime drama.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **ManyBooks Mystery & Thriller** | `https://manybooks.net/categories/mystery-and-thriller` | Clean CMS / EPUB | Over 8,000+ detective, murder mystery, thriller, and spy novels with clean categorization. | [ ] Working |
| **Free-eBooks.net Mystery** | `https://www.free-ebooks.net/mystery` | Custom CMS | High-volume indie mystery novels, cozy mysteries, psychological thrillers, and private eye stories. | [ ] Working |
| **Classic Crime Fiction** | `http://www.classiccrimefiction.com` | Static HTML | Golden Age of Detective Fiction archive: Agatha Christie style, John Dickson Carr, locked-room mysteries. | [ ] Working |
| **Arthur Conan Doyle Online** | `https://www.arthur-conan-doyle.com` | MediaWiki / Full Text | The definitive comprehensive collection of all Sherlock Holmes novels, cases, and mystery novellas. | [ ] Working |
| **Feedbooks Mystery & Crime** | `https://www.feedbooks.com/publicdomain/category/FBFIC022000` | OPDS / Clean HTML | Cleanly typeset vintage noir, detective fiction, and early psychological crime novellas. | [ ] Working |

---

## 5. Traditional, Contemporary & Romantasy (Romance)

*Target audience: High-retention readers of contemporary romance, billionaire, fantasy romance (Romantasy), dark romance, and historical drama.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **AllFreeNovel** | `https://allfreenovel.com` | Bespoke (Already in app) | 40,000+ popular romance, contemporary fiction, romantic suspense, billionaire, and dark romance titles. | [x] Working |
| **Novel12** | `https://novel12.com` | High-Capacity Aggregator | Over 50,000+ romance, contemporary fiction, YA titles. Note: Currently encountering infinite redirect loop. | [-] Redirect Loop |
| **Novel80** | `https://novel80.com` | High-Capacity Aggregator | Massive collection of popular published romance series. Note: Currently encountering infinite redirect loop. | [-] Redirect Loop |
| **ReadNovelsOnline** | `https://readnovelsonline.com` | Custom Web Portal | High-volume library of popular modern romance. Note: DNS/Connection timeout. | [-] Timed Out |
| **Novel24** | `https://novel24.com` | NovelFull-variant | Broad general fiction catalog with heavy focus on romance. Note: Protected by dynamic JS JWT cookie verification. | [!] JS JWT Protected |
| **Booknet English** | `https://booknet.com/en` | Commercial Portal / Free Tiers | Hotbed for modern indie romance: billionaire romance, dark fantasy, and Romantasy web serials. | [ ] Working |
| **Inkitt** | `https://www.inkitt.com` | React SPA / REST API | Thousands of crowd-favorite indie romance novels, werewolf/mafia romance, and viral fantasy stories. | [ ] Working |

---

## 6. Literary Fiction, Curated Short Stories & Novellas

*Target audience: Readers wanting short, punchy 50–150 page standalone reads or deep character-driven literature.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **Reactor Mag (formerly Tor.com)** | `https://reactormag.com/fiction/` | WordPress / Semantic HTML | The industry pinnacle of modern speculative novellas, Hugo/Nebula award winners, and standalone short fiction. | [ ] Working |
| **Beneath Ceaseless Skies** | `https://www.beneath-ceaseless-skies.com` | Bi-weekly Literary Digest | World-renowned magazine publishing character-driven literary fantasy and short novellas in secondary worlds. | [ ] Working |
| **Flash Fiction Online** | `https://www.flashfictiononline.com` | WordPress / Quick Reads | Curated 500-1,000 word stories across sci-fi, literary, and fantasy. Perfect for casual mobile reading. | [ ] Working |
| **East of the Web** | `https://www.eastoftheweb.com/short-stories/` | Bespoke (`EastOfTheWebExtractor`) | Premier library of curated short stories and novellas across literary, sci-fi, romance, and crime. | [x] Working |
| **American Literature (Short Stories)** | `https://americanliterature.com/short-stories/` | Clean HTML | Tens of thousands of complete classic short stories, novellas, and literary fiction works with clean formatting. | [ ] Working |

---

## 7. Young Adult (YA) & Teen Coming-of-Age

*Target audience: Teen and adult readers seeking high-stakes magic schools, coming-of-age journeys, and dystopian fiction.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **ManyBooks Young Adult** | `https://manybooks.net/categories/young-adult` | Clean CMS / EPUB | Curated library of YA fantasy, teen coming-of-age, and dystopian adventure. | [ ] Working |
| **Smashwords Free YA** | `https://www.smashwords.com/books/category/1054/newest/0/free/any` | Custom Bookstore API | Thousands of free full-length YA indie novels, magical school academies, and urban fantasy starters. | [ ] Working |
| **Inkitt YA Collection** | `https://www.inkitt.com/genres/youngadult` | React SPA / REST API | Viral indie YA fiction, supernatural high school, and teen dystopian romance. | [ ] Working |

---

## 8. Eastern Web Fiction, Cultivation & Light Novels (Top Aggregators & Translation Collectives)

*Target audience: Dedicated web novel readers looking for Xianxia, Wuxia, Korean Hunter novels, and Japanese Light Novels.*

| Source Name | Website URL | Engine / Architecture | Content Highlights | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| **ReadNovelFull** | `https://readnovelfull.com` | NovelFull Family (In App) | 55,000+ top translated Chinese, Korean, and Japanese webnovels. | [x] Working |
| **NovelFull** | `https://novelfull.com` | NovelFull Family (In App) | 50,000+ popular webnovels with fast server response and full chapter archives. | [x] Working |
| **FreeWebNovel** | `https://freewebnovel.com` | NovelFull Family (In App) | 45,000+ webnovels, light novels, and Korean fantasy novels. | [x] Working |
| **LibRead** | `https://libread.com` | NovelFull Family (In App) | 40,000+ clean catalog web novels with minimal ad intrusion. | [x] Working |
| **NovelFire** | `https://novelfire.net` | NovelFull Family (In App) | 38,000+ Korean hunter and Xianxia novels with active updates. | [x] Working |
| **WuxiaBox** | `https://www.wuxiabox.com` | ReadWN Family (In App) | 45,000+ high-speed raw machine-translated cultivation and urban novels. | [x] Working |
| **NovelCool** | `https://novelcool.com` | Bespoke (In App) | Manhwa/Manga novel source adaptations, Japanese LNs, and Korean web novels. | [x] Working |
| **LightNovelWorld** | `https://www.lightnovelworld.co` | Modern SPA / SSR | Premium web novel reader mirroring top trending light novels and translated serials. | [ ] Inspected |
| **BoxNovel** | `https://boxnovel.com` | WordPress Madara | Popular light novel and translated Korean webnovel portal. Note: Protected by Cloudflare challenge. | [!] Cloudflare Protected |
| **Woopread** | `https://woopread.com` | Bespoke (`WoopReadExtractor`) | High-quality human translations of popular Korean fantasy and Otome novels. Fully supported Next.js reader. | [x] Working |
| **RainOfSnow** | `https://rainofsnow.com` | WordPress Madara | Dedicated group translating Korean web fiction, Romance Fantasy, and Xianxia. Note: Protected by Cloudflare challenge. | [!] Cloudflare Protected |
| **Foxaholic** | `https://foxaholic.com` | WordPress Madara | High-traffic hub hosting hundreds of active translation projects for Chinese/Korean novels. | [ ] Inspected |
| **Chrysanthemum Garden** | `https://chrysanthemumgarden.com` | WordPress Bespoke | The premier translation group for Danmei, BL, and cultivation web novels. | [ ] Inspected |
| **Re:Library** | `https://re-library.com` | Bespoke (`ReLibraryExtractor`) | High quality Japanese light novel translations with clean semantic reader formatting and comprehensive volume TOCs. | [x] Working |
| **AsuraScans** | `https://asurascans.com` | Bespoke (In App) | Source web novels for top Manhwa titles (Solo Leveling style, Necromancers, Gates). | [x] Working |
| **RoliaScan** | `https://roliascan.com` | Bespoke (In App) | Korean Otome Isekai, Villainess, and Romance Fantasy translations. | [x] Working |
| **Kakuyomu** | `https://kakuyomu.jp` | Kadokawa Official (In App) | Official Japanese webnovel platform with 100,000+ raw Japanese light novels. | [x] Working |

---

## Next Steps for Integration

1. **Your Inspection**: Browse the URLs above that interest you, check whether they load cleanly in your browser without aggressive IP blocking, and mark `[x]` on your choices.
2. **Implementation Strategy**:
   * **Tier 1 (Instant Plug-in)**: Enable `Royal Road` and `Scribble Hub` (extractors are already written in your codebase).
   * **Tier 2 (Template Reuse)**: Sites running **WordPress Madara** (BoxNovel, Woopread, RainOfSnow) or **NovelFull** (Novel12, Novel80, LightNovelWorld) can be activated in `source_registry.dart` with simple config entries without writing new extractors.
   * **Tier 3 (Bespoke APIs)**: Build bespoke extractors for high-impact content sources (Standard Ebooks, Clarkesworld, Baen Free Library).
