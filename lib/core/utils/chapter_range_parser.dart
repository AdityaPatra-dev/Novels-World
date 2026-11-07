import '../models/chapter.dart';

/// Helper utility to parse flexible chapter expressions like:
/// - "1-40"        -> chapters 1 through 40
/// - "1-30,40-50"  -> chapters 1 through 30 and 40 through 50
/// - "1,2"         -> chapters 1 and 2
/// - "30"          -> chapter 30
class ChapterRangeParser {
  /// Parses a comma-separated range string into a sorted set of requested integer chapter numbers.
  static Set<int> parseRange(String input) {
    final Set<int> result = {};
    if (input.trim().isEmpty) return result;

    // Split on commas
    final segments = input.split(',');
    for (final rawSegment in segments) {
      final seg = rawSegment.trim();
      if (seg.isEmpty) continue;

      // Check for range patterns: "1-40", "1 - 40", "1..40", "1 to 40"
      final rangeMatch = RegExp(r'^(\d+)\s*(?:-|to|\.\.)\s*(\d+)$', caseSensitive: false).firstMatch(seg);
      if (rangeMatch != null) {
        final start = int.tryParse(rangeMatch.group(1)!);
        final end = int.tryParse(rangeMatch.group(2)!);
        if (start != null && end != null) {
          final low = start < end ? start : end;
          final high = start > end ? start : end;
          for (int i = low; i <= high; i++) {
            result.add(i);
          }
          continue;
        }
      }

      // Check for single number: "30"
      final singleMatch = RegExp(r'^(\d+)$').firstMatch(seg);
      if (singleMatch != null) {
        final num = int.tryParse(singleMatch.group(1)!);
        if (num != null) {
          result.add(num);
        }
      }
    }

    return result;
  }

  /// Calculates the effective logical chapter number for a chapter in a list.
  /// 1) Uses chapterNumber if specified
  /// 2) Or parses number from title (e.g. "Chapter 40" -> 40)
  /// 3) Or falls back to 1-based list index (index + 1)
  static int getEffectiveChapterNumber(Chapter chapter, int indexInList) {
    if (chapter.chapterNumber != null) {
      return chapter.chapterNumber!.round();
    }
    final titleMatch = RegExp(
      r'(?:chapter|ch\.?|ep\.?)\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(chapter.title);
    if (titleMatch != null) {
      final val = int.tryParse(titleMatch.group(1)!);
      if (val != null) return val;
    }
    final leadingNum = RegExp(r'^(\d+)[\s.:\-_]').firstMatch(chapter.title.trim());
    if (leadingNum != null) {
      final val = int.tryParse(leadingNum.group(1)!);
      if (val != null) return val;
    }
    return indexInList + 1;
  }

  /// Filters [allChapters] to only those matching [requestedNumbers].
  static List<Chapter> filterChapters(
    List<Chapter> allChapters,
    Set<int> requestedNumbers,
  ) {
    if (requestedNumbers.isEmpty || allChapters.isEmpty) return [];

    final List<Chapter> matches = [];
    final Set<String> addedIds = {};

    for (int i = 0; i < allChapters.length; i++) {
      final ch = allChapters[i];
      final effNum = getEffectiveChapterNumber(ch, i);

      if (requestedNumbers.contains(effNum)) {
        if (addedIds.add(ch.id)) {
          matches.add(ch);
        }
      }
    }

    // Fallback: If no chapters matched by chapter number, match by 1-based position
    if (matches.isEmpty) {
      for (int i = 0; i < allChapters.length; i++) {
        final oneBasedIndex = i + 1;
        if (requestedNumbers.contains(oneBasedIndex)) {
          if (addedIds.add(allChapters[i].id)) {
            matches.add(allChapters[i]);
          }
        }
      }
    }

    return matches;
  }

  /// Formats a set of integer chapter numbers into a readable range description,
  /// e.g. "1–30, 40–50" or "1, 2" or "30".
  static String formatRangeDescription(Set<int> numbers) {
    if (numbers.isEmpty) return 'None';
    final sorted = numbers.toList()..sort();

    final List<String> parts = [];
    int? rangeStart;
    int? prev;

    for (final n in sorted) {
      if (rangeStart == null) {
        rangeStart = n;
        prev = n;
      } else if (n == prev! + 1) {
        prev = n;
      } else {
        if (rangeStart == prev) {
          parts.add('$rangeStart');
        } else if (prev - rangeStart == 1) {
          parts.add('$rangeStart, $prev');
        } else {
          parts.add('$rangeStart–$prev');
        }
        rangeStart = n;
        prev = n;
      }
    }

    if (rangeStart != null && prev != null) {
      if (rangeStart == prev) {
        parts.add('$rangeStart');
      } else if (prev - rangeStart == 1) {
        parts.add('$rangeStart, $prev');
      } else {
        parts.add('$rangeStart–$prev');
      }
    }

    return parts.join(', ');
  }
}
