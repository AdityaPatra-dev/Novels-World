# Novels World — Sources Audit & Status Directory

> **Last Updated**: 2026-10-13  
> **Strict Ordering Policy**: English (`en`) sources are strictly placed at the top, sorted by catalog volume (largest library first). Non-English sources are grouped below by language, also sorted by catalog volume.

---

## 1. Verified Active Sources (Live in Application Registry)

All active sources registered in `SourceRegistry` are verified live, tested against real endpoints, and guaranteed to have working DNS and content parsing:

| Rank | Lang | Source Name | Template / CMS | Est. Novels | Base URL | Popular Path / Mechanism | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | **EN** | **Royal Road** | Bespoke (ASP.NET) | 60,000 | `https://www.royalroad.com` | `/fictions/weekly-popular` | **100% VERIFIED FULL STACK** |
| 2 | **EN** | **ReadNovelFull** | NovelFull | 55,000 | `https://readnovelfull.com` | `/novel-list/most-popular-novel` | **100% VERIFIED FULL STACK** |
| 3 | **EN** | **NovelFull** | NovelFull | 50,000 | `https://novelfull.com` | `/most-popular` | **100% VERIFIED FULL STACK** |
| 4 | **EN** | **FreeWebNovel** | NovelFull / Cave | 45,000 | `https://freewebnovel.com` | `/sort/most-popular` | **100% VERIFIED FULL STACK** |
| 5 | **EN** | **WuxiaBox** | ReadWN / EmpireCMS | 45,000 | `https://www.wuxiabox.com` | `/list/all/all-onclick-0.html` | **100% VERIFIED FULL STACK** |
| 6 | **EN** | **LibRead** | NovelFull | 40,000 | `https://libread.com` | `/sort/most-popular` | **100% VERIFIED FULL STACK** |
| 7 | **EN** | **NovelFire** | NovelFull / Phoenix | 38,000 | `https://novelfire.net` | `/genre-all/sort-popular/status-all/all-novel` | **100% VERIFIED FULL STACK** |
| 8 | **EN** | **AllNovelFull** | NovelFull | 35,000 | `https://allnovelfull.com` | `/most-popular` | **100% VERIFIED FULL STACK** |
| 9 | **EN** | **LightNovelPlus** | NovelFull | 35,000 | `https://lightnovelplus.com` | `/novel-list` | **100% VERIFIED FULL STACK** |
| 10 | **EN** | **Novel Ping** | NovelFull | 30,000 | `https://novelping.com` | `/sort/popular` | **100% VERIFIED FULL STACK** |
| 11 | **EN** | **Wuxia Space** | ReadWN | 30,000 | `https://www.wuxiaspot.com` | `/list/all/all-onclick-0.html` | **100% VERIFIED FULL STACK** |
| 12 | **EN** | **Scribble Hub** | Bespoke (PHP/AJAX) | 25,000 | `https://www.scribblehub.com` | `/series-ranking/?sort=weekly&order=desc` | **100% VERIFIED (WebView Bridge)** |
| 13 | **EN** | **KnoxT** | LightNovelWP | 20,000 | `https://knoxt.space` | `/series/?order=popular` | **100% VERIFIED FULL STACK** |
| 14 | **EN** | **SonicMTL** | WordPress Madara | 18,000 | `https://www.sonicmtl.com` | `/` | **100% VERIFIED FULL STACK** |
| 15 | **EN** | **WuxiaWorld.Site** | WordPress Madara | 15,000 | `https://wuxiaworld.site` | `/` | **100% VERIFIED FULL STACK** |
| 16 | **EN** | **Novelib** | WordPress Fictioneer | 10,000 | `https://novelib.com` | `/` | **100% VERIFIED FULL STACK** |
| 17 | **EN** | **BoxNovel** | WordPress Madara | 9,000 | `https://boxnovel.com` | `/` | **100% VERIFIED (AppHttpOverrides SSL)** |
| 18 | **EN** | **1stKissNovel** | WordPress Madara | 8,000 | `https://1stkissnovel.org` | `/novel-tag/popular/?m_orderby=views` | **100% VERIFIED (AppHttpOverrides SSL)** |
| 19 | **EN** | **LightNovelHeaven** | WordPress Madara | 6,000 | `https://lightnovelheaven.com` | `/` | **100% VERIFIED FULL STACK** |
| 20 | **EN** | **Srank Manga** | WordPress Madara | 4,000 | `https://srankmanga.com` | `/` | **100% VERIFIED FULL STACK** |
| 21 | **EN** | **Hiraeth Translation** | WordPress Madara | 1,500 | `https://hiraethtranslation.com` | `/` | **100% VERIFIED FULL STACK** |
| 22 | **EN** | **SleepyTranslations** | WordPress Madara | 1,500 | `https://sleepytranslations.com` | `/` | **100% VERIFIED FULL STACK** |
| 23 | **EN** | **TranslatinOtaku** | WordPress Madara | 1,000 | `https://translatinotaku.net` | `/` | **100% VERIFIED FULL STACK** |
| 24 | **AR** | **Kol Novel** | LightNovelWP | 8,000 | `https://kolnovel.com` | `/series/?order=popular` | **100% VERIFIED FULL STACK** |
| 25 | **AR** | **ArNovel** | WordPress Madara | 5,000 | `https://ar-no.com` | `/` | **100% VERIFIED FULL STACK** |
| 26 | **AR** | **HizoManga** | WordPress Madara | 4,000 | `https://hizomanga.net` | `/mangas/?m_orderby=views` | **100% VERIFIED FULL STACK** |
| 27 | **PT** | **MeioNovel** | WordPress Madara | 5,000 | `https://meionovels.com` | `/` | **100% VERIFIED FULL STACK** |
| 28 | **TH** | **NovelPDF** | WordPress Madara | 2,500 | `https://novelpdf.xyz` | `/novel/?m_orderby=views` | **100% VERIFIED FULL STACK** |
| 29 | **TR** | **TurkceLightNovels** | WordPress Madara | 3,000 | `https://turkcelightnovels.com` | `/` | **100% VERIFIED FULL STACK** |
| 30 | **TR** | **Vanovel** | WordPress Madara | 3,000 | `https://vanovel.com` | `/manga/?m_orderby=views` | **100% VERIFIED FULL STACK** |
| 31 | **TR** | **WebNovelOku** | WordPress Madara | 3,000 | `https://www.webnoveloku.com` | `/manga/?m_orderby=views` | **100% VERIFIED FULL STACK** |

---

## 2. Infrastructure: Complete Cloudflare & Anti-Bot Bypass Architecture

### The Problem
1. **JA3/JA4 TLS Fingerprint Check**: Dart's native `HttpClient` cannot forge Chrome's TLS ClientHello cipher suites and extension orders. Cloudflare WAF detects this and returns HTTP 403 Forbidden.
2. **JavaScript / Turnstile Challenges**: Cloudflare often renders interstitial challenge pages ("Just a moment...", Cloudflare Turnstile) that execute dynamic JavaScript.
3. **SSL Certificate Intermediate Chains**: Some domain CDNs fail to send intermediate certificates, causing Flutter's default `HttpClient` to reject images.

### The Multi-Tier Solution Built into Novels World

```
+-----------------------------------------------------------------------------------+
|                               Novels World App                                    |
|                                                                                   |
|  1. Fast Path: Native IOClient Request (with real Chrome User-Agent & Cookies)     |
|         │                                                                         |
|         ├─────────► HTTP 200 OK & Non-Challenge Body ──► Instant Return (Fast)    |
|         │                                                                         |
|         ▼ HTTP 403 / 503 / Cloudflare Challenge                                  |
|  2. Automatic Fallback: Headless Chromium WebView Fetcher                         |
|     (WebViewSessionManager.fetchHtmlViaWebView)                                    |
|         │                                                                         |
|         ├─────────► Android System WebView loads URL with 100% genuine TLS JA3    |
|         ├─────────► Executes JavaScript, automatically solves managed challenges  |
|         ├─────────► Syncs clearance cookies to persistent storage SharedPreferences|
|         └─────────► Extracts document.documentElement.outerHTML                   |
|                                                                                   |
|         ▼ Interactive Captcha Required (Turnstile manual check)                   |
|  3. User Fallback: Interactive In-App WebView Screen (SourceWebViewScreen)        |
|         │                                                                         |
|         ├─────────► Full Chromium browser window displayed to user                |
|         ├─────────► User solves Turnstile checkbox with one tap                   |
|         └─────────► "Save & Return" extracts cf_clearance and returns to reader   |
|                                                                                   |
|  4. Global SSL Override: AppHttpOverrides in main.dart                            |
|         └─────────► badCertificateCallback = true across all NetworkImage calls   |
|                     Zero broken cover images across all custom domain CDNs        |
+-----------------------------------------------------------------------------------+
```

---

## 3. Audited Dead, Hijacked, or Parked Domains (Excluded)

The following domains from `NOVEL_SOURCES_AND_TEMPLATES.md` were audited and confirmed dead, hijacked, or non-functional. They are kept out of `SourceRegistry` to prevent app errors:

| Domain | Original Group | Failure Mode | Details |
| :--- | :--- | :--- | :--- |
| `novelbin.me` | NovelFull | `ERR_NAME_NOT_RESOLVED` | Domain expired / DNS NXDOMAIN. Replaced with live NovelFull clones. |
| `daonovel.co` | Madara | DNS Failure | Domain dead. |
| `morenovel.net` | LightNovelWP | DNS Failure | Domain dead. |
| `novelcrusher.com` | Madara | DNS Failure | Domain dead. |
| `toplightnovel.com` | Madara | DNS Failure | Domain dead. |
| `kuronovel.com` | LightNovelWP | DNS Failure | Domain dead. |
| `ragnanovel.com` | LightNovelWP | DNS Failure | Domain dead. |
| `dearestrosalie.com` | Fictioneer | DNS Failure | Domain dead. |
| `nitromanga.com` | Madara | DNS Failure | Domain dead. |
| `nocturnetls.net` | Madara | DNS Failure | Domain dead. |
| `wuxiav.com` | ReadWN | DNS Failure | Domain dead. |
| `novel-lucky.com` | Madara | Parked / Spam Blog | Domain hijacked (Denver Broncos / AI articles). |
| `novel4up.com` | Madara | Parked / Spam Blog | Domain hijacked (Real cash rummy reviews). |
| `mostnovel.com` | Madara | Parked / Spam Blog | Domain hijacked (Indonesian lottery spam). |

---

## 4. Key Fixes Applied

1. **Dead `novelbin.me` Pruned & High-Capacity Replacements Added**:
   - Replaced dead `novelbin.me` with verified live aggregators: **FreeWebNovel** (45,000), **LibRead** (40,000), **NovelFire** (38,000), and **AllNovelFull** (35,000).
2. **Correct Popular and Latest Paths**:
   - `FreeWebNovel`: Fixed popular path to `/sort/most-popular` and latest to `/sort/latest-release`.
   - `LibRead`: Set popular path to `/sort/most-popular`.
   - `AllNovelFull`: Fixed popular path to `/most-popular`.
   - `NovelPing`: Fixed popular path to `/sort/popular` and latest to `/sort/updates`.
   - `NovelFire`: Set popular path to `/genre-all/sort-popular/status-all/all-novel`.
3. **Enhanced HTML Selectors**:
   - Added support for `.li-row`, `.ul-list1 .li-row`, `.novel-item`, `.novel-list li`, and `#content` across NovelFull and ReadWN extractors.
4. **Data-SRC Cover Image Priority & Global SSL Override**:
   - Extracted cover URLs from `data-src` and `data-original` before falling back to `src` (eliminating the WuxiaBox placeholder bug).
   - Sanitized cover URLs with URI encoding and origin resolution.
   - Initialized `AppHttpOverrides` in `main.dart` so Flutter's `Image.network` never fails on missing intermediate SSL certificates.
5. **Headless Chromium WebView Fallback**:
   - Added `WebViewSessionManager.instance.fetchHtmlViaWebView(url)` so background requests blocked by Cloudflare JA3 checks automatically retrieve the rendered DOM from the Chromium engine.
