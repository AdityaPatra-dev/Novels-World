# Novels-World: Phase-by-Phase Implementation Plan

This document tracks the phased development of the **Novels-World** app based on the master specifications in [ChatGPT-Design Novel Reading App-20261012-2358.md](file:///home/adityapatra/Documents/GitHub/Novels-World/ChatGPT-Design%20Novel%20Reading%20App-20261012-2358.md) and [NOVEL_SOURCES_AND_TEMPLATES.md](file:///home/adityapatra/Documents/GitHub/Novels-World/NOVEL_SOURCES_AND_TEMPLATES.md).

---

## Roadmap Overview

| Phase | Milestone | Status | Key Deliverables |
| :--- | :--- | :--- | :--- |
| **Phase 1** | **Foundation, Extractor & Reader** | 🟢 **COMPLETED** | Flutter 3.44 scaffold, Domain Models, Universal `MadaraExtractor` (76+ sites support), Local Storage & Cache, Multi-source registry, Reading UI with themes (AMOLED/Dark/Sepia/Light), typography controls, 100% test pass. |
| **Phase 2** | **3 Neural TTS Engines & Real-Time Audio** | 🟢 **COMPLETED** | `TtsModelRegistry` cataloging the 3 specialized novel models + zero-download fallback, `KokoroEngine` (Expressive Storyteller), `PiperEngine` (Ultra-Fast VITS), `SherpaEngine` (Asian CJK Specialist), `SystemFallbackEngine`, Real-time sentence `RingBufferManager`, Smart Sleep Timer with 60s smooth volume fade-out, Interactive sentence tapping & Karaoke-style reader highlighting. |
| **Phase 3** | **Offline Library & Batch Downloader** | 🟢 **COMPLETED** | `DownloadService` background queue, rate-limited chapter downloading with retries, 1-click batch options (Next 5, 10, 25, All), live progress bar banner, chapter list badges (downloaded/downloading), storage cache breakdown & clean-up tools. |
| **Phase 4** | **Multi-Source Expansion & Bespoke Sites** | 🟢 **COMPLETED** | LightNovelWP (36+ sites), NovelFull/NovelBin (8+ sites), Royal Road & Scribble Hub bespoke handlers, Source Registry expansion with 11+ configured sources, full test coverage. |

---

## Phase 4 Deliverables (Completed & Verified)

- [x] **Universal LightNovelWP Extractor (`lib/extractors/lightnovelwp_extractor.dart`)**:
  - Covers 36+ WordPress sites powered by the Themesia LightNovelWP template (*Kol Novel*, *KnoxT*, *Light Novel FR*, *AllNovelRead*, *Novels Paradise*, etc.).
  - Extracts search results, popular/directory series (`.listupd .bsx`), cover images, metadata, and author details.
  - Parses chapter listings (`.eplister ul li a`) with descending-to-ascending automatic ordering.
  - Sanitizes chapter reading containers (`.epcontent`) stripping ads (`.sharedaddy`, `.adsbygoogle`), scripts, and navigation links.
- [x] **Universal NovelFull / NovelBin Extractor (`lib/extractors/novelfull_extractor.dart`)**:
  - Covers the high-traffic aggregator network (*NovelFull*, *NovelBin*, *ReadNovelFull*, *LibRead*, *AllNovelFull*, *NovelPing*).
  - Handles both static DOM chapter tables and dynamic AJAX chapter archives (`/ajax/chapter-archive?novelId=...`).
  - Cleans reader container (`#chr-content`) and scrubs aggregator watermark paragraphs.
- [x] **Bespoke Royal Road Extractor (`lib/extractors/bespoke/royalroad_extractor.dart`)**:
  - Premier western original web fiction platform (`royalroad.com`).
  - Scrapes fiction search, best-rated, and latest update listings.
  - Parses fiction details, tags, covers, and chapter table (`#chapters tbody tr[data-url]`).
  - Strips author note portlets (`.author-note-portlet`, `.portlet-body`) to preserve clean story prose.
- [x] **Bespoke Scribble Hub Extractor (`lib/extractors/bespoke/scribblehub_extractor.dart`)**:
  - Major original web fiction and light novel platform (`scribblehub.com`).
  - Scrapes series ranking and search boxes (`.search_main_box`).
  - Parses table of contents (`ol.toc_ol li a`) and handles AJAX pagination fallback.
  - Strips author notes (`.wi_authornotes`) from reading text (`.chp_raw`).
- [x] **Expanded Multi-Source Registry (`lib/extractors/source_registry.dart`)**:
  - Pre-registers 11 active sources across 4 distinct CMS architectures:
    - **Bespoke**: Royal Road (EN), Scribble Hub (EN)
    - **Madara**: FirstKiss Novel, Novel Translate, Lunar Letters, Dao Novel, Foxaholic
    - **LightNovelWP**: AllNovelRead (EN), KnoxT (EN), Light Novel FR (FR), Kol Novel (AR)
    - **NovelFull**: NovelFull (EN), NovelBin (EN)
- [x] **Verification**:
  - `flutter analyze lib/ test/` -> **0 issues found** (0 errors, 0 warnings).
  - `flutter test` -> **All 28 tests passed** across all test suites (`models_test.dart`, `madara_extractor_test.dart`, `tts_engine_test.dart`, `download_service_test.dart`, `extractors_test.dart`, `widget_test.dart`).
  - `flutter build linux --debug` -> **Native Linux binary built successfully** (`build/linux/x64/debug/bundle/novels_world`).
