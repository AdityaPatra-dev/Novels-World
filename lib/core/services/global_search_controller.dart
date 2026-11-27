import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/novel.dart';
import '../../extractors/novel_source.dart';
import '../../extractors/source_registry.dart';

/// Search scope for filtering or prioritizing sources before dispatch.
enum GlobalSearchScope {
  fast('Fast (Top 15)'),
  all('All Sources'),
  english('English'),
  hindi('Hindi'),
  odia('Odia'),
  classics('Classics');

  final String label;
  const GlobalSearchScope(this.label);
}

/// Structured outcome status for a single source search.
enum SearchOutcomeStatus {
  ok,
  empty,
  timedOut,
  blocked,
  skippedCircuitBreaker,
  error,
}

/// Tracks per-source latency and consecutive failures for circuit-breaking.
class SourceHealthStats {
  int consecutiveFailures = 0;
  DateTime? cooldownUntil;
  double? avgLatencyMs;
  String? lastError;

  bool isCircuitOpen(DateTime now) =>
      cooldownUntil != null && now.isBefore(cooldownUntil!);

  void recordSuccess(Duration elapsed) {
    consecutiveFailures = 0;
    cooldownUntil = null;
    lastError = null;
    final ms = elapsed.inMilliseconds.toDouble();
    avgLatencyMs = avgLatencyMs == null ? ms : (avgLatencyMs! * 0.7 + ms * 0.3);
  }

  void recordFailure(String error, DateTime now) {
    consecutiveFailures++;
    lastError = error;
    if (consecutiveFailures >= 3) {
      cooldownUntil = now.add(const Duration(minutes: 10));
    }
  }
}

/// Result emitted by a single source during a global search session.
class SourceSearchResult {
  final NovelSource source;
  final List<Novel> novels;
  final bool isSuccess;
  final String? errorMessage;
  final Duration elapsed;
  final SearchOutcomeStatus status;

  const SourceSearchResult({
    required this.source,
    required this.novels,
    required this.isSuccess,
    this.errorMessage,
    required this.elapsed,
    this.status = SearchOutcomeStatus.ok,
  });
}

/// Represents a single novel found across one or more sources.
class GroupedNovelMatch {
  String canonicalTitle;
  String author;
  String coverUrl;
  final Map<NovelSource, Novel> sourceVariants;

  GroupedNovelMatch({
    required this.canonicalTitle,
    required this.author,
    required this.coverUrl,
    required this.sourceVariants,
  });

  /// The primary novel variant, preferring valid cover, author, and priority source.
  Novel get primaryNovel {
    if (sourceVariants.length == 1) return sourceVariants.values.first;
    Novel best = sourceVariants.values.first;
    int bestScore = -1;
    for (final entry in sourceVariants.entries) {
      final n = entry.value;
      int s = 0;
      if (n.coverUrl.isNotEmpty &&
          !n.coverUrl.contains('placeholder') &&
          !n.coverUrl.contains('blank')) {
        s += 3;
      }
      if (n.author.isNotEmpty && n.author != 'Unknown Author') s += 2;
      if (GlobalSearchController._priorityIds.contains(entry.key.id)) s += 2;
      if (!n.title.contains('[') && !n.title.contains('(')) s += 1;
      if (s > bestScore) {
        bestScore = s;
        best = n;
      }
    }
    return best;
  }

  /// List of sources where this novel was found
  List<NovelSource> get sources => sourceVariants.keys.toList();

  /// Total number of sources offering this novel
  int get sourceCount => sourceVariants.length;
}

/// Immutable state snapshot of the active global search session.
class GlobalSearchState {
  final String query;
  final GlobalSearchScope scope;
  final bool isSearching;
  final int totalSources;
  final int completedSources;
  final List<SourceSearchResult> sourceResults;
  final List<GroupedNovelMatch> groupedMatches;
  final List<Novel> allNovelsRaw;

  const GlobalSearchState({
    this.query = '',
    this.scope = GlobalSearchScope.fast,
    this.isSearching = false,
    this.totalSources = 0,
    this.completedSources = 0,
    this.sourceResults = const [],
    this.groupedMatches = const [],
    this.allNovelsRaw = const [],
  });

  double get progress => totalSources > 0 ? (completedSources / totalSources).clamp(0.0, 1.0) : 0.0;
  bool get isCompleted => totalSources > 0 && completedSources >= totalSources;
  int get totalNovelsFound => allNovelsRaw.length;
  int get failedOrSkippedCount => sourceResults
      .where((r) =>
          r.status == SearchOutcomeStatus.timedOut ||
          r.status == SearchOutcomeStatus.blocked ||
          r.status == SearchOutcomeStatus.error ||
          r.status == SearchOutcomeStatus.skippedCircuitBreaker)
      .length;

  GlobalSearchState copyWith({
    String? query,
    GlobalSearchScope? scope,
    bool? isSearching,
    int? totalSources,
    int? completedSources,
    List<SourceSearchResult>? sourceResults,
    List<GroupedNovelMatch>? groupedMatches,
    List<Novel>? allNovelsRaw,
  }) {
    return GlobalSearchState(
      query: query ?? this.query,
      scope: scope ?? this.scope,
      isSearching: isSearching ?? this.isSearching,
      totalSources: totalSources ?? this.totalSources,
      completedSources: completedSources ?? this.completedSources,
      sourceResults: sourceResults ?? this.sourceResults,
      groupedMatches: groupedMatches ?? this.groupedMatches,
      allNovelsRaw: allNovelsRaw ?? this.allNovelsRaw,
    );
  }
}

class _CachedSearchEntry {
  final GlobalSearchState state;
  final DateTime cachedAt;
  const _CachedSearchEntry(this.state, this.cachedAt);
}

/// Central controller orchestrating parallel multi-source global searches.
/// Includes instant local matching, script-aware routing, circuit breakers,
/// latency-ordered dispatch, and adaptive concurrency.
class GlobalSearchController extends ValueNotifier<GlobalSearchState> {
  GlobalSearchController() : super(const GlobalSearchState());

  int _currentGenerationId = 0;
  static const Duration sourceTimeout = Duration(seconds: 5);
  static const Duration _cacheTtl = Duration(minutes: 10);

  // In-memory TTL query cache for instant (0ms) global search repeat lookups
  static final Map<String, _CachedSearchEntry> _queryCache = {};
  static const int _maxCacheEntries = 40;

  // Per-source health & latency stats for circuit breaking
  static final Map<String, SourceHealthStats> _sourceHealth = {};

  static const List<String> _priorityIds = [
    'readnovelfull',
    'novelfull',
    'royalroad',
    'scribblehub',
    'freewebnovel',
    'wuxiaworld',
    'novelfire',
    'novelbin',
    'allnovelfull',
    'libread',
    'gutenberg',
    'standardebooks',
    'openlibrary',
    'internetarchive',
    'lightnovelpub',
  ];

  static const Set<String> _classicIds = {
    'gutenberg',
    'standardebooks',
    'openlibrary',
    'internetarchive',
    'arthurconandoyle',
    'vedicheritage',
    'hindwi',
    'gadyakosh',
    'kavitakosh',
    'bharatdiscovery',
    'odiabibhaba',
    'or_wikisource',
    'ova',
    'aamaodisha',
    'odiasahitya',
  };

  /// Resets all tripped source circuit breakers.
  static void resetCircuitBreakers() {
    _sourceHealth.clear();
  }

  /// Detects regional script language from the query string.
  static String? detectQueryLanguage(String query) {
    if (RegExp(r'[\u0900-\u097F]').hasMatch(query)) return 'hi';
    if (RegExp(r'[\u0B00-\u0B7F]').hasMatch(query)) return 'or';
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(query)) return 'ar';
    return null;
  }

  /// Selects and orders sources based on [scope], detected query script, and health.
  static List<NovelSource> selectSourcesForScope(
    List<NovelSource> all,
    GlobalSearchScope scope,
    String query,
  ) {
    final detectedLang = detectQueryLanguage(query);
    List<NovelSource> filtered;

    switch (scope) {
      case GlobalSearchScope.english:
        filtered = all.where((s) => s.lang.toLowerCase() == 'en').toList();
        break;
      case GlobalSearchScope.hindi:
        filtered = all.where((s) => s.lang.toLowerCase() == 'hi').toList();
        break;
      case GlobalSearchScope.odia:
        filtered = all.where((s) => s.lang.toLowerCase() == 'or').toList();
        break;
      case GlobalSearchScope.classics:
        filtered = all.where((s) => _classicIds.contains(s.id)).toList();
        break;
      case GlobalSearchScope.fast:
        if (detectedLang != null) {
          final regional = all.where((s) => s.lang.toLowerCase() == detectedLang).toList();
          filtered = regional.isNotEmpty ? regional.take(15).toList() : all.take(15).toList();
        } else {
          final prioritized = all.where((s) => _priorityIds.contains(s.id)).toList();
          if (prioritized.length < 15) {
            for (final s in all) {
              if (!prioritized.contains(s) && s.lang.toLowerCase() == 'en') {
                prioritized.add(s);
                if (prioritized.length >= 15) break;
              }
            }
          }
          filtered = prioritized;
        }
        break;
      case GlobalSearchScope.all:
        filtered = List<NovelSource>.from(all);
        break;
    }

    filtered.sort((a, b) {
      final aPri = _priorityIds.indexOf(a.id);
      final bPri = _priorityIds.indexOf(b.id);
      if (aPri != -1 && bPri != -1) return aPri.compareTo(bPri);
      if (aPri != -1) return -1;
      if (bPri != -1) return 1;

      final aLat = _sourceHealth[a.id]?.avgLatencyMs ?? 99999;
      final bLat = _sourceHealth[b.id]?.avgLatencyMs ?? 99999;
      return aLat.compareTo(bLat);
    });

    return filtered;
  }

  /// Executes global search across selected sources with controlled concurrency.
  /// Results stream incrementally into [value] in real time.
  Future<void> search(
    String query, {
    List<NovelSource>? targetSources,
    GlobalSearchScope scope = GlobalSearchScope.fast,
    List<Novel> localNovels = const [],
    bool bypassCache = false,
  }) async {
    final cleanQuery = normalizeQueryForDispatch(query);
    if (cleanQuery.isEmpty) {
      clear();
      return;
    }

    final cacheKey = '${scope.name}:${cleanQuery.toLowerCase()}';
    if (!bypassCache && targetSources == null) {
      final cached = _queryCache[cacheKey];
      if (cached != null && DateTime.now().difference(cached.cachedAt) < _cacheTtl) {
        _currentGenerationId++;
        value = cached.state;
        return;
      }
    }

    final generationId = ++_currentGenerationId;
    final allSources = targetSources != null
        ? List<NovelSource>.from(targetSources)
        : selectSourcesForScope(SourceRegistry.getAllSources(), scope, cleanQuery);

    final List<SourceSearchResult> resultsAccumulator = [];
    final List<Novel> novelsAccumulator = [];
    final Map<String, GroupedNovelMatch> groupedMap = {};

    // Instant t = 0ms local matches (Library + cached Browse novels)
    if (localNovels.isNotEmpty) {
      final seenLocalIds = <String>{};
      final localHits = <Novel>[];
      for (final novel in localNovels) {
        if (seenLocalIds.contains(novel.id)) continue;
        if (computeNovelRelevance(novel.title, novel.author, cleanQuery) > 0) {
          seenLocalIds.add(novel.id);
          localHits.add(novel);
        }
      }
      if (localHits.isNotEmpty) {
        final sourcesById = {for (final s in SourceRegistry.getAllSources()) s.id: s};
        for (final novel in localHits) {
          novelsAccumulator.add(novel);
          final src = sourcesById[novel.sourceId];
          if (src != null) {
            _mergeNovelIntoGroup(groupedMap, novel, src, cleanQuery);
          }
        }
      }
    }

    final initialGrouped = _sortMatches(groupedMap.values, cleanQuery);

    // Initial state: searching started (with instant local matches if any)
    value = GlobalSearchState(
      query: cleanQuery,
      scope: scope,
      isSearching: allSources.isNotEmpty,
      totalSources: allSources.length,
      completedSources: 0,
      sourceResults: [],
      groupedMatches: List.unmodifiable(initialGrouped),
      allNovelsRaw: List.unmodifiable(novelsAccumulator),
    );

    if (allSources.isEmpty) return;

    DateTime lastEmission = DateTime.now();

    void maybeEmitUpdate(bool force) {
      if (_currentGenerationId != generationId) return;
      final now = DateTime.now();
      if (force || now.difference(lastEmission).inMilliseconds > 180 || resultsAccumulator.length == 1) {
        lastEmission = now;
        final isAllDone = resultsAccumulator.length >= allSources.length;
        final sortedMatches = _sortMatches(groupedMap.values, cleanQuery);

        value = value.copyWith(
          completedSources: resultsAccumulator.length,
          isSearching: !isAllDone,
          sourceResults: List.unmodifiable(resultsAccumulator),
          allNovelsRaw: List.unmodifiable(novelsAccumulator),
          groupedMatches: List.unmodifiable(sortedMatches),
        );
      }
    }

    int nextSourceIndex = 0;
    final int maxConcurrent = kIsWeb ? 6 : 12;

    Future<void> runWorker() async {
      while (true) {
        if (_currentGenerationId != generationId) return;
        NovelSource source;
        if (nextSourceIndex < allSources.length) {
          source = allSources[nextSourceIndex++];
        } else {
          return;
        }

        final health = _sourceHealth.putIfAbsent(source.id, () => SourceHealthStats());
        final now = DateTime.now();

        // Circuit breaker: skip repeatedly failing sources during cooldown
        if (targetSources == null && health.isCircuitOpen(now)) {
          resultsAccumulator.add(SourceSearchResult(
            source: source,
            novels: const [],
            isSuccess: false,
            errorMessage: 'Skipped (temporarily unavailable)',
            elapsed: Duration.zero,
            status: SearchOutcomeStatus.skippedCircuitBreaker,
          ));
          maybeEmitUpdate(false);
          continue;
        }

        final stopwatch = Stopwatch()..start();
        List<Novel> sourceNovels = [];
        bool isSuccess = false;
        String? errorMessage;
        SearchOutcomeStatus status = SearchOutcomeStatus.ok;

        try {
          sourceNovels = await source.search(cleanQuery).timeout(sourceTimeout);
          isSuccess = true;
          status = sourceNovels.isEmpty ? SearchOutcomeStatus.empty : SearchOutcomeStatus.ok;
          health.recordSuccess(stopwatch.elapsed);
        } on TimeoutException {
          status = SearchOutcomeStatus.timedOut;
          errorMessage = 'Timed out after ${sourceTimeout.inSeconds}s';
          health.recordFailure(errorMessage, DateTime.now());
        } catch (e) {
          final msg = e.toString().replaceAll('Exception:', '').trim();
          status = (msg.contains('403') || msg.toLowerCase().contains('cloudflare'))
              ? SearchOutcomeStatus.blocked
              : SearchOutcomeStatus.error;
          errorMessage = msg;
          health.recordFailure(msg, DateTime.now());
        } finally {
          stopwatch.stop();
        }

        if (_currentGenerationId != generationId) return;

        resultsAccumulator.add(SourceSearchResult(
          source: source,
          novels: sourceNovels,
          isSuccess: isSuccess,
          errorMessage: errorMessage,
          elapsed: stopwatch.elapsed,
          status: status,
        ));

        sourceNovels.sort((a, b) => computeNovelRelevance(b.title, b.author, cleanQuery)
            .compareTo(computeNovelRelevance(a.title, a.author, cleanQuery)));

        for (final novel in sourceNovels) {
          novelsAccumulator.add(novel);
          _mergeNovelIntoGroup(groupedMap, novel, source, cleanQuery);
        }

        maybeEmitUpdate(false);
      }
    }

    await runZoned(() async {
      final workerFutures = <Future<void>>[];
      final activeWorkers = allSources.length < maxConcurrent ? allSources.length : maxConcurrent;
      for (int i = 0; i < activeWorkers; i++) {
        workerFutures.add(runWorker());
      }
      await Future.wait(workerFutures);
    }, zoneValues: {#skipWebViewFallback: true});

    if (_currentGenerationId == generationId) {
      final sortedMatches = _sortMatches(groupedMap.values, cleanQuery);

      final finalState = value.copyWith(
        isSearching: false,
        completedSources: allSources.length,
        sourceResults: List.unmodifiable(resultsAccumulator),
        allNovelsRaw: List.unmodifiable(novelsAccumulator),
        groupedMatches: List.unmodifiable(sortedMatches),
      );
      value = finalState;

      final hasHealthyResult = resultsAccumulator.any((r) => r.isSuccess);
      if (targetSources == null && hasHealthyResult) {
        if (_queryCache.length >= _maxCacheEntries) {
          _queryCache.remove(_queryCache.keys.first);
        }
        _queryCache[cacheKey] = _CachedSearchEntry(finalState, DateTime.now());
      }
    }
  }

  /// Retries all failed or circuit-skipped sources from the current search.
  Future<void> retryFailedSources() async {
    final current = value;
    if (current.query.isEmpty || current.isSearching) return;
    final failedSources = current.sourceResults
        .where((r) =>
            r.status == SearchOutcomeStatus.timedOut ||
            r.status == SearchOutcomeStatus.blocked ||
            r.status == SearchOutcomeStatus.error ||
            r.status == SearchOutcomeStatus.skippedCircuitBreaker)
        .map((r) => r.source)
        .toList();
    if (failedSources.isEmpty) return;

    for (final s in failedSources) {
      _sourceHealth.remove(s.id);
    }
    await search(
      current.query,
      targetSources: failedSources,
      scope: current.scope,
      bypassCache: true,
    );
  }

  static void _mergeNovelIntoGroup(
    Map<String, GroupedNovelMatch> groupedMap,
    Novel novel,
    NovelSource source,
    String cleanQuery,
  ) {
    final normalizedKey = normalizeTitle(novel.title);
    if (groupedMap.containsKey(normalizedKey)) {
      final existing = groupedMap[normalizedKey]!;
      existing.sourceVariants[source] = novel;

      if (novel.title.toLowerCase().trim() == cleanQuery.toLowerCase().trim() ||
          (novel.title.length < existing.canonicalTitle.length &&
              novel.title.toLowerCase().contains(cleanQuery.toLowerCase()))) {
        existing.canonicalTitle = novel.title;
      }

      if ((existing.author == 'Unknown Author' || existing.author.isEmpty) &&
          novel.author.isNotEmpty &&
          novel.author != 'Unknown Author') {
        existing.author = novel.author;
      }

      if (novel.coverUrl.isNotEmpty &&
          (existing.coverUrl.isEmpty ||
              existing.coverUrl.contains('400') ||
              existing.coverUrl.contains('placeholder') ||
              existing.coverUrl.contains('blank'))) {
        existing.coverUrl = novel.coverUrl;
      }
    } else {
      groupedMap[normalizedKey] = GroupedNovelMatch(
        canonicalTitle: novel.title,
        author: novel.author.isNotEmpty ? novel.author : 'Unknown Author',
        coverUrl: novel.coverUrl,
        sourceVariants: {source: novel},
      );
    }
  }

  static const Map<String, String> _acronymExpansions = {
    'lotm': 'lord of the mysteries',
    'orv': 'omniscient reader s viewpoint',
    'tbate': 'the beginning after the end',
    'ri': 'reverend insanity',
    'rotssg': 'reincarnation of the strongest sword god',
    'cote': 'classroom of the elite',
  };

  static const Set<String> _stopwords = {'the', 'of', 'a', 'an', 'and', 'in', 'to', 'for'};

  /// Normalizes smart quotes and whitespace before dispatching query to extractors.
  static String normalizeQueryForDispatch(String query) {
    return query
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Precomputes relevance scores once per match so List.sort() runs in O(N log N) without regexes.
  static List<GroupedNovelMatch> _sortMatches(
    Iterable<GroupedNovelMatch> matches,
    String query,
  ) {
    final list = matches.toList();
    if (list.length <= 1) return list;
    final scores = <GroupedNovelMatch, int>{
      for (final m in list) m: computeRelevanceScore(m, query),
    };
    list.sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return list;
  }

  static double _bigramSimilarity(String a, String b) {
    if (a.length < 2 || b.length < 2) return 0.0;
    final aBigrams = <String>{for (int i = 0; i < a.length - 1; i++) a.substring(i, i + 2)};
    final bBigrams = <String>{for (int i = 0; i < b.length - 1; i++) b.substring(i, i + 2)};
    final intersection = aBigrams.intersection(bBigrams).length;
    return (2.0 * intersection) / (aBigrams.length + bBigrams.length);
  }

  /// Calculates a ranking score for a grouped novel match against the user query.
  static int computeRelevanceScore(GroupedNovelMatch match, String query) {
    var normQuery = normalizeTitle(query);
    normQuery = _acronymExpansions[normQuery] ?? normQuery;
    final normTitle = normalizeTitle(match.canonicalTitle);

    if (normQuery.isEmpty) return 0;

    int score = 0;

    if (normTitle == normQuery) {
      score += 20000;
    } else if (normTitle.startsWith('$normQuery ') || normTitle.startsWith('$normQuery:')) {
      score += 10000;
    } else if (normTitle.startsWith(normQuery)) {
      score += 7000;
    } else if (RegExp('\\b${RegExp.escape(normQuery)}\\b', caseSensitive: false).hasMatch(normTitle)) {
      score += 4000;
    } else if (normTitle.contains(normQuery)) {
      score += 2000;
    } else {
      final qTokens = normQuery.split(' ').where((s) => s.isNotEmpty && !_stopwords.contains(s)).toSet();
      final tTokens = normTitle.split(' ').where((s) => s.isNotEmpty && !_stopwords.contains(s)).toSet();
      final overlap = qTokens.intersection(tTokens).length;
      if (overlap > 0) {
        score += overlap * 400;
        if (qTokens.isNotEmpty && overlap == qTokens.length) {
          score += 1500;
        }
      } else {
        final sim = _bigramSimilarity(normQuery, normTitle);
        if (sim >= 0.55) {
          score += (sim * 1800).round();
        }
      }
    }

    final lowerTitle = match.canonicalTitle.toLowerCase();
    if (lowerTitle.contains('adaptation') ||
        lowerTitle.contains('fanfic') ||
        lowerTitle.contains('fan-fic') ||
        lowerTitle.contains('spin-off') ||
        lowerTitle.contains('tribute') ||
        lowerTitle.contains('journey to') ||
        lowerTitle.contains('inspired by') ||
        lowerTitle.contains('remake')) {
      score -= 5000;
    }

    score += match.sourceCount * 500;

    final lenDiff = (normTitle.length - normQuery.length).abs();
    score -= (lenDiff * 8).clamp(0, 1500);

    if (match.author.isNotEmpty && match.author != 'Unknown Author') {
      score += 100;
      if (normalizeTitle(match.author).contains(normQuery)) {
        score += 3000;
      }
    }

    if (match.coverUrl.isNotEmpty && !match.coverUrl.contains('placeholder') && !match.coverUrl.contains('400')) {
      score += 200;
    }

    return score;
  }

  /// Calculates relevance for individual novels inside a source.
  static int computeNovelRelevance(String title, String author, String query) {
    var normQuery = normalizeTitle(query);
    normQuery = _acronymExpansions[normQuery] ?? normQuery;
    final normTitle = normalizeTitle(title);
    final normAuthor = normalizeTitle(author);

    if (normQuery.isEmpty) return 0;
    if (normTitle == normQuery) return 10000;
    if (normTitle.startsWith('$normQuery ')) return 5000;
    if (normTitle.contains(normQuery)) return 2000;

    if (normAuthor.isNotEmpty) {
      if (normAuthor == normQuery) return 3000;
      if (normAuthor.contains(normQuery)) return 1500;
    }

    final qTokens = normQuery.split(' ').where((s) => s.isNotEmpty && !_stopwords.contains(s)).toSet();
    final tTokens = normTitle.split(' ').where((s) => s.isNotEmpty && !_stopwords.contains(s)).toSet();
    final overlap = qTokens.intersection(tTokens).length;
    if (overlap > 0) {
      return (overlap * 300 - (normTitle.length - normQuery.length).abs()).clamp(10, 2000);
    }

    final sim = _bigramSimilarity(normQuery, normTitle);
    if (sim >= 0.55) {
      return (sim * 1200).round();
    }
    return 0;
  }

  /// Normalizes novel title to group identical works across different CMS sources.
  static String normalizeTitle(String title) {
    var clean = title.toLowerCase().trim();
    clean = clean.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'\s*(?:web novel|light novel|novel|mtl)\s*$', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : title.toLowerCase().trim();
  }

  /// Cancels in-flight searches and clears results.
  void clear() {
    _currentGenerationId++;
    value = const GlobalSearchState();
  }

  /// Stops an active search while keeping already-collected results visible.
  void stopSearch() {
    if (!value.isSearching) return;
    _currentGenerationId++;
    value = value.copyWith(isSearching: false);
  }
}
