import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/models/reading_progress.dart';
import 'package:novels_world/core/services/auth_service.dart';
import 'package:novels_world/core/services/cloud_sync_service.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/providers/library_provider.dart';
import 'package:novels_world/ui/profile/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auth & Cloud Sync Service Tests', () {
    test('AuthService initial unauthenticated state', () {
      final auth = AuthService.instance;
      expect(auth.isAuthenticated, isFalse);
      expect(auth.displayName, 'Guest Reader');
      expect(auth.email, 'Not signed in');
      expect(auth.photoUrl, isNull);
    });

    test('CloudSyncService unauthenticated graceful fallback', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('cloud_sync_test_');
      final storage = StorageService();
      await storage.init(appDir: tempDir);

      final sync = CloudSyncService.instance;
      await sync.syncFull(storage);
      expect(sync.syncError, 'Not signed in');

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('StorageService persists locally even when cloud sync is offline', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('cloud_offline_test_');
      final storage = StorageService();
      await storage.init(appDir: tempDir);

      const novel = Novel(
        id: 'test_sync_novel_1',
        title: 'Reverend Insanity',
        author: 'Gu Zhen Ren',
        sourceId: 'novelfull',
        sourceUrl: 'https://novelfull.com/reverend-insanity.html',
      );

      await storage.saveNovelToLibrary(novel);
      expect(storage.isNovelInLibrary('test_sync_novel_1'), isTrue);

      await storage.saveProgress(
        ReadingProgress(
          novelId: 'test_sync_novel_1',
          chapterId: 'ch_1',
          chapterTitle: 'Chapter 1: Heart of a Demon',
          lastReadAt: DateTime.now(),
        ),
      );

      final prog = storage.getProgress('test_sync_novel_1');
      expect(prog, isNotNull);
      expect(prog!.chapterTitle, 'Chapter 1: Heart of a Demon');
      expect(storage.isChapterRead('test_sync_novel_1', 'ch_1'), isTrue);

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  group('ProfileScreen UI Tests', () {
    late StorageService storage;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('profile_ui_test_');
      storage = StorageService();
      await storage.init(appDir: tempDir);
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('ProfileScreen renders Google Sign-In button and info card', (tester) async {
      final libraryProvider = LibraryProvider(storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storage),
            ChangeNotifierProvider.value(value: libraryProvider),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header title
      expect(find.text('My Profile & Cloud Sync'), findsOneWidget);

      // Check Google Sign-in text and instructions
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Sign in to Novels World'), findsOneWidget);
      expect(find.textContaining('sync your novels, reading history, and exact chapter progress'), findsOneWidget);
    });
  });
}
