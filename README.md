<div align="center">

# 📖 Novels World
### *Next-Gen Web Novel Reader & Continuous Neural AI Audiobook Platform*

<img src="assets/icon/app_icon_1024.png" width="130" height="130" alt="Novels World App Icon" style="border-radius: 28px; box-shadow: 0 12px 30px rgba(139, 92, 246, 0.4); margin: 15px 0;" />

<p align="center">
  <a href="https://github.com/AdityaPatra-dev/Novels-World/releases/latest"><img src="https://img.shields.io/github/v/release/AdityaPatra-dev/Novels-World?color=8B5CF6&label=Latest%20Release&style=for-the-badge&logo=github" alt="Release" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x%20%7C%20Dart%203.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" /></a>
  <a href="https://github.com/AdityaPatra-dev/Novels-World/actions"><img src="https://img.shields.io/badge/Tests-44%2F44%20Passing-10B981?style=for-the-badge&logo=githubactions&logoColor=white" alt="Tests" /></a>
  <a href="#-platforms"><img src="https://img.shields.io/badge/Platforms-Android%20%7C%20Linux%20%7C%20Windows%20%7C%20macOS-EC4899?style=for-the-badge" alt="Platforms" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-F59E0B?style=for-the-badge" alt="License" /></a>
</p>

<p align="center">
  <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=18&duration=2500&pause=800&color=A78BFA&center=true&vCenter=true&width=620&lines=31%2B+Web+Novel+Catalogs+In+One+App;0ms+Gapless+Sample-Accurate+Audiobooks;5+Specialized+AI+Vocal+Personas;Instant+Cloudflare+%26+Turnstile+Clearance;Offline+Chapter+Caching+%26+Sleep+Timer" alt="Typing SVG" />
</p>

---

</div>

## 🌟 Overview

**Novels World** is a premier open-source multi-source web novel reader and studio-grade AI audiobook streaming app. 

Built with Flutter and high-performance native audio pipelines, Novels World aggregates **31+ major web novel platforms** into a distraction-free, customizable reading environment. Experience books with **sample-accurate, zero-gap continuous AI narration** featuring authentic breathing, emotional sentence prosody, and genre-specific voices (Xianxia, LitRPG, Grimdark, Romance, and High Fantasy).

> [!TIP]
> **Looking for systems architecture, scraper algorithms, or audio queue mechanics?**
> See the complete [TECHNICAL.md](TECHNICAL.md) for deep-dive diagrams, frame trimmers, and engineering specs.

---

## ✨ Features at a Glance

* 🎙️ **Sample-Accurate Gapless Audiobooks:** 0ms transitions between paragraphs powered by native ExoPlayer queueing and real-time MPEG silence stripping.
* 🎭 **5 Specialized Neural AI Vocal Engines:**
  * **Microsoft Neural HD (Studio AI):** 8 flagship voices with human breathing, baritone resonance, and dynamic dialogue inflection.
  * **Kokoro-82M (Audiophile Drama):** Calibrated for deliberate literary pacing and dramatic character acting.
  * **Piper Fast Neural (Speed Reading):** Crisp consonant articulation optimized for 1.25x–2.5x speed listening.
  * **Sherpa-Matcha (Asian Webnovels):** Built-in phonetic normalizer for Xianxia cultivation terms (*Qi*, *Dantian*, *Dao*, *Sect*, *Elder*) and Japanese/Korean names.
  * **Device Native (Hardware Fallback):** Zero-data, 100% offline hardware TTS.
* 🌐 **31+ Aggregated Sources:** Instant access to Royal Road, Scribble Hub, WuxiaWorld, NovelFull, FreeWebNovel, ReadWN, NovelBin, and more.
* 🛡️ **Anti-Bot & Cloudflare Clearance:** Transparent headless engine synchronization with JA3 TLS fingerprinting and Turnstile clearance.
* 📥 **Offline Batch Downloader:** Download hundreds of chapters with progress indicators and read on flights with zero internet.
* 🎨 **Bespoke Reading Typography:** Amoled, Dark, Sepia, and Light palettes with customizable font sizing, line height, and live paragraph sync.
* ⏱️ **Audio Sleep Timer:** 15m, 30m, 45m, 60m countdown timers with automated end-of-chapter triggers and volume fadeout.

---

## 🚀 Installation & Downloads

Choose your platform below to download the latest release:

<details open>
<summary><b>📱 Android Installation (APK)</b></summary>

<br />

1. Download the latest **`Novels-World-Android-v1.1.0.apk`** from [GitHub Releases](https://github.com/AdityaPatra-dev/Novels-World/releases/latest).
2. Tap the downloaded file on your Android device.
3. If prompted, allow **Install from Unknown Sources** in your browser settings.
4. Tap **Install** and launch Novels World!

**Via ADB (CLI):**
```bash
adb install -r Novels-World-Android-v1.1.0.apk
```

</details>

<details>
<summary><b>🐧 Linux Desktop Installation (Portable & Native)</b></summary>

<br />

1. Download **`Novels-World-Linux-x64.tar.gz`** from [GitHub Releases](https://github.com/AdityaPatra-dev/Novels-World/releases/latest).
2. Extract and run:

```bash
# Extract the bundle
tar -xzvf Novels-World-Linux-x64.tar.gz -C ~/novels_world/

# Launch the app
cd ~/novels_world && ./novels_world
```

*Required system libraries on Debian/Ubuntu/Fedora:*
```bash
# Ubuntu / Debian
sudo apt-get install -y libgtk-3-0 libasound2

# Fedora / RHEL
sudo dnf install -y gtk3 alsa-lib
```

</details>

<details>
<summary><b>🪟 Windows Desktop Installation</b></summary>

<br />

1. Download **`Novels-World-Windows-x64.zip`** from [GitHub Releases](https://github.com/AdityaPatra-dev/Novels-World/releases/latest).
2. Right-click the `.zip` file and select **Extract All**.
3. Double-click **`novels_world.exe`** to start reading!

</details>

<details>
<summary><b>🍎 macOS Desktop Installation</b></summary>

<br />

1. Download **`Novels-World-macOS-Universal.zip`** from [GitHub Releases](https://github.com/AdityaPatra-dev/Novels-World/releases/latest).
2. Extract the archive and drag **`Novels World.app`** into your **Applications** folder.
3. Open via Launchpad.

</details>

---

## 🛠️ Building from Source

Ensure you have [Flutter 3.x](https://flutter.dev/docs/get-started/install) and git installed:

```bash
# 1. Clone the repository
git clone https://github.com/AdityaPatra-dev/Novels-World.git
cd Novels-World

# 2. Install dependencies
flutter pub get

# 3. Run automated tests (44/44 passing)
flutter test

# 4. Build for your platform
flutter build apk --release       # Android
flutter build linux --release     # Linux
flutter build windows --release   # Windows
flutter build macos --release     # macOS
```

---

## 🗺️ Navigation & Gestures

| Action | Control |
| :--- | :--- |
| **Play / Pause Audio** | Tap Floating Audio Bar or bottom Play icon |
| **Jump to Specific Paragraph** | Tap any paragraph text directly in the reader |
| **Change Voice / Model** | Tap Model chip in the player bar |
| **Adjust Speed** | Tap Speed chip (Cycles `0.75x` $\rightarrow$ `1.0x` $\rightarrow$ `1.25x` $\rightarrow$ `1.5x` $\rightarrow$ `2.0x`) |
| **Sleep Timer** | Tap Moon icon in player bar to select duration |
| **Reader Settings** | Tap `Aa` icon in top bar to configure theme, fonts & line spacing |

---

## 📄 License & Acknowledgments

* Distributed under the **MIT License**. See `LICENSE` for details.
* Crafted with ❤️ for web novel lovers and audiobook binge readers.
* Technical architecture and systems documentation available in [TECHNICAL.md](TECHNICAL.md).
