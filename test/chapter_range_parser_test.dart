import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/utils/chapter_range_parser.dart';

void main() {
  group('ChapterRangeParser - Syntax Parsing', () {
    test('parses single range: 1-40', () {
      final res = ChapterRangeParser.parseRange('1-40');
      expect(res.length, 40);
      expect(res.contains(1), isTrue);
      expect(res.contains(40), isTrue);
      expect(res.contains(41), isFalse);
    });

    test('parses multiple ranges: 1-30,40-50', () {
      final res = ChapterRangeParser.parseRange('1-30,40-50');
      expect(res.length, 41); // 30 + 11 = 41
      expect(res.contains(1), isTrue);
      expect(res.contains(30), isTrue);
      expect(res.contains(35), isFalse);
      expect(res.contains(40), isTrue);
      expect(res.contains(50), isTrue);
    });

    test('parses discrete list: 1,2', () {
      final res = ChapterRangeParser.parseRange('1,2');
      expect(res, {1, 2});
    });

    test('parses single chapter: 30', () {
      final res = ChapterRangeParser.parseRange('30');
      expect(res, {30});
    });

    test('handles whitespace and various formats gracefully', () {
      final res = ChapterRangeParser.parseRange(' 1 - 5 ,  10 to 12 ,  20 .. 22 , 30 ');
      expect(res, {1, 2, 3, 4, 5, 10, 11, 12, 20, 21, 22, 30});
    });

    test('handles reversed range: 10-5', () {
      final res = ChapterRangeParser.parseRange('10-5');
      expect(res, {5, 6, 7, 8, 9, 10});
    });

    test('handles overlapping ranges: 1-5, 3-7', () {
      final res = ChapterRangeParser.parseRange('1-5, 3-7');
      expect(res, {1, 2, 3, 4, 5, 6, 7});
    });

    test('formats range description accurately', () {
      expect(ChapterRangeParser.formatRangeDescription({1, 2, 3, 4, 5}), '1–5');
      expect(
        ChapterRangeParser.formatRangeDescription(
          ChapterRangeParser.parseRange('1-30,40-50'),
        ),
        '1–30, 40–50',
      );
      expect(ChapterRangeParser.formatRangeDescription({1, 2}), '1, 2');
      expect(ChapterRangeParser.formatRangeDescription({30}), '30');
    });
  });

  group('ChapterRangeParser - Filtering Chapters', () {
    final List<Chapter> mockChapters = List.generate(
      100,
      (i) => Chapter(
        id: 'ch_${i + 1}',
        novelId: 'test_novel',
        title: 'Chapter ${i + 1}: The Adventure',
        chapterNumber: (i + 1).toDouble(),
        url: 'https://example.com/ch_${i + 1}',
      ),
    );

    test('filters 1-40 correctly', () {
      final requested = ChapterRangeParser.parseRange('1-40');
      final filtered = ChapterRangeParser.filterChapters(mockChapters, requested);
      expect(filtered.length, 40);
      expect(filtered.first.id, 'ch_1');
      expect(filtered.last.id, 'ch_40');
    });

    test('filters 1-30,40-50 correctly', () {
      final requested = ChapterRangeParser.parseRange('1-30,40-50');
      final filtered = ChapterRangeParser.filterChapters(mockChapters, requested);
      expect(filtered.length, 41);
      expect(filtered.first.id, 'ch_1');
      expect(filtered[29].id, 'ch_30');
      expect(filtered[30].id, 'ch_40');
      expect(filtered.last.id, 'ch_50');
    });

    test('filters 1,2 correctly', () {
      final requested = ChapterRangeParser.parseRange('1,2');
      final filtered = ChapterRangeParser.filterChapters(mockChapters, requested);
      expect(filtered.length, 2);
      expect(filtered.map((c) => c.id).toList(), ['ch_1', 'ch_2']);
    });

    test('filters 30 correctly', () {
      final requested = ChapterRangeParser.parseRange('30');
      final filtered = ChapterRangeParser.filterChapters(mockChapters, requested);
      expect(filtered.length, 1);
      expect(filtered.first.id, 'ch_30');
    });

    test('gracefully ignores out-of-bounds chapter numbers without crash', () {
      final requested = ChapterRangeParser.parseRange('95-150');
      final filtered = ChapterRangeParser.filterChapters(mockChapters, requested);
      expect(filtered.length, 6); // 95 to 100
      expect(filtered.first.id, 'ch_95');
      expect(filtered.last.id, 'ch_100');
    });
  });
}
