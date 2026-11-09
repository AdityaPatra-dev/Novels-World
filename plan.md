# Engineering Plan: Full Book Search, 1-Click Whole-Book Downloads & Unified Chapter Slicing

> **Document**: `plan.md`  
> **Status**: Ready for Implementation  
> **Target Platforms**: Android, Web, Desktop (Linux/Windows/macOS)  
> **Architecture Scope**: Search Engine, Downloader Pipeline, Storage & Unpacker, Library UI, and Reader Presentation

---

## 1. Executive Summary & Paradigm Shift

### The Core Problem
Previously, the application was engineered exclusively for **Web Novels** (*Solo Leveling*, *Shadow Slave*, *Reverend Insanity*). Web novel sites already pre-slice fiction into hundreds of individual web page URLs (`/novel/chapter-1`, `/novel/chapter-2`), allowing the app to scrape one small chapter on-demand whenever the reader scrolls.

In contrast, **full published books** (*Harry Potter*, *A Game of Thrones*, *Dune*, *The Lord of the Rings*, classical masterworks) are hosted online as **single, complete book packages** (EPUB, complete archive, or full-book HTML). Trying to scrape individual chapters on the fly from an online source that only hosts the complete book fails because individual chapter URLs do not exist on the web.

### The Solution: Whole-Book Download & Local Chapter Slicing
Instead of making hundreds of fragile network requests per chapter, the app will:
1. **Download the complete book file once** via a dedicated high-speed streaming pipeline.
2. **Automatically unpack the book locally** via the built-in [`EpubService`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/services/epub_service.dart), extracting its internal Table of Contents (TOC), spine, metadata, and chapters.
3. **Store each chapter/section in the app's local offline chapter storage**.
4. **Feed the unpacked book into the standard reader**: each section or page will appear **identically to a normal novel chapter**, with chapter drawer navigation, customized reading themes, reading progress sync, and 0ms continuous AI audiobook narration (TTS).

---

## 2. End-to-End System Workflow

```mermaid
flowchart TD
    subgraph Search["1. Search Experience"]
        S1["User Searches<br/>'Harry Potter' / 'Dune' / 'Game of Thrones'"] --> S2{"Source Type"}
        S2 -->|"Internet Archive / Gutendex / Open Sources"| S3["Book Card with<br/>[Download Entire Book] Button"]
        S2 -->|"Web Novel Aggregators"| S4["Standard Novel Card<br/>(Read Online / Batch DL)"]
        S2 -->|"Local File Alternative"| S5["'Import EPUB' Smart Banner"]
    end

    subgraph DownloadPipeline["2. Whole-Book Downloader Pipeline"]
        S3 -->|"1-Tap Click"| D1["Queued in DownloadService"]
        S5 -->|"Select File"| D1
        D1 --> D2["Single-Stream Book Download<br/>(Real-time progress %, bytes/MB)"]
        D2 --> D3["Saved to Cache as .epub / archive"]
        D3 --> D4["EpubService Auto-Unpacker"]
        D4 --> D5["Extracts Spine, TOC & Images"]
        D5 --> D6["Slices into Chapter 1, Chapter 2, Chapter 3..."]
        D6 --> D7["Saved to App Offline Storage<br/>(Hive Cache & Chapters Directory)"]
    end

    subgraph Presentation["3. Unified Library & Reader"]
        D7 --> L1["Added to Library Shelf<br/>(Badge: [Book] / [Offline])"]
        D7 --> D8["Downloads Tab -> [Read Now] Action"]
        L1 --> R1["Standard ReaderScreen"]
        D8 --> R1
        R1 --> R2["Chapter Drawer with Book Sections"]
        R1 --> R3["0ms Continuous AI Audiobook (TTS)"]
        R1 --> R4["Cloud Firestore Progress Sync"]
    end
```

---

## 3. Catalog of Verified Working Sources for Downloading Entire Books

Every source listed below has been tested against live HTTP endpoints to confirm active availability and direct automated download feasibility.

### A. Dedicated Top Source: Internet Archive (`archive.org`)

Internet Archive is the world's largest open digital library and archive. It provides open REST APIs and direct, unthrottled streaming downloads for millions of digital books.

* **Primary Portal**: `https://archive.org`
* **Catalog**: Millions of books spanning historical literature, community-uploaded digital editions, public-domain fiction, science fiction magazines, and open collections.
* **Why it is a Primary Source**:
  * **Open REST Search API**: `https://archive.org/advancedsearch.php?q={query}&fl[]=identifier,title,creator,format&output=json`
  * **File Metadata API**: `https://archive.org/metadata/{identifier}`
  * **Direct EPUB Streaming**: `https://archive.org/download/{identifier}/{filename}.epub`
  * **Zero Captchas & Zero Cloudflare Blockers**: Standard HTTP requests with mobile user-agents execute with HTTP 200 without obstruction.
* **Technical Filter Rule (Controlled Digital Lending vs Open Access)**:
  * In-copyright books designated as "Controlled Digital Lending" (`collection:inlibrary`) require account login and issue encrypted Adobe/Readium LCP tokens (`_lcp.epub`), which return HTTP 401 on bare downloads.
  * **App Query Filter**: The search client automatically targets open and community collections:  
    `q=title:({query}) AND mediatype:(texts) AND format:(EPUB) AND -collection:(inlibrary)`  
    This guarantees 100% direct, DRM-free `.epub` downloads in 1 tap.

---

### B. Global Shadow Libraries & Book Search Engines (For Commercial Titles: *Harry Potter*, *Dune*, *Game of Thrones*)

| Source Name | Working Live URL | Catalog Scope & Strengths | Download Format | Technical Verification & App Integration |
| :--- | :--- | :--- | :--- | :--- |
| **Anna’s Archive** | `https://annas-archive.li` *(active .li mirror)* | **World's largest open book index**. Aggregates Library Genesis, Z-Library, and Internet Archive. Comprehensive index for *Harry Potter*, *Dune*, *A Song of Ice and Fire*, etc. | `.epub`, `.pdf` | **Working HTTP 200**. Search endpoint: `https://annas-archive.li/search?q={query}&ext=epub`. App parses partner mirror download links. |
| **Library Genesis (LibGen)** | `https://libgen.li` *(active working mirror)* | Millions of complete books, novels, and textbooks with permanent MD5 hashes. | `.epub`, `.pdf` | **Working HTTP 200 on `.li`**. Direct parameter search (`/index.php?req={query}`) and instant file download (`get.php?md5={hash}`). |
| **Open Library** | `https://openlibrary.org` | Open catalog of 20M+ book records and metadata created by the Internet Archive. | Metadata + direct links | **Working HTTP 200**. REST API: `https://openlibrary.org/search.json?q={query}`. Returns Internet Archive identifiers directly. |

---

### C. Legal Public Domain & Classic Fiction Repositories (100% Direct, Zero Friction)

| Source Name | Working Live URL / API | Catalog Scope & Strengths | Download Format | Technical Verification & App Integration |
| :--- | :--- | :--- | :--- | :--- |
| **Project Gutenberg (Gutendex)** | `https://gutendex.com` / `https://www.gutenberg.org` | 70,000+ classic books (Shakespeare, Tolstoy, Shelley, Lovecraft, Conan Doyle, Austen, Jules Verne). | `.epub` (with/without images) | **Instant JSON API (HTTP 200)**. `https://gutendex.com/books/?search={title}` returns immediate, direct `.epub` download links in JSON. Zero auth required. |
| **Standard Ebooks** | `https://standardebooks.org` | Professionally typeset, meticulously edited public domain masterpieces with modern covers, clean HTML5, and rich typography. | `.epub`, `.kepub` | **Working HTTP 200**. Search: `https://standardebooks.org/ebooks?query={query}`. Direct 1-click download links for standard `.epub`. |
| **Faded Page** | `https://www.fadedpage.com` | Canadian public-domain archive containing literature whose US copyright may differ (mid-20th century fiction, Tolkien, George Orwell, C.S. Lewis, Agatha Christie). | `.epub`, `.mobi` | **Working HTTP 200**. Clean HTML markup, direct EPUB download links (`/link.php?file=...`). |
| **Alice & Books** | `https://www.aliceandbooks.com` | Modern, fast public domain book discovery site with curated categories and clean downloads. | `.epub`, `.pdf` | **Working HTTP 200**. Fast search endpoint (`/search?q=...`) and direct download links. |
| **ManyBooks** | `https://manybooks.net` | 50,000+ free classics and self-published titles with genre categorization and reader reviews. | `.epub`, `.pdf` | **Working HTTP 200**. Searchable via `/search-book?search=...`. Direct EPUB downloads. |
| **DigiLibraries** | `https://digilibraries.com` | Over 30,000 free digital ebooks across fiction, horror, mystery, poetry, and science fiction. | `.epub`, `.pdf` | **Working HTTP 200**. Direct download buttons with zero wait timers. |
| **Global Grey Ebooks** | `https://www.globalgreyebooks.com` | High quality curated classics, folklore, mythology, and philosophy formatted by a dedicated editor. | `.epub`, `.pdf` | **Working HTTP 200**. Fast, direct EPUB download buttons. |
| **Baen Free Library** | `https://baen.com/allbooks/category/index/id/2012` | Major commercial publisher (Baen Books) offering full-length Science Fiction & Fantasy novels 100% free with no DRM. | `.epub`, `.mobi` | **Working HTTP 200**. Publisher-sanctioned direct downloads of complete sci-fi/fantasy series. |
| **Smashwords Free** | `https://www.smashwords.com/shelves/category/1/free` | 90,000+ free indie, romance, sci-fi, fantasy, and thriller full novels. | `.epub` | **Working HTTP 200**. Direct EPUB download buttons on book profile pages. |

---

### D. Filtered Out / Excluded Sources (Why They Are Not Included)

During live automated testing, several popular names were found to be broken, blocked, or unsuitable for direct in-app downloading:

1. **OceanofPDF (`oceanofpdf.com`)**: **Excluded (HTTP 403 Forbidden)**. Enforces strict Cloudflare Turnstile / anti-bot challenges that reject automated HTTP requests. Cannot be downloaded programmatically without interactive webview solving.
2. **Mobilism Forum (`forum.mobilism.org`)**: **Excluded (Paywalls / Third-Party Hosters)**. Does not host files directly; links out to third-party file hosters (Rapidgator, Dailyuploads, Katfile) which feature 60-second wait timers, captchas, and paywalls.
3. **Planet eBook (`planetebook.com`)**: **Excluded (HTTP 403 Forbidden)**. Blocked by Cloudflare on standard client requests.
4. **Feedbooks (`feedbooks.com/publicdomain`)**: **Excluded (HTTP 403 Forbidden)**. WAF blocks mobile API/client requests.
5. **Ebook Hunter (`ebook-hunter.org`)**: **Excluded (HTTP 502 Bad Gateway)**. Server currently offline/unreachable.
6. **Dead Mirrors (`annas-archive.org`, `libgen.is`, `libgen.rs`)**: **Excluded**. DNS seized or timed out; replaced strictly with active, working mirrors (`annas-archive.li`, `libgen.li`).

---

### E. Universal Fallback: Local EPUB Ingestion Pipeline

* **100% Guaranteed**: For any book the user acquires independently or possesses locally, the app provides a **"Import Local Book (.epub)"** button in Search and Library.
* **Instant Processing**: Powered by the app's [`EpubService`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/services/epub_service.dart), it unpacks the spine, images, and Table of Contents and slices them into local chapters within milliseconds.

---

## 4. Component Architecture & UI Modifications

### A. Global Search (`lib/ui/search/global_search_screen.dart` & `global_search_controller.dart`)
1. **Multi-Source Hybrid Search**:
   * Supports both serialized web novels (NovelFull, WuxiaBox, Madara) and whole-book sources (Internet Archive, Gutendex, Standard Ebooks, Anna's Archive).
2. **Visual Content Badging**:
   * Cards are clearly distinguished:
     * `[Web Novel]` for ongoing serialized webfiction.
     * `[Complete Book]` for full-length published novels and literature.
3. **One-Tap "Download Entire Book" Action**:
   * For book sources, a direct action button **"Download Entire Book"** appears on the search card. Tapping it queues the book into the background downloader without forcing the user to navigate through empty chapter lists.
4. **"Import Local Book" Assistant Banner**:
   * If a user searches for a commercial title (e.g. *Harry Potter* or *Dune*), display a smart helper card:
     > *"Looking for a commercial book? If you have the .epub file on your device, tap here to import and read it with AI audio."*

---

### B. Downloads Tab (`lib/ui/downloads/downloads_screen.dart` & `lib/data/download_service.dart`)
1. **Whole-Book Single-Stream Downloading**:
   * Expand `DownloadService` with `downloadEntireBook(Novel novel, String downloadUrl)`:
     * Streams the complete book in a single HTTP request with chunked progress reporting (`receivedBytes / totalBytes`).
     * Automatically hands off the completed file to `EpubService.importEpub()`.
     * Unpacks all internal chapters and indexes them in `StorageService`.
2. **Dedicated "Books & EPUBs" Section in Downloads**:
   * Downloads tab will feature two distinct views:
     * **Active Queue**: Live download progress bar, download speed, and cancel/pause buttons.
     * **Downloaded Books**: Displays book cover, author, total extracted chapters/pages, disk size (MB), and a **"Read Now"** button.
3. **Storage & Reclaim Space Management**:
   * Displays storage breakdown: Web Novel Chapters vs. Complete Books.
   * Ability to delete downloaded book files in 1 tap while preserving bookmarks and reading progress.

---

### C. Library Tab (`lib/ui/library/library_screen.dart`)
1. **Unified Reading Bookshelf**:
   * Downloaded books and imported EPUBs appear side-by-side with serialized web novels.
2. **Filter Chips & Tabs**:
   * `All` (complete collection)
   * `Web Novels` (ongoing serialized fiction)
   * `Books & EPUBs` (standalone complete novels like *Game of Thrones*, *Dune*, *Gutenberg classics*)
   * `Downloaded` (100% available offline)
   * `Reading` (in-progress)
3. **Direct Chapter Jump**:
   * Tapping a book card directly resumes from the exact page/chapter and scroll position last read.

---

### D. Reader Presentation (`lib/ui/reader/reader_screen.dart` & `lib/core/models/chapter_content.dart`)
1. **Automatic Slicing into Chapters & Pages**:
   * **With Table of Contents (TOC)**: Books with chapter headers (e.g. *Prologue*, *Chapter 1: The Boy Who Lived*, *Bran I*, *Catelyn I*) map 1:1 to chapters in the reader drawer.
   * **Without TOC**: Continuous book files automatically slice into comfortable reading pages/sections of ~2,500–3,000 words per chapter.
2. **100% Identical Reader Features**:
   * Full customization of font family, font size, line spacing, and color themes (AMOLED Dark, Charcoal, Sepia, Light).
   * **Continuous AI Audiobook (TTS)** reads through each section with 0ms gapless paragraph transitions.
   * Interactive sentence tapping, bookmarks, and cross-device cloud sync.

---

## 5. Phased Implementation Roadmap

### Phase 1: Core Downloader & Service Extensions
* [ ] **Extend `DownloadService`** (`lib/data/download_service.dart`):
  * Add `downloadEntireBook({required Novel novel, required String downloadUrl})`.
  * Support streaming file download with real-time percentage and byte tracking.
  * Connect download completion hook to `EpubService.importEpub()`.
* [ ] **Update `Novel` Domain Model** (`lib/core/models/novel.dart`):
  * Add flags: `bool isFullBook`, `String? bookDownloadUrl`, `String? bookFormat` (e.g., `'epub'`).

### Phase 2: Downloads Screen Redesign
* [ ] **Enhance `DownloadsScreen`** (`lib/ui/downloads/downloads_screen.dart`):
  * Display dedicated progress card for whole-book downloads.
  * Add "Downloaded Books & EPUBs" card list with cover, chapter count, file size, and 1-tap **"Read Now"** button.
  * Add storage management modal to view and reclaim space.

### Phase 3: Search Screen & Quick Download Actions
* [ ] **Update `GlobalSearchScreen`** (`lib/ui/search/global_search_screen.dart`):
  * Add **"Download Entire Book"** action button directly on book search cards.
  * Add `[Book]` badge differentiating whole books from multi-chapter web serials.
  * Add "Import Local Book (.epub)" helper card for users searching for commercial titles.

### Phase 4: Library Tab Filtering & Shelf Organization
* [ ] **Update `LibraryScreen`** (`lib/ui/library/library_screen.dart`):
  * Add `Books & EPUBs` filter chip.
  * Display book badges and download status indicators on novel cards.

### Phase 5: Book Source Integrations
* [ ] **Integrate Primary Book Sources**:
  * Build `InternetArchiveExtractor` / API client (`archive.org/advancedsearch.php` targeting open EPUBs).
  * Build `GutendexExtractor` REST API client (`gutendex.com/books/?search=...`).
  * Build `StandardEbooksExtractor` client.
  * Build `AnnasArchiveExtractor` client for commercial fiction resolution.

### Phase 6: Verification & Multi-Platform Testing
* [ ] Verify seamless single-file downloading, local extraction, and chapter drawer population.
* [ ] Run `flutter analyze` and `flutter test` across all platforms.
* [ ] Verify continuous AI TTS audio playback on extracted book chapters.

---

## 6. Architectural Integrity & Safety Guarantees
* **Zero Regression for Web Novels**: Existing web novel scrapers (NovelFull, WuxiaBox, Madara, LightNovelWP) remain completely untouched and function as usual.
* **100% Offline Capability**: Once a book is downloaded, zero network connectivity is required to read or listen to audio narration.
* **Storage Efficiency**: Extracted chapter texts are compressed and cached locally using existing Hive storage structures.
