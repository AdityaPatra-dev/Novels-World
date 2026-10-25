# 📖 Novels World — Official Docker Container

[![Docker Pulls](https://img.shields.io/docker/pulls/adityapatra/novels-world?style=for-the-badge&logo=docker&logoColor=white&color=2496ED)](https://hub.docker.com/r/adityapatra/novels-world)
[![Docker Image Size](https://img.shields.io/docker/image-size/adityapatra/novels-world/latest?style=for-the-badge&color=00D26A)](https://hub.docker.com/r/adityapatra/novels-world)
[![Version](https://img.shields.io/badge/version-v1.1.0-blueviolet?style=for-the-badge)](https://github.com/AdityaPatra-dev/Novels-World/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

**Novels World** is a modern, high-performance web novel reader and continuous neural AI audiobook Progressive Web App (PWA).

This production-grade Docker image packages the optimized CanvasKit Web build served behind a hardened, high-throughput **NGINX Alpine** server with automated gzip compression, SPA client routing, and native browser Web Audio support.

---

## ⚡ Quick Start

### 1. Run with Docker CLI
```bash
docker run -d \
  --name novels-world \
  --restart unless-stopped \
  -p 8080:80 \
  adityapatra/novels-world:latest
```
Now navigate to **`http://localhost:8080`** in your browser!

---

### 2. Run with Docker Compose
Create a `docker-compose.yml` file:
```yaml
services:
  novels-world:
    image: adityapatra/novels-world:latest
    container_name: novels-world
    restart: unless-stopped
    ports:
      - "8080:80"
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://127.0.0.1/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 5s
```
Launch the stack:
```bash
docker compose up -d
```

---

## 🌟 Key Features

* **🎙️ Continuous Neural AI Audiobook Stream**: 0ms gapless speech transitions with sample-accurate sentence playback and automated digital silence trimming.
* **🎭 5 Specialized AI Vocal Engines**:
  * *Microsoft Neural HD (Studio AI)*
  * *Kokoro-82M (Audiophile Literature Drama)*
  * *Piper Fast Neural (Speed Reading 1.25x–2.5x)*
  * *Sherpa-Matcha (Xianxia & Asian CJK Phonetics)*
  * *Device Native Web Speech Synthesis*
* **📚 31+ Web Novel Sources Supported**: Direct search, catalog indexing, and real-time chapter scraping for WordPress Madara, Themesia LightNovelWP, NovelFull, ReadWN, Royal Road, Scribble Hub, and more.
* **📱 Responsive PWA**: Installs directly to your home screen or desktop application drawer with offline reading cache.
* **🪶 Ultra-Lightweight Footprint**: Base image is only **~22 MB** compressed and consumes under **25 MB RAM** at idle.

---

## 🔒 Production Security & Performance Headers

The bundled NGINX configuration includes production-hardened headers:
* `X-Frame-Options: SAMEORIGIN`
* `X-Content-Type-Options: nosniff`
* `Cross-Origin-Embedder-Policy: credentialless`
* `Cross-Origin-Opener-Policy: same-origin`
* `Referrer-Policy: strict-origin-when-cross-origin`
* `Gzip` compression for JSON, WASM, JavaScript, and CSS.
* Immutable 30-day cache for CanvasKit binaries with cache-busting for PWA service workers.

---

## 🏷️ Available Tags

* `latest` — Latest stable production build
* `1.1.0`, `v1.1.0` — Specific release tags matching GitHub milestones

---

## 🔗 Links & Source Code

* **GitHub Repository**: [AdityaPatra-dev/Novels-World](https://github.com/AdityaPatra-dev/Novels-World)
* **Releases & Desktop Downloads**: [GitHub Releases](https://github.com/AdityaPatra-dev/Novels-World/releases)
* **Author**: Aditya Patra ([@AdityaPatra-dev](https://github.com/AdityaPatra-dev))

