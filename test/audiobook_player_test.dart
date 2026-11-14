import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/providers/audiobook_player_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storageService;
  late AudiobookPlayerProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('player_test_');
    storageService = StorageService();
    await storageService.init(appDir: tempDir);
    provider = AudiobookPlayerProvider(storageService: storageService);
  });

  tearDown(() {
    provider.dispose();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('AudiobookPlayerProvider default state', () {
    expect(provider.hasTrack, isFalse);
    expect(provider.isPlaying, isFalse);
    expect(provider.speed, 1.0);
    expect(provider.sleepTimerRemaining, isNull);
  });

  test('AudiobookPlayerProvider speed adjustment', () async {
    await provider.setSpeed(1.5);
    expect(provider.speed, 1.5);

    await provider.setSpeed(0.75);
    expect(provider.speed, 0.75);
  });

  test('AudiobookPlayerProvider sleep timer configuration', () {
    provider.setSleepTimer(const Duration(minutes: 15));
    expect(provider.sleepTimerDuration, const Duration(minutes: 15));
    expect(provider.sleepTimerRemaining, const Duration(minutes: 15));

    // Turn sleep timer off
    provider.setSleepTimer(null);
    expect(provider.sleepTimerRemaining, isNull);
  });
}
