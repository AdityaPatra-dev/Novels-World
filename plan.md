# Engineering Plan: Offline Audiobook Ecosystem, In-Reader Translation, Audio Cache Assembly & Portable .ZIP Migration

> **Document**: `plan.md`  
> **Status**: Approved Production Architecture & UI/UX Design  
> **Target Platforms**: Android, iOS, Web, Desktop (Linux/Windows/macOS)  
> **Scope**: Advanced Dual-Track Downloader, In-Reader Live Translation (`Icons.translate`), Zero-FFmpeg MP3 Frame Concatenation, "Listen-to-Save" Audio Cache Assembly, Downloads Tab Multi-Tag Badging (`offline`, `audio_hi`), Dedicated Audiobook Player, and 1-Click Portable `.zip` Backup & Migration (Export/Import).

---

## 1. Executive Summary & User Story

### The Problem
Previously, reading and downloading in novel apps was rigidly one-dimensional:
1. **Language Barrier**: If an English reader wanted to read a raw Japanese light novel, or a reader fluent only in **Hindi** wanted to read an English novel like *Shadow Slave*, they had no way to translate the chapter text or listen to it in their native tongue.
2. **Ephemeral Audio**: When using Text-to-Speech (TTS), audio chunks were streamed and discarded after listening. Users could not retain the audio or download complete offline audiobooks for their commute or flights.
3. **App Deletion / Device Migration Fear**: If a user reinstalled the app, cleaned phone storage, or bought a new phone, all downloaded chapters and reading progress were permanently lost.

### The Solution: A Complete, User-Friendly Audio & Reading Ecosystem
This plan introduces a cohesive, intuitive feature set designed specifically for everyday, non-technical readers:
- **1-Tap Dual-Track Downloader**: When downloading chapters (e.g. *Shadow Slave* Ch 1–10), the user can effortlessly choose their preferred text language (e.g. Hindi), check `[🎧 Download Audio too]`, choose the voice, and download both text and studio-grade audio in one go.
- **In-Reader Translation Symbol (`Icons.translate`)**: A translation button right in the top app bar transforms the novel text into Hindi (or any of 70+ languages) with one tap, with synchronized Hindi speech highlighting.
- **"Listen-to-Save" Audio Assembly**: Listening to TTS while reading automatically retains and stitches the audio into permanent chapter `.mp3` audiobooks.
- **Downloads Tab Badging**: In the Downloads tab, chapters clearly display colorful badges: **`[offline]`** for text and **`[audio_hi]`** for Hindi audio (or `audio_en`, `audio_es`, etc.).
- **1-Click Portable `.zip` Backup & Migration**: An Export/Import window packages all novels, chapters, audiobooks, and progress into a single `.zip` file on phone storage. Reinstalling the app and picking the `.zip` file instantly restores everything.

---

## 2. End-to-End System Workflow

```mermaid
flowchart TD
    subgraph S1["1. User Selection & Dual-Track Download"]
        UI_A["Novel Detail / Source Page<br/>(e.g. 'Shadow Slave')"] --> BTN["Tap [Download Chapters]"]
        BTN --> MODAL["DownloadRangeDialog<br/>Mode: [Text + Audiobook]<br/>Text: Hindi | Audio: Hindi (Swara)"]
        MODAL --> QUEUE["AudiobookDownloadService<br/>(Background Parallel Queue)"]
    end

    subgraph S2["2. Processing & Synthesis Pipeline"]
        QUEUE --> TRANS{"Translation Required?"}
        TRANS -->|"Yes (EN -> HI)"| TR_SVC["TranslationService<br/>(Batched Web API / LLM)"]
        TRANS -->|"No (Original)"| SLICE["Sentence Slicer"]
        TR_SVC --> SLICE
        SLICE --> TTS["EdgeNeuralEngine (hi-IN-SwaraNeural)<br/>Stream MP3 Audio Frames"]
        TTS --> STITCH["AudiobookAssemblerService<br/>(Pure-Dart MP3 Frame Concatenation)"]
    end

    subgraph S3["3. Local Storage & Indexing"]
        STITCH --> FILE_AUDIO["audiobooks/{novelId}/{chapterId}_hi.mp3"]
        TR_SVC --> FILE_TXT["translations/{novelId}/{chapterId}_hi.json"]
        FILE_AUDIO --> REG["StorageService Registry<br/>(Registers 'offline' & 'audio_hi' Tags)"]
        FILE_TXT --> REG
    end

    subgraph S4["4. User Presentation & Playback"]
        REG --> TAB["Downloads Tab -> Novel Card"]
        TAB --> LIST["Chapter List -> Badges: [offline] [audio_hi]"]
        LIST --> READ["ReaderScreen (Offline Hindi Reading)"]
        LIST --> PLAY["AudiobookPlayer (0ms Offline Audio Playback)"]
    end

    subgraph S5["5. Portable Backup & Device Migration"]
        REG --> EXP["BackupService.exportToZip()<br/>Bundles Manifest, Text & Audio into .zip"]
        EXP --> ZIP_FILE["novels_world_backup_20261114.zip<br/>(Saved to Phone / Google Drive)"]
        ZIP_FILE --> IMP["BackupService.importFromZip()<br/>(Reinstalled App / New Device)"]
        IMP --> REG
    end
```

---

## 3. Detailed UI/UX Design & Core Pillars

### Pillar 1: Modern & Dead-Simple Download Modal (`DownloadRangeDialog`)

#### Visual Layout & Wireframe:
When the user taps the `[Download]` button on any novel, a clean bottom sheet opens:

```
┌─────────────────────────────────────────────────────────────┐
│ 📥 Download Chapters                                        │
│ Shadow Slave • NovelFire                                    │
├─────────────────────────────────────────────────────────────┤
│ Select Download Mode:                                       │
│ ┌───────────────┐ ┌───────────────────┐ ┌─────────────────┐ │
│ │ 📖 Text Only  │ │ 🎧 Audiobook Only │ │ 🌟 Both (T+A)   │ │
│ └───────────────┘ └───────────────────┘ └─────────────────┘ │
│                                                             │
│ Chapter Range:                                              │
│ [ Next 10 Unread ]  [ Next 25 ]  [ Next 50 ]  [ All ]       │
│ Custom: [ 1-10                                        ]     │
│                                                             │
│ 🌐 Text Language:                                           │
│ [ 🇮🇳 हिन्दी (Hindi)                               ▼ ]     │
│                                                             │
│ 🎧 Audio Settings:                                          │
│ Voice: [ Swara (Expressive Female - Hindi)        ▼ ]       │
│        [ ▶ Preview Voice (3s sample) ]                      │
│                                                             │
│ ℹ️ Summary:                                                  │
│ 10 Chapters • ~120 KB Text • ~12.4 MB Audio                 │
│ Estimated Time: ~45 seconds on Wi-Fi                        │
│                                                             │
│ [           ⬇️ Start Download (10 Chapters)          ]      │
└─────────────────────────────────────────────────────────────┘
```

#### Key UX Features:
1. **Three Visual Mode Cards**:
   - `📖 Text Only`: Fast offline text reading (~10 KB/chapter).
   - `🎧 Audiobook Only`: Studio audio without translating text (~1.2 MB/chapter).
   - `🌟 Both (Text + Audio)`: Full visual reading + offline voice narration.
2. **Friendly Language Selector with Native Scripts**:
   - Displays flags and native spellings so anyone can recognize their language: `🇮🇳 हिन्दी (Hindi)`, `🇪🇸 Español (Spanish)`, `🇯🇵 日本語 (Japanese)`, `🇫🇷 Français (French)`, `🇩🇪 Deutsch (German)`, `🇸🇦 العربية (Arabic)`, `🇨🇳 中文 (Chinese)`.
3. **Voice Sample Preview Button (`[▶ Preview Voice]`)**:
   - Tapping plays a 3-second friendly greeting in the chosen voice (e.g., *"नमस्ते! यह उपन्यासों की दुनिया है"*) so the user knows exactly how the narrator sounds before downloading.
4. **Clear Space & Time Estimate**:
   - Prevents surprises by showing exact download size and time before starting.

---

### Pillar 2: In-Reader Live Translation & Bilingual Helper (`ReaderScreen`)

#### Top App Bar Integration:
In [`ReaderScreen`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/reader/reader_screen.dart), an international translation symbol (`Icons.translate`) sits beside the TTS button:

```
[ ← Back ]  Chapter 1: The First Nightmare      [ 文A ]  [ 🎧 TTS ]  [ Aa ]
```

#### Interactive Behavior:
1. **1-Tap Toggle**:
   - Tapping `[文A]` opens a smooth modal:
     - Switch: **"Translate Chapter"** (ON / OFF).
     - Target Language: Quick chips for recent languages (`Hindi`, `Spanish`, `Japanese`, etc.).
2. **Active State Banner**:
   - When active, an elegant dismissible banner appears below the AppBar:
     `"Translated to Hindi • Tap [文A] to switch back to English"`.
   - The chapter text dynamically re-renders in Hindi (Devanagari script).
3. **Bilingual Long-Press Helper**:
   - If a translated fantasy term, character name, or ability looks unfamiliar:
   - Long-pressing any translated paragraph surfaces a lightweight floating tooltip showing the **original English text**!
4. **Synchronized Multilingual TTS Playback**:
   - When the user taps the **TTS Audio Button** while Hindi is active:
     - The reader automatically speaks the chapter in Hindi using `hi-IN-SwaraNeural`.
     - Spoken Hindi sentences highlight in real time as the audio flows.
     - In [`TtsSheet`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/reader/tts_sheet.dart), the reader can freely switch voices or pitch.

---

### Pillar 3: "Listen-to-Save" Audio Cache Assembly (Zero Network Re-use)

#### The Mechanism:
- While reading with TTS enabled, the user can toggle **"Save Listening as Offline Audiobook"** in the TTS Sheet or App Settings.
- As the user reads and listens to sentences:
  1. [`RingBufferManager`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/tts/ring_buffer_manager.dart) retains the synthesized MP3 chunks in order for the current chapter: `_chapterAudioChunks[sentenceIdx] = tempPath`.
  2. When the chapter ends (or when background pre-fetching completes all chapter sentences):
     - `AudiobookAssemblerService` stitches all sentence chunks into the final chapter audio file:
       `${storage.appDocumentsDirectoryPath}/audiobooks/${novelId}/${chapterId}_${lang}.mp3`.
     - Injects ID3 metadata (Novel Cover, Novel Title, Chapter Title, Track Number).
     - Registers the chapter in [`StorageService`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/storage_service.dart).
     - Shows a toast: *"✅ Chapter 1 saved to Offline Audiobooks"*.
3. **Instant 0-Lag Future Playback**:
   - If the user re-opens this chapter or plays it in the Audiobook Player:
   - The app detects the existing `.mp3` file on disk and streams it directly via `just_audio`.
   - **Zero network requests, zero server dependencies, and zero sentence-gap stutter!**

---

### Pillar 4: Pure-Dart Zero-FFmpeg Binary MP3 Frame Concatenation

#### Technical Implementation:
- **No Heavy Native Binaries**: Avoids cumbersome 80MB FFmpeg C-libraries that cause Android APK bloat and iOS compilation failures.
- **MPEG Stream Architecture**:
  - Microsoft Edge Neural TTS outputs pristine `audio/mpeg` frames (MPEG-1/2 Audio Layer III).
  - An MP3 audio stream consists of discrete frames, each starting with the 11-bit sync word `0xFFE0` (`0xFF 0xFB`).
  - Concatenation Algorithm in `AudiobookAssemblerService`:
    ```dart
    final outputFile = File('$audiobookDir/${chapterId}_$lang.mp3');
    final sink = outputFile.openWrite();
    
    // 1. Write ID3v2.3 Tag Header (Title, Artist, Album, Attached Cover Art)
    sink.add(id3TagBytes);
    
    // 2. Sequentially stream sentence audio chunks, stripping any chunk-level ID3 headers
    for (final chunkPath in sentenceChunkPaths) {
      final chunkBytes = await File(chunkPath).readAsBytes();
      final audioData = _stripId3Header(chunkBytes);
      sink.add(audioData);
    }
    
    await sink.flush();
    await sink.close();
    ```
- **Performance**: A typical 3,000-word chapter (~15 minutes of speech) stitches in **under 45 milliseconds**.

---

### Pillar 5: Downloads Tab Presentation & Multi-Tag Badging (`offline`, `audio_hi`)

#### 1. Novel Card in Downloads Tab ([`DownloadsScreen`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/downloads/downloads_screen.dart)):
In the **Downloads Tab**, *Shadow Slave* displays its rich status:

```
┌─────────────────────────────────────────────────────────────┐
│ [Cover]  Shadow Slave                                       │
│          Guiltythree • NovelFire                            │
│          [ 📄 10 Chapters ]  [ 🎧 10 Audiobooks (HI) ]      │
│          Storage: 12.5 MB                                   │
└─────────────────────────────────────────────────────────────┘
```

#### 2. Chapter List Presentation & Color-Coded Badges:
Tapping the novel card opens its offline chapter list:

```
┌─────────────────────────────────────────────────────────────┐
│ ← Shadow Slave (Downloaded Chapters)           [ 🔍 ] [ ⋮ ] │
├─────────────────────────────────────────────────────────────┤
│ Chapter 1: The First Nightmare                              │
│ [ offline ]  [ 🎧 audio_hi ]         [ 📖 Read ] [ 🎧 Play ]│
├─────────────────────────────────────────────────────────────┤
│ Chapter 2: The Choice                                       │
│ [ offline ]  [ 🎧 audio_hi ]         [ 📖 Read ] [ 🎧 Play ]│
├─────────────────────────────────────────────────────────────┤
│ Chapter 3: Into the Mountain                                │
│ [ offline ]  [ 🎧 audio_hi ]         [ 📖 Read ] [ 🎧 Play ]│
└─────────────────────────────────────────────────────────────┘
```

#### Badge Definitions:
- **`[ offline ]`** (Emerald Green border/fill): The full text has been downloaded and translated into Hindi; readable anywhere with zero internet.
- **`[ 🎧 audio_hi ]`** (Violet/Purple border/fill with headphone icon): The complete Hindi neural audiobook has been generated and saved locally.
- **`[ 🎧 audio_en ]` / `[ 🎧 audio_es ]`**: Clearly indicates the audio language if downloaded in English or Spanish.
- **Direct 1-Tap Actions**:
  - Tapping **`[ 📖 Read ]`** opens [`ReaderScreen`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/reader/reader_screen.dart) in offline mode with translated text.
  - Tapping **`[ 🎧 Play ]`** launches the **Audiobook Player** immediately with 0 second delay.

---

### Pillar 6: Dedicated Built-in Audiobook Player (`AudiobookPlayerScreen` & Mini-Player)

#### 1. Floating Persistent Mini-Player:
When an audiobook is playing, a sleek floating mini-player docks at the bottom of the screen (visible on Library, Browse, and Novel Detail screens):
- Left: Novel thumbnail cover + Chapter Title.
- Right: Quick Play/Pause button + Skip 15s button + Close.
- Tapping anywhere on the bar smoothly expands into the **Full-Screen Immersive Player**.

#### 2. Full-Screen Immersive Player:
Designed for relaxed, hands-free listening:
- **Large Artwork**: High-resolution novel cover with soft ambient drop-shadow.
- **Novel & Chapter Title**: Clear typography with author byline.
- **Scrubbing Time Bar**: Real-time position (e.g. `04:15 / 14:30`) with smooth draggable seeker.
- **Big Media Controls**:
  - `[⏮ Prev Chapter]` `[⏪ -15s]` `[ ▶ Play / ⏸ Pause ]` `[⏩ +15s]` `[⏭ Next Chapter]`
- **Speed Dial**: Preset buttons: `0.75x`, `1.0x`, `1.25x`, `1.5x`, `2.0x`.
- **Sleep Timer**: "15 min", "30 min", "End of Chapter" (with gradual 60-second audio fade-out so readers aren't jolted awake).
- **Background & Lock Screen Notifications**: Supports Android MediaSession & iOS Remote Command Center (lock-screen play/pause/skip and headphone buttons).
- **Autoplay Next Chapter**: When Chapter 1 finishes, it automatically rolls into Chapter 2 without requiring manual input.

---

### Pillar 7: Portable Backup & Migration (.ZIP Export & Import)

#### The User Scenario:
> *"Suppose the user wants to delete or reinstall the application, or move to a new phone, but wants to keep all downloaded novels and audiobooks. We add an export window that bundles all downloaded novels, text chapters, and audiobooks into a structured `.zip` archive saved to their phone. When re-installing the app, they select Import, choose the `.zip`, and all novels, chapters, `offline` and `audio_hi` tags, and audiobooks are instantly restored."*

#### 1. Backup Directory & Internal Zip Specification:
Using pure-Dart `package:archive/archive.dart` (`ZipEncoder` / `ZipDecoder`):

```
novels_world_backup_YYYYMMDD_HHMM.zip
├── manifest.json                                  <-- App version, backup date, novel registry index
├── settings.json                                  <-- Reader preferences, active voices, translation prefs
└── novels/
    └── shadow_slave/
        ├── metadata.json                          <-- Novel model (title, author, genres, cover URL, source)
        ├── cover.jpg                              <-- Cached cover image binary
        ├── chapters/
        │   ├── chapter_1.json                     <-- Original text content
        │   ├── chapter_1_hi.json                  <-- Translated Hindi text content
        │   └── ...
        └── audio/
            ├── chapter_1_hi.mp3                   <-- Complete assembled Hindi audiobook MP3
            ├── chapter_2_hi.mp3
            └── ...
```

#### 2. Export Window Workflow (`BackupService.exportToZip`):
1. In [`DownloadsScreen`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/downloads/downloads_screen.dart), tap the **[Backup & Migration]** icon in the AppBar (`Icons.archive_outlined`).
2. Opens the **Backup & Migration Dialog**:
   - Summary Card: Shows total items to be backed up:
     `"3 Novels • 45 Text Chapters • 20 Audiobooks • Total Size: ~24.5 MB"`.
   - Options checkboxes:
     - `[x] Include Offline Text & Library History`
     - `[x] Include Offline Audiobooks (.mp3)`
3. User taps **[📦 Export Backup (.zip)]**:
   - Generates `manifest.json`.
   - Packages novels, chapters, translated files, audiobooks, and covers.
   - Shows live progress bar (`0% -> 100%`).
   - Uses `FilePicker.platform.saveFile(...)` to let the user save `novels_world_backup_<date>.zip` into their Phone Downloads, SD Card, or Google Drive.
   - Shows success toast: *"✅ Backup successfully saved to your device!"*.

#### 3. Import Window Workflow (`BackupService.importFromZip`):
1. On a fresh app installation or new phone, user goes to Downloads tab $\rightarrow$ taps **[Backup & Migration]** $\rightarrow$ taps **[📥 Import Backup (.zip)]**.
2. Opens file picker via `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'])`.
3. User selects their saved backup `.zip` file.
4. **Pre-Import Verification Summary**:
   - App inspects `manifest.json` and presents a confirmation dialog:
     `"Found Backup from Nov 14, 2026: 3 Novels (Shadow Slave, Lord of the Mysteries...), 45 Chapters, 20 Audiobooks. Restore now?"`
5. Tapping **[Confirm Restore]**:
   - Safely extracts text chapters into `${storage.appDocumentsDirectoryPath}/chapters/`.
   - Extracts translated chapters into `${storage.appDocumentsDirectoryPath}/translations/`.
   - Extracts `.mp3` audio files into `${storage.appDocumentsDirectoryPath}/audiobooks/{novelId}/`.
   - Restores novel metadata and reading progress in [`StorageService`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/storage_service.dart).
6. **Immediate UI Refresh**:
   - Both **Library** and **Downloads** tabs refresh instantly.
   - *Shadow Slave* appears with its 10 chapters, the **`[offline]`** and **`[audio_hi]`** badges are active, and tapping **`[🎧 Play]`** plays the Hindi audio immediately without needing an internet connection!

---

### Pillar 8: High-Performance Translation & Error Resilience

#### 1. Batched Sentence Translation (`TranslationService`):
- To prevent network latency and avoid rate-limiting, chapter sentences are batched into groups of 15–20 sentences per translation request.
- A 100-sentence chapter requires only **5 network roundtrips** instead of 100 individual requests, completing in ~3 seconds.

#### 2. Offline Translation Cache:
- All translated chapters are permanently cached on disk at `translations/{novelId}/{chapterId}_{lang}.json`.
- A chapter translated once never needs to be translated again.

#### 3. Network Dropout Resilience:
- If a user loses internet while downloading Chapter 7 of a 10-chapter audiobook batch:
  - Chapters 1–6 remain **100% intact and playable offline**.
  - The download queue marks Chapter 7 as `paused / failed` with a 1-tap `[Retry]` button.
  - No duplicated data is ever re-downloaded.

---

### Pillar 9: Storage Manager Integration (`NovelStorageModal`)

In [`NovelStorageModal`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/widgets/novel_storage_modal.dart), users can view a clear storage breakdown:
- **Text Chapters**: `10 chapters • 120 KB`
- **Hindi Audiobooks**: `10 chapters • 12.4 MB`
- **Granular Cleanup Actions**:
  - `[🗑️ Delete Audio Only]` (Frees 12.4 MB while preserving offline text for reading).
  - `[🗑️ Delete Text Only]`
  - `[🗑️ Clear All Storage]`

---

## 4. Phased Implementation Roadmap

### Phase 1: Core Services & Audio File Assembler
- [ ] Implement `AudiobookAssemblerService` ([`lib/core/services/audiobook_assembler_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/services/audiobook_assembler_service.dart)) for pure-Dart binary MP3 concatenation with ID3 metadata injection.
- [ ] Extend `StorageService` ([`lib/data/storage_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/storage_service.dart)) to index, query, delete, and measure audiobook storage.
- [ ] Write unit tests for binary MP3 stitching and metadata verification.

### Phase 2: "Listen-to-Save" Audio Cache Assembly
- [ ] Add `saveTtsAsAudiobook` toggle to `SettingsProvider` and SharedPreferences.
- [ ] Update `RingBufferManager` to index sentence chunks per chapter and trigger `AudiobookAssemblerService` on chapter completion.
- [ ] Add pre-check in `RingBufferManager.playFrom` to stream existing chapter MP3 files directly without network round-trips.
- [ ] Add toggle to `TtsSheet`.

### Phase 3: Multilingual Translation Service & In-Reader Translation
- [ ] Create `TranslationService` ([`lib/core/services/translation_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/services/translation_service.dart)) with batched Google Translate web client and optional LLM provider.
- [ ] Add in-reader Translation symbol (`Icons.translate`) in `ReaderScreen` AppBar with language picker modal and bilingual tooltip helper.
- [ ] Add multilingual voice catalog and language mapping in `TtsModelRegistry` / `EdgeNeuralEngine`.
- [ ] Write unit tests for sentence translation and language-voice resolution.

### Phase 4: Bulk Audiobook Downloader Service & UI
- [ ] Implement `AudiobookDownloadService` ([`lib/data/audiobook_download_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/audiobook_download_service.dart)) with queue processing, progress updates, and retry logic.
- [ ] Update `DownloadRangeDialog` with 3 mode cards (`Text`, `Audio`, `Both`), language selector, voice sample preview (`[▶ Preview Voice]`), and resource estimator.
- [ ] Add `offline` and `audio_{lang}` badge pills to chapter list in `NovelDetailScreen` and `DownloadsScreen`.
- [ ] Update `NovelStorageModal` to display and purge audiobook storage.

### Phase 5: Portable Backup & Migration (.ZIP Export & Import)
- [ ] Implement `BackupService` ([`lib/core/services/backup_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/services/backup_service.dart)) using `package:archive` (`ZipEncoder` & `ZipDecoder`).
- [ ] Add Backup & Migration Modal in `DownloadsScreen` (`[Import / Export Backup]`).
- [ ] Verify export creates valid `.zip` with manifest, novels, text chapters, and audio files.
- [ ] Verify import seamlessly extracts, restores preferences, novel cards, badges, and offline playback.

### Phase 6: Audiobook Player UI & Verification
- [ ] Build floating Audiobook Mini Player and Full-Screen Audiobook Player modal with sleep timer, speed dial, and seek bar.
- [ ] Verify background audio playback and lock-screen notification controls via `just_audio`.
- [ ] Run full test suite (`flutter test`) and static analysis (`flutter analyze`).
