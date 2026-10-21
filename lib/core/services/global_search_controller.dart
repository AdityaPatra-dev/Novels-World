import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/novel.dart';
import '../../extractors/novel_source.dart';
import '../../extractors/source_registry.dart';

/// Result emitted by a single source during a global search session.
class SourceSearchResult {
  final NovelSource source;
  final List<Novel> novels;
  final bool isSuccess;
  final String? errorMessage;
  final Duration elapsed;

  const SourceSearchResult({
    required this.source,
    required this.novels,
    required this.isSuccess,
    this.errorMessage,
    required this.elapsed,
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

  /// The primary novel variant (preferred source, or first found)
  Novel get primaryNovel => sourceVariants.values.first;

  /// List of sources where this novel was found
  List<NovelSource> get sources => sourceVariants.keys.toList();

  /// Total number of sources offering this novel
  int get sourceCount => sourceVariants.length;
}

/// Immutable state snapshot of the active global search session.
class GlobalSearchState {
  final String query;
  final bool isSearching;
  final int totalSources;
  final int completedSources;
  final List<SourceSearchResult> sourceResults;
  final List<GroupedNovelMatch> groupedMatches;
  final List<Novel> allNovelsRaw;

  const GlobalSearchState({
    this.query = '',
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

  GlobalSearchState copyWith({
    String? query,
    bool? isSearching,
    int? totalSources,
    int? completedSources,
    List<SourceSearchResult>? sourceResults,
    List<GroupedNovelMatch>? groupedMatches,
    List<Novel>? allNovelsRaw,
  }) {
    return GlobalSearchState(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      totalSources: totalSources ?? this.totalSources,
      completedSources: completedSources ?? this.completedSources,
      sourceResults: sourceResults ?? this.sourceResults,
      groupedMatches: groupedMatches ?? this.groupedMatches,
      allNovelsRaw: allNovelsRaw ?? this.allNovelsRaw,
    );
  }
}

/// Central controller orchestrating parallel multi-source global searches.
/// Fully fault-tolerant: individual source timeouts or errors never stall other sources.
class GlobalSearchController extends ValueNotifier<GlobalSearchState> {
  GlobalSearchController() : super(const GlobalSearchState());

  int _currentGenerationId = 0;
  static const Duration sourceTimeout = Duration(seconds: 8);

  /// Executes global search across all cataloged sources in parallel.
  /// Results stream incrementally into [value] in real time.
  Future<void> search(String query, {List<NovelSource>? targetSources}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      clear();
      return;
    }

    final generationId = ++_currentGenerationId;
    final sources = targetSources ?? SourceRegistry.getAllSources();

    // Initial state: searching started
    value = GlobalSearchState(
      query: cleanQuery,
      isSearching: true,
      totalSources: sources.length,
      completedSources: 0,
      sourceResults: [],
      groupedMatches: [],
      allNovelsRaw: [],
    );

    final List<SourceSearchResult> resultsAccumulator = [];
    final List<Novel> novelsAccumulator = [];
    final Map<String, GroupedNovelMatch> groupedMap = {};

    // Concurrently trigger each source search worker
    final List<Future<void>> workerFutures = sources.map((source) async {
      final stopwatch = Stopwatch()..start();
      List<Novel> sourceNovels = [];
      bool isSuccess = false;
      String? errorMessage;

      try {
        sourceNovels = await source.search(cleanQuery).timeout(sourceTimeout);
        isSuccess = true;
      } on TimeoutException {
        errorMessage = 'Source search timed out after ${sourceTimeout.inSeconds}s';
      } catch (e) {
        errorMessage = e.toString().replaceAll('Exception:', '').trim();
      } finally {
        stopwatch.stop();
      }

      // Check if user entered a newer query while this source was fetching
      if (_currentGenerationId != generationId) return;

      final result = SourceSearchResult(
        source: source,
        novels: sourceNovels,
        isSuccess: isSuccess,
        errorMessage: errorMessage,
        elapsed: stopwatch.elapsed,
      );

      // Mutate local accumulators safely
      resultsAccumulator.add(result);

      // Sort novels within this source by relevance to query
      sourceNovels.sort((a, b) => computeNovelRelevance(b.title, b.author, cleanQuery).compareTo(computeNovelRelevance(a.title, a.author, cleanQuery)));

      for (final novel in sourceNovels) {
        novelsAccumulator.add(novel);

        // Normalize title for clustering
        final normalizedKey = normalizeTitle(novel.title);
        if (groupedMap.containsKey(normalizedKey)) {
          final existing = groupedMap[normalizedKey]!;
          existing.sourceVariants[source] = novel;

          // Prefer exact title over long subtitle/fanfiction variants
          if (novel.title.toLowerCase().trim() == cleanQuery.toLowerCase().trim() ||
              (novel.title.length < existing.canonicalTitle.length &&
                  novel.title.toLowerCase().contains(cleanQuery.toLowerCase()))) {
            existing.canonicalTitle = novel.title;
          }

          // Prefer real author over 'Unknown Author'
          if ((existing.author == 'Unknown Author' || existing.author.isEmpty) &&
              novel.author.isNotEmpty &&
              novel.author != 'Unknown Author') {
            existing.author = novel.author;
          }

          // Prefer real cover over placeholder
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

      final isAllDone = resultsAccumulator.length >= sources.length;

      // Sort grouped matches by relevance score (exact match and multi-source novels at the top)
      final sortedMatches = groupedMap.values.toList()
        ..sort((a, b) => computeRelevanceScore(b, cleanQuery).compareTo(computeRelevanceScore(a, cleanQuery)));

      // Incrementally emit state to UI listeners
      value = value.copyWith(
        completedSources: resultsAccumulator.length,
        isSearching: !isAllDone,
        sourceResults: List.unmodifiable(resultsAccumulator),
        allNovelsRaw: List.unmodifiable(novelsAccumulator),
        groupedMatches: List.unmodifiable(sortedMatches),
      );
    }).toList();

    // Wait for all workers to settle
    await Future.wait(workerFutures);

    if (_currentGenerationId == generationId) {
      final sortedMatches = groupedMap.values.toList()
        ..sort((a, b) => computeRelevanceScore(b, cleanQuery).compareTo(computeRelevanceScore(a, cleanQuery)));

      value = value.copyWith(
        isSearching: false,
        completedSources: sources.length,
        groupedMatches: List.unmodifiable(sortedMatches),
      );
    }
  }

  /// Calculates a ranking score for a grouped novel match against the user query.
  /// 1. Exact match gets highest score (20,000 pts).
  /// 2. Multi-source availability gives heavy boost (+500 pts per source) as canonical novels are on multiple aggregators.
  /// 3. Fanfiction, adaptation, or spin-off keywords are demoted (-5,000 pts).
  /// 4. Length difference penalty keeps clean, canonical titles ranked above bloated titles.
  static int computeRelevanceScore(GroupedNovelMatch match, String query) {
    final normQuery = normalizeTitle(query);
    final normTitle = normalizeTitle(match.canonicalTitle);

    if (normQuery.isEmpty) return 0;

    int score = 0;

    // 1. Exact match tier (Highest possible)
    if (normTitle == normQuery) {
      score += 20000;
    } 
    // 2. Starts with query as a full word prefix
    else if (normTitle.startsWith('$normQuery ') || normTitle.startsWith('$normQuery:')) {
      score += 10000;
    }
    // 3. Starts with query
    else if (normTitle.startsWith(normQuery)) {
      score += 7000;
    }
    // 4. Exact word match boundary within title (e.g. "Shadow Slave")
    else if (RegExp('\\b${RegExp.escape(normQuery)}\\b', caseSensitive: false).hasMatch(normTitle)) {
      score += 4000;
    }
    // 5. Contains query substring
    else if (normTitle.contains(normQuery)) {
      score += 2000;
    }
    // 6. Token overlap
    else {
      final qTokens = normQuery.split(' ').where((s) => s.isNotEmpty).toSet();
      final tTokens = normTitle.split(' ').where((s) => s.isNotEmpty).toSet();
      final overlap = qTokens.intersection(tTokens).length;
      score += overlap * 400;
    }

    // Heavy penalty for fanfictions, adaptations, and spin-offs when searching for canon titles
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

    // Heavy multi-source availability boost:
    // Real, popular novels exist across 2, 3, 5, 8+ aggregators (NovelFire, ReadNovelFull, WuxiaBox, NovelFull, etc.)
    // Fanfics typically only exist on 1 source (e.g. Royal Road).
    score += match.sourceCount * 500;

    // Length difference penalty:
    // "Shadow Slave" (12 chars) is much more relevant than a 60-character fan-fiction title
    final lenDiff = (normTitle.length - normQuery.length).abs();
    score -= (lenDiff * 8).clamp(0, 1500);

    // Valid author boost
    if (match.author.isNotEmpty && match.author != 'Unknown Author') {
      score += 100;
      if (normalizeTitle(match.author).contains(normQuery)) {
        score += 3000;
      }
    }

    // Cover image presence boost
    if (match.coverUrl.isNotEmpty && !match.coverUrl.contains('placeholder') && !match.coverUrl.contains('400')) {
      score += 200;
    }

    return score;
  }

  /// Calculates relevance for individual novels inside a source.
  static int computeNovelRelevance(String title, String author, String query) {
    final normQuery = normalizeTitle(query);
    final normTitle = normalizeTitle(title);
    final normAuthor = normalizeTitle(author);

    if (normQuery.isEmpty) return 0;
    if (normTitle == normQuery) return 10000;
    if (normTitle.startsWith('$normQuery ')) return 5000;
    if (normTitle.contains(normQuery)) return 2000;

    // Author match support
    if (normAuthor.isNotEmpty) {
      if (normAuthor == normQuery) return 3000;
      if (normAuthor.contains(normQuery)) return 1500;
    }

    final qTokens = normQuery.split(' ').where((s) => s.isNotEmpty).toSet();
    final tTokens = normTitle.split(' ').where((s) => s.isNotEmpty).toSet();
    final overlap = qTokens.intersection(tTokens).length;
    if (overlap > 0) {
      return (overlap * 300 - (normTitle.length - normQuery.length).abs()).clamp(10, 2000);
    }
    return 0;
  }

  /// Normalizes novel title to group identical works across different CMS sources.
  /// Handles variants like "Shadow Slave", "Shadow Slave (Web Novel)", "Shadow Slave [LN]"
  static String normalizeTitle(String title) {
    var clean = title.toLowerCase().trim();
    // Remove parenthesized notes: (Web Novel), [WN], (Light Novel), (LN), etc.
    clean = clean.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ');
    // Remove common CMS suffixes
    clean = clean.replaceAll(RegExp(r'\s*(?:web novel|light novel|novel|mtl)\s*$', caseSensitive: false), ' ');
    // Strip non-alphanumeric characters for fuzzy key matching
    clean = clean.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    // Collapse whitespace
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : title.toLowerCase().trim();
  }

  /// Cancels in-flight searches and clears results.
  void clear() {
    _currentGenerationId++;
    value = const GlobalSearchState();
  }
}

