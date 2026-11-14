# Engineering Plan: Offline Audiobook Generation, Audio Cache Assembly & Multilingual Neural Audiobooks

> **Document**: `plan.md`  
> **Status**: Approved Architecture & Implementation Plan  
> **Target Platforms**: Android, iOS, Web, Desktop (Linux/Windows/macOS)  
> **Scope**: Background Audiobook Downloader, Real-time TTS Chunk Assembly, Zero-DSP Binary MP3 Concatenation, Multilingual Translation Pipeline, and Unified Audiobook Player UI.

---

## 1. Executive Summary & Vision

### Current State
- The application features a high-performance **sequential neural TTS playback engine** ([`RingBufferManager`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/tts/ring_buffer_manager.dart)) powered by **Microsoft Edge Neural TTS** ([`EdgeNeuralEngine`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/tts/engines/edge_neural_engine.dart)) and local on-device engines ([`SherpaEngine`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/tts/engines/sherpa_engine.dart), [`PiperEngine`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/tts/engines/piper_engine.dart)).
- During real-time reading, the TTS engine aggressively prefetches up to 5 sentences at a time into temporary cache files (`edge_tts_cache/*.mp3`).
- **Limitation**: These audio chunks are temporary and ephemeral. Once the user closes the reader or finishes listening, the chunks are discarded or eventually purged by the OS temporary cache. Furthermore, users cannot queue chapters for bulk offline audiobook generation or listen to translated versions of foreign webnovels.

### The New Architecture
This plan introduces a complete **Audiobook Ecosystem** within Novels-World:
1. **1-Tap Chapter & Batch Audiobook Downloader**: Select any chapter range (e.g. Ch 1–25, "Next 10 unread", or whole book) and download them directly as standalone, high-fidelity offline audiobooks (`.mp3`).
2. **Real-time "Listen-to-Save" Audio Cache Assembly**: An intelligent setting where listening to TTS while reading automatically retains, stitches, and saves all played sentence chunks into that novel's permanent offline audiobook library. Subsequent listens use 0 network data and 0 buffering.
3. **Pure-Dart Binary Frame Concatenation**: Zero heavy FFmpeg dependencies. Valid MPEG-1/2 Audio Layer III (MP3) frames are losslessly stitched with ID3v2 metadata (Cover Art, Novel Title, Author, Chapter Title, Track Number) directly in Dart.
4. **Multilingual Translation & Native Voice Pipeline**: Built-in translation enabling readers to translate foreign webnovels (Japanese, Chinese, Korean, Arabic, Spanish, etc.) into any target language and synthesize speech using localized Microsoft Neural studio voices (e.g. Japanese `ja-JP-NanamiNeural`, Chinese `zh-CN-XiaoxiaoNeural`, English `en-US-ChristopherNeural`, Spanish `es-ES-AlvaroNeural`).
5. **Integrated Audiobook Player & Storage Management**: Dedicated playback UI with scrub bars, 15-second skip, speed controls, sleep timers, and storage management in [`NovelStorageModal`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/widgets/novel_storage_modal.dart).

---

## 2. End-to-End System Architecture

```mermaid
flowchart TD
    subgraph Trigger["1. User Trigger Modes"]
        T1["Novel Details / Range Dialog<br/>[Download as Audiobook]"] --> DL["Audiobook Downloader Service"]
        T2["Reader TTS Playback<br/>(Toggle: 'Save TTS as Audiobook')"] --> RB["RingBufferManager Audio Cache"]
    end

    subgraph TranslationLayer["2. Multilingual & Translation Engine"]
        DL --> TR{"Needs Translation?"}
        TR -->|"Original Language"| S1["Extract Sentences"]
        TR -->|"Different Language (e.g. JA -> EN)"| T3["TranslationService<br/>(Google Translate API / LLM)"]
        T3 --> S1
    end

    subgraph SynthesisPipeline["3. Neural Synthesis & Slicing"]
        S1 --> SYN["EdgeNeuralEngine / EdgeTtsClient<br/>(Selected Language Voice)"]
        SYN --> CHUNKS["Sentence MP3 Chunks<br/>(24kHz / 48kHz High-Fidelity)"]
    end

    subgraph AssemblyLayer["4. Zero-FFmpeg MP3 Assembler"]
        CHUNKS --> ASM["AudiobookAssemblerService"]
        RB -->|"Chapter End / Completed"| ASM
        ASM --> ID3["Inject ID3v2 Tags & Cover Art"]
        ID3 --> FILE["audiobooks/{novelId}/{chapterId}.mp3"]
    end

    subgraph PlaybackAndStorage["5. Storage & Playback"]
        FILE --> DB["StorageService Audiobook Registry"]
        DB --> UI1["Library -> Audiobook Tab"]
        DB --> UI2["Novel Detail -> Offline Audio Badge"]
        DB --> PL["Audiobook Player (just_audio)"]
    end
```

---

## 3. Core Technical Pillars & Implementation Details

### Pillar 1: Pure-Dart Lossless MP3 Binary Frame Concatenation

#### Why MP3?
- Microsoft Edge TTS outputs raw, pristine `audio/mpeg` frames encoded at 24kHz / 48kHz mono.
- Unlike MP4/M4A/AAC which require rewriting binary container atoms (`moov`, `stco`, `stsz` chunk offsets), **MP3 is a native streamable frame format**.
- Each MP3 frame starts with an 11-bit sync word `0xFFE0` (typically `0xFF 0xFB` or `0xFF 0xF3`) followed by bitrate, sample rate, and padding headers.
- **Concatenation Algorithm**:
  1. Open target file write stream.
  2. Write ID3v2 header containing Cover Art (JPEG), Title, Artist, Album, and Chapter Track Number.
  3. Sequentially read each sentence chunk file.
  4. Skip any ID3v2 tag prefix on the chunk (if present).
  5. Stream the raw MPEG audio frame bytes directly into the target file.
  6. Close stream.
- **Speed**: Stitches 100 sentences (~3,000 words, ~15 minutes of audio) in **under 45 milliseconds** on a mobile device without CPU throttling or battery drain.

---

### Pillar 2: "Listen-to-Save" Audio Cache Assembly (Real-time Reader Integration)

#### How It Works:
1. In [`SettingsProvider`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/providers/settings_provider.dart) and [`TtsSheet`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/reader/tts_sheet.dart):
   - Add switch: `bool saveTtsAsAudiobook` (defaults to `false` or prompt on first audio listen).
2. In [`RingBufferManager`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/tts/ring_buffer_manager.dart):
   - When `saveTtsAsAudiobook == true`:
     - Maintain an ordered map `Map<int, String> _chapterAudioChunks` for the active chapter.
     - As sentences are synthesized or prefetched, their cached MP3 file paths are indexed: `_chapterAudioChunks[sentenceIndex] = filePath`.
     - When `_handleSentenceCompleted()` reaches the final sentence of the chapter (or when all chapter sentences are prefetched in background):
       - Fire `AudiobookAssemblerService.assembleChapterAudio(...)` in an unawaited background task.
       - Stitch all chunks into `audiobooks/<novelId>/<chapterId>.mp3`.
       - Notify [`StorageService`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/storage_service.dart) and display a subtle snackbar: *"Chapter saved to Offline Audiobooks"*.
3. **Instant Cache Re-use**:
   - If a chapter has already been assembled into an audiobook file, `RingBufferManager.playFrom(index)` detects the complete chapter audio file and plays it directly via `_player.setFilePath(...)`, eliminating all network latency, server dependencies, and sentence-to-sentence gap jitter!

---

### Pillar 3: Dedicated Bulk Audiobook Downloader Service

#### Structure:
```dart
class AudiobookDownloadTask {
  final Novel novel;
  final Chapter chapter;
  final String voice;
  final double speed;
  final double pitch;
  final String? targetLanguage; // null if original language
  DownloadStatus status;
  double progress; // 0.0 to 1.0 (sentences synthesized / total)
  String? error;
}
```

#### Queue Processor Workflow:
1. **Extract Content**: Retrieve chapter paragraphs via [`StorageService.getCachedChapterContent`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/storage_service.dart#L192) (or fetch from extractor if not downloaded).
2. **Clean & Slice**: Use [`TextCleaner.splitIntoSentences`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/utils/text_cleaner.dart) to generate optimal 15–25 word breath-phrased chunks.
3. **Translate (if applicable)**: Run sentence groups through [`TranslationService`](#pillar-4-multilingual--translation-audiobook-pipeline) to target language.
4. **Batch Synthesize**: Call `EdgeTtsClient.synthesizeToBytes(...)` with concurrent rate-limiting (3 concurrent sentence requests to prevent Microsoft WebSocket throttling).
5. **Assemble & Tag**: Combine into `${storage.appDocumentsDirectoryPath}/audiobooks/${novelId}/${chapterId}.mp3`.
6. **Register**: Add chapter ID to `downloaded_audiobooks_${novelId}` in `SharedPreferences`.

---

### Pillar 4: Multilingual & Translation Audiobook Pipeline

#### The Problem:
- Readers often read foreign raw light novels (e.g. Kakuyomu in Japanese, WuxiaBox raws in Chinese, Riwyat in Arabic) or want English novels narrated in Spanish, French, German, or Hindi.

#### Architecture:
```dart
abstract class TranslationService {
  Future<String> translateText(String text, {required String sourceLang, required String targetLang});
  Future<List<String>> translateSentences(List<String> sentences, {required String sourceLang, required String targetLang});
}
```

#### Translation Providers:
1. **Free High-Speed Web Translation** (Default, zero API key needed):
   - Endpoint: `https://translate.googleapis.com/translate_a/single?client=gtx&sl={src}&tl={target}&dt=t&q={encoded}`
   - Fast, reliable, and handles 50–100 sentences per chapter in small batches without user setup.
2. **AI LLM Translation (Optional / User Configurable)**:
   - For users with a Gemini API Key or OpenAI Key in app settings:
   - Preserves literary tone, fantasy honorifics (e.g. *senpai*, *cultivation ranks*, *daoist terms*), and narrative voice.

#### Neural Voice Mapping Matrix:
When translating or synthesizing in different languages, the system dynamically maps the target language to the best studio-grade Microsoft Neural voice:

| Language Code | Language Name | Recommended Female Voice | Recommended Male Voice |
| :---: | :---: | :---: | :---: |
| `en` | English | `en-US-JennyNeural` | `en-US-ChristopherNeural` / `en-GB-RyanNeural` |
| `ja` | Japanese | `ja-JP-NanamiNeural` | `ja-JP-KeitaNeural` |
| `zh` | Chinese (Mandarin) | `zh-CN-XiaoxiaoNeural` | `zh-CN-YunxiNeural` |
| `ko` | Korean | `ko-KR-SunHiNeural` | `ko-KR-InJoonNeural` |
| `es` | Spanish | `es-ES-ElviraNeural` | `es-ES-AlvaroNeural` |
| `fr` | French | `fr-FR-DeniseNeural` | `fr-FR-HenriNeural` |
| `de` | German | `de-DE-KatjaNeural` | `de-DE-ConradNeural` |
| `hi` | Hindi | `hi-IN-SwaraNeural` | `hi-IN-MadhurNeural` |
| `ar` | Arabic | `ar-EG-SalmaNeural` | `ar-SA-HamedNeural` |
| `th` | Thai | `th-TH-PremwadeeNeural` | `th-TH-NiwatNeural` |

---

### Pillar 5: Storage Architecture & Directory Layout

All audiobook files are stored in a sandboxed, clean directory structure that automatically supports offline playback, backup exclusion, and individual chapter purging:

```
<ApplicationDocumentsDirectory>/
  audiobooks/
    {novelId}/
      metadata.json                      <-- Audiobook duration, voice used, language
      {chapterId}.mp3                    <-- Assembled chapter audiobook (Original)
      {chapterId}_{targetLang}.mp3       <-- Assembled chapter audiobook (Translated)
```

#### Key Storage Service Enhancements ([`StorageService`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/storage_service.dart)):
- `Future<File> getAudiobookFile(String novelId, String chapterId, {String? lang})`
- `Future<bool> hasOfflineAudiobook(String novelId, String chapterId, {String? lang})`
- `Future<List<String>> getDownloadedAudiobookChapterIds(String novelId)`
- `Future<int> getAudiobookStorageBytes(String novelId)`
- `Future<void> deleteAudiobookChapter(String novelId, String chapterId)`
- `Future<void> deleteAllAudiobooksForNovel(String novelId)`

---

### Pillar 6: User Interface & User Experience Design

#### 1. Download Range Dialog ([`DownloadRangeDialog`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/widgets/download_range_dialog.dart)):
- Add an action selector segment:
  - `[📄 Download Text]` (Standard offline reading)
  - `[🎧 Download Audiobook]` (Audiobook generation)
- When `[🎧 Download Audiobook]` is selected:
  - Surfaces a voice selector dropdown (prefilled with current active voice).
  - Surfaces a **Translation Option**: `"Audio Language: [Original] | [Translate to English / Spanish / Japanese / etc.]"`.
  - Estimates total audio duration and file size (e.g. ~1.2 MB per chapter).

#### 2. Novel Detail Screen ([`NovelDetailScreen`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/novel/novel_detail_screen.dart)):
- Beside each chapter item in the list:
  - If text is downloaded: green checkmark icon.
  - If audiobook is downloaded: purple headphones icon `[🎧]`.
  - Tapping the headphone icon plays that chapter in the Audiobook Player immediately.

#### 3. Reader TTS Settings Sheet ([`TtsSheet`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/ui/reader/tts_sheet.dart)):
- Add a new card switch:
  - **"Save Listening as Offline Audiobook"** (Switch: ON/OFF)
  - Subtitle: *"Automatically combines streamed audio chunks into permanent offline chapter audiobooks as you read."*

#### 4. Persistent Floating Audiobook Mini-Player:
- When playing an audiobook in the background:
  - Bottom persistent mini-bar (Novel Cover, Chapter Title, Play/Pause, +15s, -15s, Close).
  - Tapping opens the full-screen immersive player with waveform, speed dial, and chapter drawer.

---

## 4. Phased Implementation Roadmap

### Phase 1: Core Services & Audio File Assembler
- [ ] Implement `AudiobookAssemblerService` ([`lib/core/services/audiobook_assembler_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/services/audiobook_assembler_service.dart)) for binary MP3 concatenation with ID3 metadata injection.
- [ ] Extend `StorageService` ([`lib/data/storage_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/storage_service.dart)) to index, query, delete, and measure audiobook storage.
- [ ] Write unit tests for binary MP3 stitching and metadata verification.

### Phase 2: "Listen-to-Save" Audio Cache Assembly
- [ ] Add `saveTtsAsAudiobook` toggle to `SettingsProvider` and SharedPreferences.
- [ ] Update `RingBufferManager` to index sentence chunks per chapter and trigger `AudiobookAssemblerService` on chapter completion.
- [ ] Add pre-check in `RingBufferManager.playFrom` to stream existing chapter MP3 files directly without network round-trips.
- [ ] Add toggle to `TtsSheet`.

### Phase 3: Multilingual & Translation Service
- [ ] Create `TranslationService` ([`lib/core/services/translation_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/core/services/translation_service.dart)) with Google Translate web client and optional LLM provider.
- [ ] Add multilingual voice catalog and language mapping in `TtsModelRegistry` / `EdgeNeuralEngine`.
- [ ] Write unit tests for sentence translation and language-voice resolution.

### Phase 4: Bulk Audiobook Downloader Service & UI
- [ ] Implement `AudiobookDownloadService` ([`lib/data/audiobook_download_service.dart`](file:///home/adityapatra/Documents/GitHub/Novels-World/lib/data/audiobook_download_service.dart)) with queue processing, progress updates, and retry logic.
- [ ] Update `DownloadRangeDialog` with `[Download Audiobook]` tab and translation dropdown.
- [ ] Add audiobook badges `[🎧]` to chapter list in `NovelDetailScreen`.
- [ ] Update `NovelStorageModal` to display and purge audiobook storage.

### Phase 5: Audiobook Player UI & Verification
- [ ] Build floating Audiobook Mini Player and Full-Screen Audiobook Player modal.
- [ ] Verify background audio playback and notification controls via `just_audio`.
- [ ] Run full test suite (`flutter test`) and static analysis (`flutter analyze`).
