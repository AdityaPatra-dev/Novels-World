# Global Search Optimization & Reliability Plan

**Target Components:**
- `lib/core/services/global_search_controller.dart` (`GlobalSearchController`, `GlobalSearchState`, `GroupedNovelMatch`, `SourceSearchResult`)
- `lib/ui/search/global_search_screen.dart` (`GlobalSearchScreen`)
- `lib/extractors/source_registry.dart` (`SourceRegistry`)
- `lib/extractors/**` (`NovelSource.search` implementations, e.g. `NovelFullExtractor`)
- `cloudflare-worker/worker.js` (Web CORS/Edge proxy used on Flutter Web)

---

## 1. Current Audit: Why Global Search Is Slow & Error-Prone

1. **Severe Concurrency & Timeout Bottleneck (`maxConcurrent = 5`, `sourceTimeout = 8s`)**
   - `GlobalSearchController.search()` runs a fixed pool of **5 workers** across every source in `SourceRegistry.getAllSources()` (~80+ sources).
   - If 20–30 sources hit the 8s timeout or run slow sequential fallbacks, total wall-clock time stretches to **45–90+ seconds**.
2. **Sequential Multi-URL Fallbacks Inside Extractors**
   - Extractors such as `NovelFullExtractor.search()` iterate sequentially through multiple `searchCandidates` over HTTP and then sequentially through `WebViewSessionManager.instance.fetchHtmlViaWebView(...)`.
   - When `Future.timeout(sourceTimeout)` fires in `GlobalSearchController`, Dart does **not** cancel the underlying HTTP socket or headless WebView, leaking background network and UI-thread work.
3. **No Circuit Breaker or Source Health Tracking**
   - Dead, ISP-blocked, Cloudflare-403, or broken sources are retried on every single search, burning 8s worker slots repeatedly.
   - Extractors that catch errors and return `[]` are recorded as `isSuccess: true` with `0` results, masking real `403`/`404`/`5xx`/parsing failures.
4. **No Script / Language / Scope Filtering Before Dispatch**
   - An English query (e.g., `"Shadow Slave"`) still queries Hindi, Odia, Arabic, Turkish, Indonesian, and classical Sanskrit archives.
   - Likewise, a Devanagari or Odia query waits behind 60+ unrelated English aggregators.
5. **No Instant Local Pre-Search (`t = 0ms` Results)**
   - The user's saved library (`LibraryProvider.novels`) and already-fetched `BrowseScreen` memory cache are not surfaced immediately while network workers are running.
6. **Web Proxy Contention (`cloudflare-worker/worker.js`)**
   - On Flutter Web, almost every source routes through `novels-world-proxy.adityapatraraj.workers.dev`. Firing 80+ uncached search requests saturates browser connection limits and risks Worker subrequest/rate throttling.
7. **CPU-Heavy Re-Sorting on Every 200ms UI Tick**
   - `maybeEmitUpdate()` calls `groupedMap.values.toList()..sort(...)` using `computeRelevanceScore()`, which compiles/runs multiple `RegExp`s and `normalizeTitle()` inside the `sort()` comparator on every emission.
8. **Broken Unicode Clustering, No Fuzzy/Typo Matching & Naive Primary Selection**
   - `normalizeTitle()` strips `[^a-z0-9\s]`, wiping out non-ASCII titles (Hindi, Odia, Arabic, CJK) and breaking cross-source grouping and relevance scoring.
   - No typo tolerance (Levenshtein/bigram similarity), stopword handling (`the`, `of`, `a`), or common web-novel acronym expansion (`LOTM`, `ORV`, `TBATE`).
   - `GroupedNovelMatch.primaryNovel` blindly picks `sourceVariants.values.first` (fastest responder) instead of the variant with the best cover, author metadata, and source reliability.
9. **Session-Only All-or-Nothing Cache**
   - `_queryCache` only stores `finalState` if all sources complete without cancellation, has no TTL, and caches empty/degraded results if the network hiccupped.

---

## 2. Target Architecture & Improvements

### Phase 1: Instant UX, Smart Scheduling & Endpoint Learning (Highest Impact)
1. **Instant `t = 0ms` Local + Static Catalog Search**
   - On every keystroke (debounced locally in `< 5ms`) and immediately upon search submit (`t = 0ms`), match against:
     - `LibraryProvider.novels`
     - `BrowseScreen`'s in-memory source cache (`_sourceNovelsCache`)
     - Cached catalogs of **static/archive sources** (e.g., Standard Ebooks, Odia Virtual Academy, Ama Odisha, Bharat Discovery, Kavita Kosh, Gadya Kosh, Arthur Conan Doyle) so those sources don't re-download full index pages on every query.
2. **Tiered Search Modes (`Fast` vs `Deep`) + Language/Script Auto-Routing**
   - **Fast Mode (Default, ~1–3s):** Search the top 12–15 high-reliability, fast sources for the detected query script/language (plus a **"Search All Sources"** button to expand on demand).
   - **Script Detection:** Detect Devanagari (`\u0900-\u097F`) → prioritize Hindi sources; Odia (`\u0B00-\u0B7F`) → prioritize Odia sources; Arabic/CJK → prioritize matching language sources; Latin → prioritize English + multi-language archives (with scope chips: `Fast`, `English`, `Hindi`, `Odia`, `Classics`, `All`).
3. **Working Search Endpoint Caching Per Source**
   - Remember which `searchCandidates` URL pattern succeeded for each `source.id` (e.g., `/novel-list/search?keyword=` vs `/search?keyword=`) so subsequent searches skip dead candidate URLs on the first attempt.
4. **Adaptive Concurrency & Shorter Per-Source Budgets**
   - Raise worker pool from `5` to **`10–12` on native** (`6` on web to respect browser connection limits).
   - Use tiered timeouts: **4s** for fast JSON/HTML APIs, **6s** for standard scrapers, and **skip headless WebView fallback during Global Search** unless the user explicitly triggers a single-source retry (WebView fallback is the #1 latency & hang culprit).

### Phase 2: Fault Tolerance, Circuit Breakers, Cancellation & Edge Caching
5. **Per-Source Circuit Breaker & Latency EMA**
   - Track `(consecutiveFailures, cooldownUntil, avgLatencyMs, lastError)` per `source.id` in memory (optionally seeded from CI health checks or persisted via `SharedPreferences`).
   - If a source fails `3` times in a row (timeout, 403, 5xx), open its circuit for `10 minutes` (skip it during Global Search and list it under a collapsible *"Unavailable / Skipped"* section with a manual retry button).
   - Sort dispatch order dynamically by `(tierPriority, avgLatencyMs)` so the fastest healthy sources always finish first.
6. **True Request Cancellation (`SearchCancelToken`)**
   - Pass an abort/cancellation token keyed by `generationId` into HTTP requests.
   - When the user clears, submits a new query, or navigates back, immediately abort in-flight HTTP sockets instead of letting them drain for 8 seconds.
7. **Structured `SearchOutcome` & Source `SearchCapability`**
   - Tag sources with `SearchCapability` (`nativeSearch`, `catalogFilter`, `none`) so browse-only sources don't waste search slots.
   - Return structured outcomes (`ok`, `empty`, `blocked_403`, `timeout`, `networkError`) instead of swallowing exceptions and returning `[]`.
8. **Edge Caching for Web Proxy (`cloudflare-worker/worker.js`)**
   - Add short-TTL Cloudflare Cache API caching (e.g., `5 minutes`) for GET search/catalog responses in `worker.js` so repeated/popular web queries return from the edge in `< 50ms` without hitting origin servers.

### Phase 3: Search Accuracy, Fuzzy Matching & Main-Thread Performance
9. **Unicode-Safe `normalizeTitle()` + Stopwords + Acronym & Fuzzy Matching**
   - Replace `[^a-z0-9\s]` with Unicode-aware stripping (`[^\p{L}\p{N}\s]` with `unicode: true`) so Hindi, Odia, Arabic, and CJK titles normalize and cluster accurately.
   - Normalize smart quotes (`’` → `'`) before dispatching queries to extractors.
   - Add **stopword-insensitive token matching** (`the`, `of`, `a`, `an`, `and`), **common acronym expansion** (`LOTM`, `ORV`, `TBATE`, `RI`), and **bounded bigram/Levenshtein similarity** so minor typos (e.g., `"Shadow Slav"`) still surface the right novel.
10. **Precomputed Relevance Keys (Zero Regexes Inside `sort()`)**
    - Precompute `normalizedTitle`, `tokens`, and `relevanceScore` **once** when a `GroupedNovelMatch` is created or updated instead of recomputing regexes inside `List.sort()` on every 200ms UI tick.
11. **Quality-Aware `primaryNovel` Selection**
    - Score each variant inside `GroupedNovelMatch.sourceVariants` by: valid high-res cover URL (`+3`), non-empty author (`+2`), source reliability tier (`+2`), and clean title (`+1`), rather than `sourceVariants.values.first`.
12. **TTL Query Cache (Never Caching Broken Runs)**
    - Store `(GlobalSearchState, DateTime cachedAt)` with a `10-minute` TTL, only caching searches with healthy source coverage, plus a manual **Refresh** button to bypass cache.

### Phase 4: Search Screen UI, Observability & Testing
13. **Actionable Controls in `GlobalSearchScreen`**
    - **Stop / Cancel** button while searching, **Expand to All Sources** CTA after Fast Mode finishes, and **Retry Failed Sources** button when errors/timeouts occur.
    - Clear source status pills in the *"By Source"* tab (`24 found • 420ms`, `Timed out (4s)`, `Blocked (403)`).
14. **Automated Unit & Benchmark Tests (`test/global_search_test.dart`)**
    - Cover Unicode title normalization (Hindi/Odia/English), acronym/fuzzy matching, precomputed relevance ranking, circuit breaker trip/recovery, generation cancellation, and `primaryNovel` variant selection.

---

## 3. Recommended Execution Order
1. **Step 1 (Accuracy & Speed Core):** Unicode-safe `normalizeTitle()`, fuzzy/acronym matching, precomputed relevance scoring, and quality-based `primaryNovel` in `GlobalSearchController` + unit tests.
2. **Step 2 (Concurrency & Resilience):** Skip WebView fallback in Global Search, cache working search URL patterns per extractor, raise concurrency (`10–12` native / `6` web), tighten timeouts (`4–6s`), and add per-source circuit breakers.
3. **Step 3 (Instant UX & Scopes):** Instant `t = 0ms` local Library/Browse/static-catalog matching, Fast/Deep toggle, script-aware language scope chips, and Stop/Retry UI in `GlobalSearchScreen`.
4. **Step 4 (Cancellation & Web Edge Cache):** `SearchCancelToken` across extractors + 5-minute edge cache in `cloudflare-worker/worker.js`.

## 4. Expected Impact
| Metric | Current | Target After Plan |
|---|---|---|
| Time to first results | 1–4s (network only) | **< 15ms** (local + static cache) + **< 1.2s** (top sources) |
| Full Fast-mode completion | 45–90s | **1.5–3.5s** |
| Error rate from dead/403 sources | High (retried every query) | **Near 0%** (auto-tripped circuit breaker) |
| Typo / Acronym / Hindi / Odia search | Broken or missed | **Full Unicode (`\p{L}\p{N}`) + fuzzy & alias support** |
