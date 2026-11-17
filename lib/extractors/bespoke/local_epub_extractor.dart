import 'dart:convert';
import 'dart:io';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/chapter_content.dart';
import '../../core/services/epub_service.dart';
import '../novel_source.dart';

/// Extractor for Local EPUB Books.
/// Enables full offline reading, chapter navigation, custom fonts/themes,
/// and background TTS audiobook playback on imported user EPUBs.
class LocalEpubExtractor implements NovelSource {
  @override
  final String id = 'local_epub';

  @override
  final String name = 'Local EPUB';

  @override
  final String baseUrl = 'file://';

  @override
  final String lang = 'en';

  @override
  final String iconUrl = '';

  @override
  final int estimatedNovelCount = 0;

  final EpubService _epubService = EpubService();

  @override
  Future<List<Novel>> getPopular({int page = 1}) async {
    if (page > 1) return [];
    return _epubService.getImportedNovels();
  }

  @override
  Future<List<Novel>> getLatest({int page = 1}) async {
    if (page > 1) return [];
    return _epubService.getImportedNovels();
  }

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async {
    final all = await _epubService.getImportedNovels();
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return all;
    return all.where((n) =>
      n.title.toLowerCase().contains(q) ||
      n.author.toLowerCase().contains(q) ||
      n.description.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final uri = Uri.parse(novelUrl);
    final rawPath = uri.scheme == 'file' ? uri.toFilePath() : novelUrl;
    final path = rawPath.endsWith('/') ? rawPath.substring(0, rawPath.length - 1) : rawPath;

    // Check if path is a raw .epub file or an unpacked directory
    if (path.endsWith('.epub') && await File(path).exists()) {
      return _epubService.importEpub(File(path));
    }

    final metaFile = File('$path/metadata.json');
    if (await metaFile.exists()) {
      final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final novelJson = json['novel'] as Map<String, dynamic>;
      return Novel.fromJson(novelJson);
    }

    final docPdf = File('$path/document.pdf');
    if (await docPdf.exists()) {
      return _epubService.importPdf(docPdf, targetDir: Directory(path).parent);
    }

    throw HttpException('Could not find local EPUB metadata at $path');
  }

  @override
  Future<List<Chapter>> getChapterList(
    String novelUrl, {
    void Function(List<Chapter> batch)? onBatchLoaded,
  }) async {
    final uri = Uri.parse(novelUrl);
    final rawPath = uri.scheme == 'file' ? uri.toFilePath() : novelUrl;
    final path = rawPath.endsWith('/') ? rawPath.substring(0, rawPath.length - 1) : rawPath;

    final docPdf = File('$path/document.pdf');
    final metaFile = File('$path/metadata.json');

    if (!await metaFile.exists() && await docPdf.exists()) {
      try {
        await _epubService.importPdf(docPdf, targetDir: Directory(path).parent);
      } catch (_) {}
    }

    if (await metaFile.exists()) {
      final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final rawChapters = json['chapters'] as List;
      var chs = rawChapters
          .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
          .toList();

      // Auto-heal previously stubbed or image-only scanned PDFs: re-import with OCR
      if (await docPdf.exists()) {
        final chaptersDir = Directory('$path/chapters');
        bool hasOnlyImageChapters = chs.length <= 1;
        if (!hasOnlyImageChapters && await chaptersDir.exists()) {
          final firstChFile = File('${chaptersDir.path}/chapter_1.xhtml');
          if (await firstChFile.exists()) {
            final content = await firstChFile.readAsString();
            if (content.contains('[IMAGE:') && content.contains('/pages/page_')) {
              hasOnlyImageChapters = true;
            }
          }
        }

        if (hasOnlyImageChapters) {
          try {
            Novel? orig;
            if (json['novel'] != null) {
              orig = Novel.fromJson(json['novel'] as Map<String, dynamic>);
            }
            await _epubService.importPdf(docPdf, targetDir: Directory(path).parent, originalNovel: orig);
            if (await metaFile.exists()) {
              final updatedJson = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
              final updatedRawChapters = updatedJson['chapters'] as List;
              chs = updatedRawChapters
                  .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
                  .toList();
            }
          } catch (_) {}
        }
      }

      if (chs.isNotEmpty) {
        onBatchLoaded?.call(chs);
      }
      return chs;
    }

    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    return _epubService.loadChapterContent(chapterUrl);
  }
}

