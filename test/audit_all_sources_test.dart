import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';

class AuditRecord {
  final String sourceId;
  final String name;
  final String lang;
  final String type;
  bool catalogOk = false;
  int catalogCount = 0;
  String? sampleTitle;
  String? sampleAuthor;
  String? sampleCover;
  bool coverValid = false;
  bool chaptersOk = false;
  int chaptersCount = 0;
  bool contentOk = false;
  int paragraphCount = 0;
  int charCount = 0;
  String firstParagraphSnippet = '';
  List<String> flaws = [];

  AuditRecord({
    required this.sourceId,
    required this.name,
    required this.lang,
    required this.type,
  });
}

bool isBookSource(String id) {
  const bookSources = {
    'gutenberg',
    'openlibrary',
    'internet_archive',
    'libgen',
    'standard_ebooks',
    'oceanofpdf',
    'vdocpub',
    'fadedpage',
    'epustakalay',
    'odiabibhaba',
    'local_epub',
  };
  return bookSources.contains(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Detailed Audit Across All Registered Sources', () async {
    HttpOverrides.global = null;

    final allSources = SourceRegistry.getAllSources();

    print('========================================================================');
    print('🚀 AUDITING ALL ${allSources.length} SOURCES IN CATALOG');
    print('========================================================================\n');

    final records = <AuditRecord>[];

    for (int i = 0; i < allSources.length; i++) {
      final s = allSources[i];
      final isBook = isBookSource(s.id);
      final record = AuditRecord(
        sourceId: s.id,
        name: s.name,
        lang: s.lang,
        type: isBook ? 'Book/PDF' : 'WebNovel',
      );

      print('\n[${i + 1}/${allSources.length}] Testing [${s.id}] "${s.name}" (${s.lang})...');

      List<Novel> catalog = [];
      try {
        catalog = await s.getPopular(page: 1).timeout(const Duration(seconds: 12));
        if (catalog.isEmpty) {
          catalog = await s.getLatest(page: 1).timeout(const Duration(seconds: 12));
        }
      } catch (e) {
        record.flaws.add('Catalog fetch failed: $e');
      }

      if (catalog.isNotEmpty) {
        record.catalogOk = true;
        record.catalogCount = catalog.length;
        final sample = catalog.first;

        try {
          final details = await s.getNovelDetails(sample.sourceUrl).timeout(const Duration(seconds: 12));
          record.sampleTitle = details.title;
          record.sampleAuthor = details.author;
          record.sampleCover = details.coverUrl;

          if (details.coverUrl.isNotEmpty &&
              (details.coverUrl.startsWith('http://') || details.coverUrl.startsWith('https://'))) {
            record.coverValid = true;
          } else {
            record.flaws.add('Invalid cover URL: "${details.coverUrl}"');
          }

          if (details.title.isEmpty ||
              details.title.toLowerCase() == 'untitled' ||
              details.title.toLowerCase() == 'hindi novel' ||
              details.title.toLowerCase() == 'unknown') {
            record.flaws.add('Placeholder/stub title: "${details.title}"');
          }

          List<Chapter> chapters = [];
          try {
            chapters = await s.getChapterList(sample.sourceUrl).timeout(const Duration(seconds: 12));
            record.chaptersCount = chapters.length;
            record.chaptersOk = chapters.isNotEmpty;
            if (chapters.isEmpty) {
              record.flaws.add('Chapter list is empty');
            }
          } catch (e) {
            record.flaws.add('getChapterList failed: $e');
          }

          if (chapters.isNotEmpty) {
            final firstChapter = chapters.first;
            try {
              final content = await s.getChapterContent(firstChapter.url).timeout(const Duration(seconds: 12));
              record.paragraphCount = content.paragraphs.length;
              record.charCount = content.paragraphs.fold(0, (sum, p) => sum + p.length);
              record.contentOk = record.charCount > 150 && record.paragraphCount >= 1;

              if (content.paragraphs.isNotEmpty) {
                record.firstParagraphSnippet = content.paragraphs.first.replaceAll('\n', ' ').trim();
                if (record.firstParagraphSnippet.length > 80) {
                  record.firstParagraphSnippet = '${record.firstParagraphSnippet.substring(0, 80)}...';
                }
              }

              if (record.charCount < 100 || record.paragraphCount <= 1) {
                if (!isBook || record.charCount < 50) {
                  record.flaws.add('Chapter content is a stub (${record.charCount} chars, ${record.paragraphCount} paras)');
                }
              }
            } catch (e) {
              record.flaws.add('getChapterContent failed: $e');
            }
          }
        } catch (e) {
          record.flaws.add('getNovelDetails failed: $e');
        }
      } else {
        record.flaws.add('No catalog novels found');
      }

      if (record.flaws.isEmpty) {
        print('   ✅ OK (${record.catalogCount} books, ${record.chaptersCount} ch, ${record.paragraphCount} paras, cover: ${record.coverValid ? "valid" : "none"})');
      } else {
        print('   ⚠️ ISSUES (${record.flaws.join(", ")})');
      }

      records.add(record);
    }

    print('\n========================================================================');
    print('📊 FINAL AUDIT TABLE');
    print('========================================================================\n');
    print('| Source ID | Name | Lang | Type | Catalog | Cover | Chapters | Ch 1 Content | Flaws |');
    print('|---|---|---|---|---|---|---|---|---|');
    for (final r in records) {
      final catalogStr = r.catalogOk ? '${r.catalogCount} items' : '❌ 0';
      final coverStr = r.coverValid ? '✅ Valid' : '❌ Broken';
      final chStr = r.chaptersOk ? '✅ ${r.chaptersCount} ch' : '❌ None';
      final contentStr = r.contentOk ? '✅ ${r.paragraphCount}p (${r.charCount}c)' : '❌ Short/Empty';
      final flawStr = r.flaws.isEmpty ? '✅ None' : r.flaws.join('; ');
      print('| `${r.sourceId}` | ${r.name} | ${r.lang} | ${r.type} | $catalogStr | $coverStr | $chStr | $contentStr | $flawStr |');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
