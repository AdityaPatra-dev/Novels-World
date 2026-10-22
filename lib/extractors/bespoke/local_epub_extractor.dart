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
  Future<List<Novel>> getPopular({int page = 1}) async => [];

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => [];

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async => [];

  @override
  Future<Novel> getNovelDetails(String novelUrl) async {
    final uri = Uri.parse(novelUrl);
    final path = uri.scheme == 'file' ? uri.toFilePath() : novelUrl;

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

    throw HttpException('Could not find local EPUB metadata at $path');
  }

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async {
    final uri = Uri.parse(novelUrl);
    final path = uri.scheme == 'file' ? uri.toFilePath() : novelUrl;

    final metaFile = File('$path/metadata.json');
    if (await metaFile.exists()) {
      final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final rawChapters = json['chapters'] as List;
      return rawChapters
          .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async {
    return _epubService.loadChapterContent(chapterUrl);
  }
}
