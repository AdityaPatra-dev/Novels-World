# 📚 Novels World — Technical Knowledge Archive & Master Index

Welcome to the comprehensive, publication-grade engineering archive for **Novels World**. This repository vault documents the complete architectural taxonomy, subsystem deep dives, algorithmic designs, and problem-solving chronology of the project.

---

## 🗂️ Documentation Vault Directory

The documentation within this directory is partitioned into modular, high-density files:

| Document | Purpose & Scope | Target Audience |
| :--- | :--- | :--- |
| **[`00_MASTER_INDEX.md`](00_MASTER_INDEX.md)** | Central navigation hub, system domain mapping, and index of technical files. | All Engineers & Reviewers |
| **[`NOVELS_WORLD_DEEP_DIVE.md`](NOVELS_WORLD_DEEP_DIVE.md)** | The comprehensive engineering masterfile: CS prerequisites, system architecture, subsystem mechanics, 10 deep real-world case studies, and senior interview Q&A. | Core Engineers, Architects, Interviewers |
| **[`COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md`](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md)** | Unvarnished chronological chronicle tracking the project from Day 1 to Production: user iteration triggers, debugging battles, logs, and algorithmic pivots. | Contributors, Maintainers, Historians |
| **[`TECHNICAL.md`](TECHNICAL.md)** | Core system diagrams, continuous neural audio pipeline, byte trimming formulas, and scraper specifications. | Systems & Media Engineers |
| **[`DOCKER.md`](DOCKER.md)** | Production Docker containerization, multi-stage compilation, NGINX Alpine server configuration, and Docker Hub deployment. | DevOps, SREs, Deployers |
| **[`README.md`](README.md)** | End-user presentation, platform support matrix, feature highlights, and native installation instructions (Android, Linux, Windows, macOS). | End Users & Developers |
| **[`README_SOURCES.md`](README_SOURCES.md)** | Directory of verified web novel sources, CMS engine templates, and anti-bot bypass strategies. | Web Scraping Engineers |
| **[`NOVEL_SOURCES_AND_TEMPLATES.md`](NOVEL_SOURCES_AND_TEMPLATES.md)** | Comprehensive catalog of 31+ novel providers, regex heuristics, and selector rules. | Scraper Maintainers |
| **[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)** | Initial execution roadmap, milestones, and architectural task checklists. | Project Planners |
| **[`DESIGN_SPEC_CHATGPT.md`](DESIGN_SPEC_CHATGPT.md)** | Foundational architectural brainstorm, domain entities, and data models. | System Designers |

---

## 🏛️ Architectural Domain Implementation Map

The table below maps every functional architectural domain to its exact implementation files, key classes, responsibilities, and concurrency patterns:

| Domain | Primary Implementation Files | Key Classes / Structs | Architectural Responsibility & Concurrency Pattern |
| :--- | :--- | :--- | :--- |
| **Acoustic Neural Synthesis (TTS)** | [`lib/tts/engines/edge_neural_engine.dart`](../lib/tts/engines/edge_neural_engine.dart)<br>[`lib/tts/engines/system_fallback_engine.dart`](../lib/tts/engines/system_fallback_engine.dart)<br>[`lib/tts/engines/kokoro_engine.dart`](../lib/tts/engines/kokoro_engine.dart)<br>[`lib/tts/engines/piper_engine.dart`](../lib/tts/engines/piper_engine.dart)<br>[`lib/tts/engines/sherpa_engine.dart`](../lib/tts/engines/sherpa_engine.dart) | `EdgeNeuralEngine`<br>`SystemFallbackEngine`<br>`KokoroEngine`<br>`PiperEngine`<br>`SherpaEngine` | Asynchronous WebSocket audio synthesis via Microsoft Edge Neural TTS API, fallback to native OS engines; in-flight deduplication, MP3 frame byte trimming, and audio file caching. |
| **Audio Playback & Sequence Queue** | [`lib/tts/ring_buffer_manager.dart`](../lib/tts/ring_buffer_manager.dart)<br>[`lib/tts/tts_model_registry.dart`](../lib/tts/tts_model_registry.dart)<br>[`lib/tts/voice_calibration.dart`](../lib/tts/voice_calibration.dart) | `RingBufferManager`<br>`TtsModelRegistry`<br>`VoiceCalibration`<br>`VoiceProfile` | Gapless playback management using `just_audio` native playlist queue (`setAudioSources`); **Monotonic Sequential FIFO Queue** resolving network race conditions between long paragraphs and short dialogues. |
| **Scraper & Content Extraction** | [`lib/extractors/madara_extractor.dart`](../lib/extractors/madara_extractor.dart)<br>[`lib/extractors/lightnovelwp_extractor.dart`](../lib/extractors/lightnovelwp_extractor.dart)<br>[`lib/extractors/novelfull_extractor.dart`](../lib/extractors/novelfull_extractor.dart)<br>[`lib/extractors/readwn_extractor.dart`](../lib/extractors/readwn_extractor.dart)<br>[`lib/extractors/royalroad_extractor.dart`](../lib/extractors/royalroad_extractor.dart)<br>[`lib/extractors/base_extractor.dart`](../lib/extractors/base_extractor.dart) | `BaseExtractor`<br>`MadaraExtractor`<br>`LightNovelWpExtractor`<br>`NovelFullExtractor`<br>`ReadWnExtractor`<br>`RoyalRoadExtractor` | Multi-engine web novel scraping across 31+ sources; HTML parsing via `package:html`, custom CSS selector extraction, text sanitization, and fallback heuristics. |
| **Anti-Bot & Session Clearance** | [`lib/core/services/webview_session_manager.dart`](../lib/core/services/webview_session_manager.dart)<br>[`lib/ui/widgets/source_webview_screen.dart`](../lib/ui/widgets/source_webview_screen.dart) | `WebViewSessionManager`<br>`SourceWebViewScreen` | Automated headless Cloudflare Turnstile & Challenge clearance; extraction and injection of `cf_clearance` cookies and mirror user-agents for `http.Client`. |
| **Persistence & Chapter Storage** | [`lib/core/database/database_helper.dart`](../lib/core/database/database_helper.dart)<br>[`lib/services/downloader_service.dart`](../lib/services/downloader_service.dart) | `DatabaseHelper`<br>`DownloaderService`<br>`NovelDao`<br>`ChapterDao` | SQLite-backed chapter and metadata storage via `sqflite`; disk caching of downloaded chapters for 100% offline reading and background batch downloads. |
| **Domain Models & Utilities** | [`lib/models/novel.dart`](../lib/models/novel.dart)<br>[`lib/models/chapter.dart`](../lib/models/chapter.dart)<br>[`lib/core/utils/text_cleaner.dart`](../lib/core/utils/text_cleaner.dart) | `Novel`<br>`Chapter`<br>`TextCleaner` | Immutable domain data structures with JSON serialization; regex-driven text sanitization stripping watermarks, promotional ads, and author notes. |
| **Reader UI & Dynamic Sync** | [`lib/ui/screens/reader_screen.dart`](../lib/ui/screens/reader_screen.dart)<br>[`lib/ui/widgets/tts_sheet.dart`](../lib/ui/widgets/tts_sheet.dart) | `ReaderScreen`<br>`TtsSheet` | High-performance scrolling reader with custom Amoled/Dark/Sepia themes, real-time sentence highlight synchronizing with the active audio stream, and sleep timer. |
| **Container & Web Hosting** | [`Dockerfile`](../Dockerfile)<br>[`nginx.conf`](../nginx.conf)<br>[`docker-compose.yml`](../docker-compose.yml)<br>[`.dockerignore`](../.dockerignore) | Multi-Stage Dockerfile<br>NGINX Alpine Web Server | Production Dockerization compiling Flutter CanvasKit Web app into an ultra-slim (22 MB) container served with Gzip, SPA fallback, and security headers. |
| **Multi-Platform CI/CD Pipeline** | [`.github/workflows/build-and-release.yml`](../.github/workflows/build-and-release.yml) | GitHub Actions Matrix Workflow | Automated compilation and packaging for Android (APK), Linux (tar.gz), Windows (zip), and macOS (universal zip) with automated GitHub Release publishing. |

---

## 🧭 Master Quick Links

- [Go to Technical Deep Dive (`NOVELS_WORLD_DEEP_DIVE.md`)](NOVELS_WORLD_DEEP_DIVE.md)
  - [1. Executive Summary & 30-Second Elevator Pitch](NOVELS_WORLD_DEEP_DIVE.md#1-executive-summary--30-second-pitch)
  - [2. Prerequisite Computer Science Foundations](NOVELS_WORLD_DEEP_DIVE.md#2-prerequisite-computer-science-foundations)
  - [3. High-Level System Architecture](NOVELS_WORLD_DEEP_DIVE.md#3-high-level-system-architecture)
  - [4. Subsystem Deep Dives](NOVELS_WORLD_DEEP_DIVE.md#4-subsystem-deep-dives)
  - [5. Real-World Engineering Case Studies (10 In-Depth Breakdowns)](NOVELS_WORLD_DEEP_DIVE.md#5-real-world-engineering-case-studies)
  - [6. Senior Technical Interview Q&A Cheatsheet](NOVELS_WORLD_DEEP_DIVE.md#6-technical-interview-qa-cheatsheet)
- [Go to Complete Development Log & Problem-Solving (`COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md`)](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md)
  - [Phase 1: Inception & Scraper Architecture](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-1-inception-and-multi-source-scraper-architecture)
  - [Phase 2: Reader UI & Offline Batch Storage](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-2-reader-ui-and-offline-batch-storage)
  - [Phase 3: The Neural Audio Revolution](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-3-the-neural-audio-revolution-and-tts-engine-integration)
  - [Phase 4: The Battle for Gapless Playback (Silence Trimming)](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-4-the-battle-for-gapless-playback-and-silence-trimming)
  - [Phase 5: The Race Condition Crisis (Monotonic FIFO Sequencing)](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-5-the-race-condition-crisis-monotonic-fifo-sequencing)
  - [Phase 6: Acoustic Partitioning & Model Unification](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-6-acoustic-partitioning-and-model-unification)
  - [Phase 7: Multi-Platform CI/CD & Local Builds](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-7-multi-platform-cicd-and-local-builds)
  - [Phase 8: GitHub Actions Hardening & Release Publishing](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-8-github-actions-hardening-and-release-publishing)
  - [Phase 9: Production Containerization & Docker Hub Deployment](COMPLETE_CHAT_DEVELOPMENT_LOG_AND_PROBLEM_SOLVING.md#phase-9-production-containerization-and-docker-hub-deployment)
