import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/chapter.dart';
import 'package:novels_world/core/models/chapter_content.dart';
import 'package:novels_world/extractors/novel_source.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/data/download_service.dart';
import 'package:novels_world/providers/library_provider.dart';
import 'package:novels_world/providers/reader_provider.dart';
import 'package:novels_world/providers/settings_provider.dart';
import 'package:novels_world/main.dart';

class _TestHttpOverrides extends HttpOverrides {}

class MockNovelSource implements NovelSource {
  @override
  String get id => '1stkissnovel';
  @override
  String get name => 'Mock Source';
  @override
  String get baseUrl => 'https://mock.com';
  @override
  String get lang => 'en';
  @override
  String get iconUrl => '';
  @override
  int get estimatedNovelCount => 100;

  @override
  Future<List<Novel>> getPopular({int page = 1}) async => [
        const Novel(
          id: 'mock_1',
          sourceId: '1stkissnovel',
          title: 'Mock Solo Leveling',
          author: 'Chugong',
          sourceUrl: 'https://mock.com/novel/solo',
        ),
      ];

  @override
  Future<List<Novel>> getLatest({int page = 1}) async => [];

  @override
  Future<List<Novel>> search(String query, {int page = 1}) async => [];

  @override
  Future<Novel> getNovelDetails(String novelUrl) async => const Novel(
        id: 'mock_1',
        sourceId: '1stkissnovel',
        title: 'Mock Solo Leveling',
        sourceUrl: 'https://mock.com/novel/solo',
      );

  @override
  Future<List<Chapter>> getChapterList(String novelUrl) async => [];

  @override
  Future<ChapterContent> getChapterContent(String chapterUrl) async => const ChapterContent(
        chapterId: 'ch_1',
        novelId: 'mock_1',
        title: 'Chapter 1',
        rawText: 'Hello world',
        paragraphs: ['Hello world'],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HttpOverrides.global = _TestHttpOverrides();
  });

  testWidgets('NovelsWorldApp renders home screen with navigation tabs', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('novels_world_test');
    final storageService = StorageService();
    await tester.runAsync(() async {
      await storageService.init(appDir: tempDir);
    });

    SourceRegistry.registerSource(MockNovelSource());
    SourceRegistry.setDefaultSourceId('1stkissnovel');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storageService),
          ChangeNotifierProvider(create: (_) => SettingsProvider(storageService)),
          ChangeNotifierProvider(create: (_) => LibraryProvider(storageService)),
          ChangeNotifierProvider(create: (_) => ReaderProvider(storageService)),
          ChangeNotifierProvider(create: (_) => DownloadService(storageService)),
        ],
        child: const NovelsWorldApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
