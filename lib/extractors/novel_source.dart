import '../core/models/novel.dart';
import '../core/models/chapter.dart';
import '../core/models/chapter_content.dart';

abstract class NovelSource {
  String get id;
  String get name;
  String get baseUrl;
  String get lang;
  String get iconUrl;
  int get estimatedNovelCount;

  Future<List<Novel>> search(String query, {int page = 1});
  Future<List<Novel>> getPopular({int page = 1});
  Future<List<Novel>> getLatest({int page = 1});
  Future<Novel> getNovelDetails(String novelUrl);
  Future<List<Chapter>> getChapterList(String novelUrl);
  Future<ChapterContent> getChapterContent(String chapterUrl);
}

