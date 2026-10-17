# Master Engineering Specification: Novels-World App

**Document Version:** 2.0 (Production Blueprint)  
**Lead Implementer:** AI Coding Agent (Antigravity)  
**Target Platform:** Cross-Platform Modern Novel Reader & Offline Audiobook Engine  
**Companion Analysis:** [NOVEL_SOURCES_AND_TEMPLATES.md](file:///home/adityapatra/Documents/GitHub/Novels-World/NOVEL_SOURCES_AND_TEMPLATES.md)

---

## 1. System Vision & Core Value Proposition

**Novels-World** is a high-performance, offline-first web novel and light novel reader paired with a **real-time, zero-latency local Neural Text-to-Speech (TTS) engine**.

Traditional novel reading apps either force users to rely on robotic, primitive robotic OS voices or require cloud-dependent streaming services with costly APIs and network lag. **Novels-World** bridges this gap:
1. **Aggregates and extracts novels** from the widest web novel ecosystems via unified CMS template extractors (starting with the widely used **WordPress Madara** engine covering 76+ sites).
2. **Streams natural neural narration in real-time** using **three top-tier local neural TTS models** specifically selected for storytelling, long-form fiction, character dialogue, and instant playback.
3. **Guarantees 100% offline functionality**: Novels, chapters, progress, and neural voice models are stored locally, allowing complete reading and audiobook listening with zero internet access.

---

## 2. Core Architecture & Tech Stack

```
┌────────────────────────────────────────────────────────────────────────┐
│                          PRESENTATION LAYER                            │
│  ┌───────────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
│  │   Library & Search    │  │  Novel Details  │  │  Offline Reader  │  │
│  │     (Cover Grid)      │  │  & Chapter TOC  │  │  (Themes/Paging) │  │
│  └───────────┬───────────┘  └────────┬────────┘  └────────┬─────────┘  │
│              │                       │                    │            │
│  ┌───────────┴───────────────────────┴────────────────────┴──────────┐ │
│  │       Audiobook Player Overlay (Floating Bar / Lockscreen)         │ │
│  │     • Real-time Sentence Highlighter   • Sleep Timer Fade-out      │ │
│  │     • Speed: 0.5x - 3.0x               • Model / Voice Switcher    │ │
│  └───────────────────────────────────┬────────────────────────────────┘ │
└──────────────────────────────────────┼─────────────────────────────────┘
                                       │
┌──────────────────────────────────────┼─────────────────────────────────┐
│                           SERVICES LAYER                               │
│  ┌────────────────────────┐          │           ┌──────────────────┐  │
│  │ Extractor Manager      │          │           │ Audio & TTS Engine│ │
│  │ • Madara Engine (76+)  │          │           │ • Sentence Queue │  │
│  │ • LightNovelWP (36+)   │          │           │ • Ring-Buffer    │  │
│  │ • NovelFull Engine     │          │           │ • Audio Track Sync│ │
│  └───────────┬────────────┘          │           └────────┬─────────┘  │
│              │                       │                    │            │
│  ┌───────────▼───────────────────────▼────────────────────▼──────────┐ │
│  │              Local Database & Cache Layer (SQLite)                 │ │
│  │   `novels`  │  `chapters`  │  `reading_progress`  │  `audio_cache` │ │
│  └───────────────────────────────────┬────────────────────────────────┘ │
└──────────────────────────────────────┼─────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼─────────────────────────────────┐
│                      LOCAL NEURAL TTS INFERENCE                        │
│   ┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐  │
│   │ 1. Kokoro-82M      │ │ 2. Piper TTS       │ │ 3. Sherpa-Matcha   │  │
│   │ (Expressive Audio- │ │ (Ultra-Fast VITS,  │ │ (Multi-lingual CJK │  │
│   │  book Narrator)    │ │  Battery-Saver)    │ │  & Asian Names)    │  │
│   └────────────────────┘ └────────────────────┘ └────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Tech Stack Evaluation & Comparison Matrix

To achieve the best possible UI experience (120Hz fluid gestures, responsive typography, zero jank) and native performance on both **phones (specifically Android)** and **laptops (Linux/Windows/macOS)**, we evaluated four primary candidates:

| Evaluation Dimension | **Flutter (Dart + C++ FFI)** *(SELECTED)* | **React Native (Expo)** | **Tauri 2.0 (Rust + Web)** | **Kotlin Multiplatform (KMP)** |
| :--- | :--- | :--- | :--- | :--- |
| **Android UI & Gestures** | ⭐⭐⭐⭐⭐ **120Hz Impeller rendering**, native touch physics, zero WebView stutter | ⭐⭐⭐⭐ Smooth, but JS bridge can drop frames during complex scrolling | ⭐⭐⭐ WebView-based, prone to micro-stutters with 10k+ DOM words | ⭐⭐⭐⭐⭐ 100% native Jetpack Compose on Android |
| **Laptop (Desktop) UX** | ⭐⭐⭐⭐⭐ Native Linux, Windows, macOS windowing & keyboard shortcuts | ⭐⭐ React Native Desktop is brittle, poor Linux support | ⭐⭐⭐⭐⭐ Excellent desktop performance via lightweight webview | ⭐⭐⭐⭐ Compose for Desktop works well, heavier JVM runtime |
| **Neural TTS Streaming** | ⭐⭐⭐⭐⭐ **Zero-copy C++ FFI** via `sherpa_onnx`; instant Float32 PCM streaming | ⭐⭐⭐ JS bridge serialization adds latency & GC pressure | ⭐⭐⭐⭐⭐ High-speed Rust FFI, but Android audio interop is complex | ⭐⭐⭐⭐ C++/JNI bindings, but fragmented across desktop targets |
| **Android Background Audio** | ⭐⭐⭐⭐⭐ **`audio_service`** provides rock-solid Foreground Service & lockscreen controls | ⭐⭐⭐⭐ Community modules exist, but background stability varies by Android OEM | ⭐⭐ Android background audio services in Tauri are nascent & experimental | ⭐⭐⭐⭐⭐ Full native Android `MediaSession` & `Service` control |
| **Scraping & Network** | ⭐⭐⭐⭐⭐ **Zero CORS**, direct socket/TLS via `dio` / `http` on both Android & Laptop | ⭐⭐⭐⭐ Native networking, but fewer robust DOM parsing libraries | ⭐⭐⭐⭐⭐ High-speed Rust reqwest + scraper, bypasses CORS | ⭐⭐⭐⭐ Ktor + Ksoup, but more verbose plugin ecosystem |
| **Offline SQLite Storage** | ⭐⭐⭐⭐⭐ **`drift`**: Reactive, compile-time verified SQLite with migrations | ⭐⭐⭐⭐ WatermelonDB / op-sqlite | ⭐⭐⭐⭐ SQLx / rusqlite in Rust | ⭐⭐⭐⭐ SQLDelight |

---

### 2.2 Final Tech Stack Decision: Flutter (Dart) + Native C++ ONNX (`sherpa_onnx`)

**Why this is the winning choice:**
1. **Unrivaled Android Phone Experience**:
   - Web novel chapters frequently contain 5,000+ words. In WebViews or JS-bridge frameworks, fast continuous scrolling or font resizing often produces frame drops. Flutter compiles directly to machine code using the **Impeller GPU renderer**, guaranteeing consistent **120fps scrolling**, fluid pinch-to-zoom font scaling, and instant page-flip curl animations.
   - Built-in support for Android 120Hz high-refresh displays via `flutter_displaymode`.
2. **First-Class Android Background Audio & Lock Screen Lifecycle**:
   - Novel readers are primarily listened to while the user is commuting, walking, or falling asleep with the screen turned off. Android's aggressive Doze mode and manufacturer battery killers (Samsung, Xiaomi, OnePlus) aggressively kill background processes.
   - Flutter's `audio_service` implements a true native Android `ForegroundService` with `MediaSessionCompat`, providing:
     - Lockscreen album art (novel cover), title, and chapter display.
     - Notification playback actions: Play/Pause, Skip 10s, Next Sentence.
     - Headset button events (Bluetooth play/pause).
     - Audio Focus handling (smoothly ducking or pausing when phone calls or GPS directions arrive).
3. **High-Performance In-Memory Neural TTS (Zero Serialization Overhead)**:
   - Neural TTS engines output raw Float32 audio samples at 22,050Hz or 24,000Hz.
   - Through Dart's Foreign Function Interface (`dart:ffi`), Flutter communicates directly with `sherpa_onnx` C++ libraries in memory.
   - Runs **Kokoro-82M**, **Piper VITS**, and **Matcha-TTS** on mobile CPU cores using ARM NEON optimizations and multi-threading without any GC pauses or UI blocking.
4. **First-Class Laptop / Desktop Support**:
   - Flutter compiles to native binary executables on Linux, Windows, and macOS without relying on Electron's heavy multi-gigabyte memory footprint.
   - Adapts cleanly to wide laptop displays with a responsive two-column layout (Chapter TOC on left, Reader on right, keyboard navigation with spacebar/arrow keys).
5. **Direct Socket Scraping Without CORS**:
   - Dart's `HttpClient` / `dio` operates at the OS socket level. It does not enforce browser CORS restrictions, allowing custom headers, arbitrary User-Agents, cookie jars, and direct scraping of Madara/WordPress novel sites.

---

### 2.3 Concrete Technology & Dependency Blueprint

```yaml
# Core pubspec.yaml Architecture Specification
dependencies:
  flutter:
    sdk: flutter

  # --- State Management & Architecture ---
  flutter_riverpod: ^2.6.1       # Reactive, testable state management
  freezed_annotation: ^2.4.4     # Immutable models & unions

  # --- Local Storage & Offline Database ---
  drift: ^2.24.0                 # High-performance, type-safe reactive SQLite
  sqlite3_flutter_libs: ^0.5.24  # Bundled native SQLite binaries for Android/Desktop
  path_provider: ^2.1.5          # System directories for cached chapters & voice models

  # --- Real-Time Neural TTS & Audio Pipeline ---
  sherpa_onnx: ^1.10.36          # Native C++ ONNX engine (Kokoro-82M, Piper VITS, Matcha-TTS)
  audio_service: ^0.18.17        # Android Foreground Service, MediaSession & lockscreen controls
  just_audio: ^0.9.42            # Gapless PCM audio streaming and ring-buffer playback

  # --- Novel Scraping & Network Layer ---
  dio: ^5.7.0                    # High-speed HTTP client (CORS-free, custom headers, cookies)
  html: ^0.15.5                  # Fast DOM selector and parser (CSS selectors)
  cookie_jar: ^4.0.8             # Persistent session & cookie storage for bypass

  # --- UI & Reader Ergonomics (Android-First) ---
  flutter_displaymode: ^0.6.0    # Forces 120Hz / 90Hz smooth refresh rate on Android devices
  scrollable_positioned_list: ^0.3.8 # Instant index-based sentence scrolling during TTS playback
  google_fonts: ^6.2.1           # High-legibility reading fonts (Merriweather, Lora, Literata, Inter)
  wakelock_plus: ^1.2.8          # Prevents screen sleep during reading sessions
```

---

## 3. Real-Time Neural TTS Engines (The 3 Specialized Models)

To deliver an exceptional novel reading experience, the app bundles and supports **three distinct, state-of-the-art local neural TTS models**, each optimized for a specific reading persona and performance envelope:

| Feature | **Model 1: Kokoro-82M** | **Model 2: Piper TTS** | **Model 3: Sherpa-Matcha (CJK)** |
| :--- | :--- | :--- | :--- |
| **Primary Specialty** | **Audiophile Storyteller** (Expressive narrative & dialogue) | **Ultra-Fast Workhorse** (Zero latency, low battery & RAM) | **Multi-Lingual CJK Specialist** (Asian names, cultivation terms) |
| **Architecture** | StyleTTS2 + ISTFT decoder (82M params) | VITS neural architecture (ONNX) | Matcha-TTS / VITS with CJK phonemizer |
| **Real-Time Factor (RTF)**| ~0.15x – 0.25x on CPU (Fast) | **~0.05x on CPU** (Ultra-fast, 20x real-time) | ~0.18x on CPU |
| **Latency to First Audio** | **< 250ms** (sentence streaming) | **< 50ms** (instant) | **< 200ms** |
| **Voice Footprint** | ~82MB ONNX + ~15MB voice embeddings | ~25MB – 55MB per voice model | ~45MB – 70MB |
| **Best Used For** | Western fantasy, romance, deep character dialogues, immersive listening | Long multi-hour binge reading, low-end phones, battery conservation | Xianxia, Wuxia, LitRPG, Japanese Light Novels with honorifics |

---

### Detailed Breakdown of the 3 Models

#### 1. Model 1: Kokoro-82M (The Expressive Storyteller)
- **Why it is superior for novels**: Traditional TTS models read text with a robotic, flat monotony that causes "listening fatigue" within 10 minutes. Kokoro-82M was trained with expressive prosody, capturing dialogue tags, emotional inflections, and natural breathing pauses.
- **Key Voices**:
  - `af_bella` / `af_sarah`: Warm, natural female narrative tones with excellent pacing.
  - `am_michael` / `am_adam`: Deep, authoritative audiobook narrators with crisp diction.
- **Inference Pipeline**: Runs via `kokoro-onnx` using quantized INT8 or FP32 weights on CPU / WebGPU.

#### 2. Model 2: Piper TTS (The Ultra-Fast & Resource-Efficient Workhorse)
- **Why it is superior for novels**: Consumes virtually no battery or RAM. Ideal for users reading on older phones or listening continuously for 6+ hours. Guaranteed deterministic output with zero crashes or out-of-memory spikes.
- **Key Voices**:
  - `en_US-lessac-high`: Studio-grade clarity, steady novel pacing.
  - `en_US-bryce-medium`: Lively, dynamic male narrator.
  - `en_US-amy-medium`: Gentle, smooth narration.
- **Inference Pipeline**: Direct ONNX VITS inference with espeak-ng phonemizer.

#### 3. Model 3: Sherpa-ONNX / Matcha-TTS (The Multi-Lingual & Asian Name Specialist)
- **Why it is superior for novels**: Translated light novels and web novels (Korean, Chinese, Japanese) are filled with non-English names (*Dongfang Bai*, *Linley Baruch*, *Meng Hao*), cultivation ranks (*Jie Dan*, *Nascent Soul*), and honorifics (*senpai*, *hyung*, *oppa*). Standard Western models mangle these words into unpronounceable gibberish. Sherpa-Matcha incorporates CJK phonemic rules and pinyin-aware pronunciation trees.
- **Key Voices**:
  - Bilingual EN/ZH and EN/JA models.
- **Inference Pipeline**: Sherpa-ONNX C++ / WASM runtime.

*(Optional Zero-Download Fallback: When the user has an active internet connection and does not want to download local weights, the app also supports Microsoft Edge Natural Voices via real-time WebSocket streaming).*

---

### Real-Time Streaming & Sentence Ring-Buffer Engine

A typical novel chapter contains **2,500 to 5,000 words** (15 to 30 minutes of spoken audio). Generating the entire chapter before playing would force the user to wait 30–60 seconds.

**The Solution: Real-Time Sentence-Level Producer-Consumer Queue**

```
 [Raw Chapter Text] 
         │
         ▼
 ┌────────────────────────────────────────────────────────┐
 │ 1. Text Cleaner & Semantic Sentence Segmenter          │
 │    • Strips author notes, web links, translator ads    │
 │    • Splits into sentences based on punctuation (.!?)  │
 └───────────────────────┬────────────────────────────────┘
                         │ Array of Sentences [S0, S1, S2, S3...]
                         ▼
 ┌────────────────────────────────────────────────────────┐
 │ 2. Audio Producer (Background TTS Worker)              │
 │    • Immediately synthesizes S0 -> sends to Player    │
 │    • Synthesizes S1, S2, S3 into a 3-sentence buffer   │
 └───────────────────────┬────────────────────────────────┘
                         │ Audio PCM chunks
                         ▼
 ┌────────────────────────────────────────────────────────┐
 │ 3. Audio Consumer (Playback Ring-Buffer)               │
 │    • Plays S0 instantly (latency < 250ms)              │
 │    • Emits `onSentenceChange(index)` for UI Highlight  │
 │    • Seamless gapless transition S0 -> S1 -> S2        │
 └────────────────────────────────────────────────────────┘
```

#### Playback & Ergonomic Controls
- **Karaoke-Style Sentence Highlighting**: As sentence $N$ plays, the reader auto-scrolls and visually highlights the matching paragraph/sentence on screen.
- **Smart Sleep Timer**:
  - 15 min, 30 min, 45 min, 60 min, or **"End of Chapter"**.
  - **Volume Fade-Out**: Over the final 60 seconds, volume smoothly ramps down from 100% to 0% to prevent jolting the user awake.
- **Audio Controls**: Variable speed ($0.75\times$ to $2.5\times$ with pitch correction), sentence rewinding ($-10\text{s}$ / $+10\text{s}$), and background playback with lock screen media notifications.

---

## 4. Extractor Architecture & Widely Used Template Strategy

As analyzed in detail in [NOVEL_SOURCES_AND_TEMPLATES.md](file:///home/adityapatra/Documents/GitHub/Novels-World/NOVEL_SOURCES_AND_TEMPLATES.md), targeting individual websites one by one is inefficient. We use the **Multi-Source Template Strategy**:

### Tier 1 Priority: The Universal WordPress Madara Engine (76+ Sites)
The app's first production extractor targets the **WordPress Madara theme**, which accounts for ~45% of active novel reading sites:
- **Unified AJAX Chapter Pagination**:
  - Endpoint: `POST {baseUrl}/wp-admin/admin-ajax.php`
  - Body: `action=manga_get_chapters&manga={manga_id}`
- **Standard Selectors**:
  - Title: `.post-title h1`
  - Cover: `.summary_image img`
  - Author: `.author-content a`
  - Genres: `.genres-content a`
  - Content: `div.text-left, div.reading-content, div.entry-content`

### Primary Verification Sources:
1. `FirstKissNovel` (`https://1stkissnovel.org/`)
2. `NovelTranslate` (`https://noveltranslate.com/`)
3. `LunarLetters` (`https://lunarletters.com/`)
4. `Foxaholic` (`https://www.foxaholic.com/`)

### Tier 2 Templates (Config-Driven Plugins):
- **LightNovelWP Engine**: 36+ sites (`Kol Novel`, `KnoxT`, `Light Novel FR`, `AllNovelRead`).
- **NovelFull / NovelBin Engine**: High-traffic aggregators (`NovelFull`, `NovelBin`, `ReadNovelFull`, `LibRead`).
- **ReadWN Engine**: Machine translation networks (`WuxiaBox`, `Ltnovel`, `FanMTL`).

### Tier 3 Bespoke Sites (Handled Individually Later):
- **Western Platforms**: [Royal Road](https://www.royalroad.com), [Scribble Hub](https://www.scribblehub.com), [AO3](https://archiveofourown.org).
- **Official Publishers**: [Wuxiaworld](https://www.wuxiaworld.com), [Webnovel](https://www.webnovel.com).
- **Obfuscated Sites**: [Chrysanthemum Garden](https://chrysanthemumgarden.com) (requires custom font deciphering).

---

## 5. Database Schema (SQLite)

All reading data, downloaded novels, chapters, and TTS states are preserved in a clean SQLite schema:

```sql
-- 1. NOVELS TABLE
CREATE TABLE IF NOT EXISTS novels (
    id TEXT PRIMARY KEY,               -- e.g. "madara_1stkiss_martial-peak"
    source_id TEXT NOT NULL,           -- e.g. "firstkissnovel"
    title TEXT NOT NULL,
    author TEXT,
    description TEXT,
    cover_url TEXT,
    cover_blob BLOB,                   -- Cached offline cover image
    genres TEXT,                       -- JSON array: ["Action", "Fantasy"]
    status TEXT DEFAULT 'UNKNOWN',     -- ONGOING, COMPLETED, UNKNOWN
    source_url TEXT NOT NULL,
    in_library INTEGER DEFAULT 0,      -- 1 = Bookmarked in user library
    last_read_chapter_id TEXT,
    last_read_at INTEGER,
    created_at INTEGER NOT NULL
);

-- 2. CHAPTERS TABLE
CREATE TABLE IF NOT EXISTS chapters (
    id TEXT PRIMARY KEY,               -- e.g. "madara_1stkiss_martial-peak_ch-100"
    novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
    chapter_number REAL,
    title TEXT NOT NULL,
    url TEXT NOT NULL,
    release_date TEXT,
    download_status TEXT DEFAULT 'NOT_DOWNLOADED', -- NOT_DOWNLOADED, DOWNLOADING, DOWNLOADED
    downloaded_at INTEGER,
    created_at INTEGER NOT NULL
);

-- 3. CHAPTER CONTENT TABLE (Separated for storage performance)
CREATE TABLE IF NOT EXISTS chapter_contents (
    chapter_id TEXT PRIMARY KEY REFERENCES chapters(id) ON DELETE CASCADE,
    novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
    raw_text TEXT NOT NULL,            -- Clean parsed text ready for reader & TTS
    html_content TEXT                  -- Optional formatted HTML
);

-- 4. READING PROGRESS TABLE
CREATE TABLE IF NOT EXISTS reading_progress (
    novel_id TEXT PRIMARY KEY REFERENCES novels(id) ON DELETE CASCADE,
    chapter_id TEXT NOT NULL REFERENCES chapters(id),
    scroll_position REAL DEFAULT 0.0,  -- Percentage (0.0 to 1.0)
    current_sentence_index INTEGER DEFAULT 0, -- Exact sentence for audio sync
    updated_at INTEGER NOT NULL
);

-- 5. TTS VOICE CONFIGURATION & CACHE
CREATE TABLE IF NOT EXISTS tts_settings (
    key TEXT PRIMARY KEY,
    selected_model TEXT DEFAULT 'kokoro',     -- kokoro, piper, sherpa
    selected_voice TEXT DEFAULT 'af_bella',
    speed REAL DEFAULT 1.0,
    pitch REAL DEFAULT 1.0,
    highlight_active_sentence INTEGER DEFAULT 1,
    sleep_timer_minutes INTEGER DEFAULT 0
);
```

---

## 6. Phased Implementation Roadmap & Verification Plan

```
  ┌─────────────────────────────────────────────────────────────┐
  │  PHASE 1: Foundation & The Widely Used Target (Madara)      │
  │  ─────────────────────────────────────────────────────────  │
  │  [✓] Catalog analysis & template mapping                    │
  │  [ ] SQLite database setup & migrations                     │
  │  [ ] Universal MadaraExtractor engine + 2 active sources    │
  │  [ ] Clean Reader UI with custom font/theme settings        │
  │  Acceptance Criteria:                                       │
  │  • Search novel on FirstKissNovel / NovelTranslate          │
  │  • Fetch chapter list and read Chapter 1 in offline reader  │
  └──────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  PHASE 2: The 3 Real-Time Neural TTS Engines                │
  │  ─────────────────────────────────────────────────────────  │
  │  [ ] Integrate ONNX Runtime with WebGPU / CPU threads       │
  │  [ ] Model 1: Kokoro-82M engine (af_bella, am_michael)     │
  │  [ ] Model 2: Piper TTS engine (lessac, bryce)             │
  │  [ ] Model 3: Sherpa-Matcha (Asian CJK novel names)         │
  │  [ ] Sentence Segmenter & Real-time Ring-Buffer (<250ms)   │
  │  [ ] Karaoke Sentence Highlighter on Reader screen          │
  │  [ ] Sleep timer with smooth volume fade-out                │
  │  Acceptance Criteria:                                       │
  │  • Cut internet connection (offline test)                   │
  │  • Audio begins playing in <300ms from clicking "Listen"    │
  │  • Switching between Kokoro, Piper, and Sherpa works on fly │
  └──────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  PHASE 3: Offline Library & Chapter Batch Downloader        │
  │  ─────────────────────────────────────────────────────────  │
  │  [ ] Library shelf UI with reading progress badges          │
  │  [ ] Background chapter batch downloader (1-click download) │
  │  [ ] Full offline verification (zero HTTP traffic)          │
  │  Acceptance Criteria:                                       │
  │  • Download 20 chapters in background with retry logic      │
  │  • Open reader and listen via TTS with Wi-Fi disabled       │
  └──────────────────────────────┬──────────────────────────────┘
                                 │
                                 ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  PHASE 4: Template Expansion (100+ Sources) & Bespoke Sites │
  │  ─────────────────────────────────────────────────────────  │
  │  [ ] LightNovelWP extractor (36+ sites)                     │
  │  [ ] NovelFull extractor (NovelFull, NovelBin)              │
  │  [ ] Bespoke handlers: Royal Road & Scribble Hub            │
  │  [ ] Chrysanthemum Garden font de-obfuscation decoder       │
  └─────────────────────────────────────────────────────────────┘
```

---

## 7. Immediate Next Implementation Step

Following the plan, the immediate implementation starts at **Phase 1**:
1. Initialize the Flutter workspace structure (`lib/core`, `lib/extractors`, `lib/reader`, `lib/tts`, `lib/data/database`, `lib/services/audio`).
2. Build the **`MadaraExtractor`** with active integration against `FirstKissNovel` and `NovelTranslate`.
3. Wire the **`Kokoro-82M`** and **`Piper`** real-time streaming pipeline via `sherpa_onnx` to prove the zero-latency audiobook experience immediately.