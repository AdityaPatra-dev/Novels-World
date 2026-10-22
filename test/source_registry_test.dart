import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';

void main() {
  group('SourceRegistry Sorting & Ordering Verification', () {
    test('Contains 15+ verified full-stack active sources', () {
      final allSources = SourceRegistry.getAllSources();
      expect(allSources.length, greaterThanOrEqualTo(15));
    });

    test('English sources are strictly placed at the top before any other language', () {
      final allSources = SourceRegistry.getAllSources();
      bool foundNonEnglish = false;

      for (final s in allSources) {
        final isEn = s.lang.toLowerCase() == 'en';
        if (foundNonEnglish) {
          // Once a non-English source has appeared, NO English source should ever appear after it!
          expect(isEn, isFalse,
              reason: 'Found English source ${s.name} (${s.id}) after a non-English source in sorted list.');
        } else if (!isEn) {
          foundNonEnglish = true;
        }
      }
    });

    test('Within English, sources with more novels are placed first (descending count)', () {
      final allSources = SourceRegistry.getAllSources();
      final enSources = allSources.where((s) => s.lang.toLowerCase() == 'en').toList();

      for (int i = 0; i < enSources.length - 1; i++) {
        final curr = enSources[i];
        final next = enSources[i + 1];
        expect(
          curr.estimatedNovelCount,
          greaterThanOrEqualTo(next.estimatedNovelCount),
          reason: '${curr.name} (${curr.estimatedNovelCount}) should come before or equal to ${next.name} (${next.estimatedNovelCount})',
        );
      }
    });

    test('Within same non-English language, sources with more novels are placed first', () {
      final allSources = SourceRegistry.getAllSources();
      final nonEnSources = allSources.where((s) => s.lang.toLowerCase() != 'en').toList();

      for (int i = 0; i < nonEnSources.length - 1; i++) {
        final curr = nonEnSources[i];
        final next = nonEnSources[i + 1];
        if (curr.lang == next.lang) {
          expect(
            curr.estimatedNovelCount,
            greaterThanOrEqualTo(next.estimatedNovelCount),
            reason: '${curr.name} in ${curr.lang} should have >= count than ${next.name}',
          );
        }
      }
    });

    test('Default source is valid and available', () {
      final def = SourceRegistry.getDefaultSource();
      expect(def, isNotNull);
      expect(def.baseUrl, isNotEmpty);
    });
  });
}

