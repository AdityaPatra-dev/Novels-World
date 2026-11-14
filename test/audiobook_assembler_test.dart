import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/services/audiobook_assembler_service.dart';
import 'package:novels_world/data/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;
  late AudiobookAssemblerService assembler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('audiobook_test_');
    storage = StorageService();
    await storage.init(appDir: tempDir);
    assembler = AudiobookAssemblerService(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AudiobookAssemblerService - ID3 & Binary Frame Processing', () {
    test('encodeSynchsafe and decodeSynchsafe roundtrip', () {
      final testValues = [0, 1, 127, 128, 255, 1024, 65535, 16384, 1048576, 268435455];
      for (final val in testValues) {
        final encoded = AudiobookAssemblerService.encodeSynchsafe(val);
        expect(encoded.length, 4);
        for (final b in encoded) {
          expect(b & 0x80, 0, reason: 'Synchsafe byte must have bit 7 clear');
        }
        final decoded = AudiobookAssemblerService.decodeSynchsafe(encoded);
        expect(decoded, val);
      }
    });

    test('buildId3v2Tag creates valid ID3v2.3 tag with metadata and cover', () {
      final dummyCover = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, // JPEG Magic
        0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      ]);

      final tag = assembler.buildId3v2Tag(
        title: 'Chapter 1: The Beginning',
        artist: 'Author Name',
        album: 'Epic Novel',
        trackNumber: 1,
        coverBytes: dummyCover,
      );

      expect(tag.length, greaterThan(10));
      // ID3 Header check
      expect(tag[0], 0x49); // 'I'
      expect(tag[1], 0x44); // 'D'
      expect(tag[2], 0x33); // '3'
      expect(tag[3], 0x03); // v2.3
      expect(tag[4], 0x00); // revision 0

      // Synchsafe size check
      final tagPayloadSize = AudiobookAssemblerService.decodeSynchsafe(tag.sublist(6, 10));
      expect(tag.length, 10 + tagPayloadSize);

      // Verify frame IDs exist in payload
      final tagString = String.fromCharCodes(tag);
      expect(tagString.contains('TIT2'), isTrue);
      expect(tagString.contains('TPE1'), isTrue);
      expect(tagString.contains('TALB'), isTrue);
      expect(tagString.contains('TRCK'), isTrue);
      expect(tagString.contains('APIC'), isTrue);
    });

    test('stripId3HeaderAndPadding strips chunk ID3 and locates MPEG sync word', () {
      // Create a fake chunk that has an ID3 tag, followed by padding, followed by MPEG sync 0xFF 0xFB
      final chunkTag = assembler.buildId3v2Tag(
        title: 'Chunk Title',
        artist: 'Artist',
        album: 'Album',
      );

      final mpegAudio = Uint8List.fromList([
        0xFF, 0xFB, 0x90, 0x44, // Valid MPEG Layer 3 header
        0xAA, 0xBB, 0xCC, 0xDD,
      ]);

      final chunkBytes = Uint8List.fromList([...chunkTag, 0x00, 0x00, ...mpegAudio]);

      final stripped = assembler.stripId3HeaderAndPadding(chunkBytes);
      expect(stripped, equals(mpegAudio));
    });
  });

  group('Audiobook Assembly & StorageService Integration', () {
    test('assembles multiple chunks into chapter MP3 and updates StorageService', () async {
      // 1. Create synthetic sentence chunk files
      final chunkDir = Directory('${tempDir.path}/chunks');
      await chunkDir.create(recursive: true);

      final chunkPaths = <String>[];
      for (int i = 0; i < 3; i++) {
        final chunkFile = File('${chunkDir.path}/chunk_$i.mp3');
        final mpegData = Uint8List.fromList([
          0xFF, 0xFB, 0x90, 0x44,
          i, i * 2, i * 3, 0xFF,
        ]);
        await chunkFile.writeAsBytes(mpegData);
        chunkPaths.add(chunkFile.path);
      }

      // 2. Assemble into chapter audiobook
      final novel = Novel(
        id: 'shadow_slave',
        title: 'Shadow Slave',
        author: 'Guiltythree',
        sourceId: 'novelfire',
        sourceUrl: 'https://example.com/shadow_slave',
      );

      final result = await assembler.assembleChapterAudiobook(
        novelId: 'shadow_slave',
        chapterId: 'chapter_1',
        lang: 'hi',
        chunkFilePaths: chunkPaths,
        novel: novel,
        chapterTitle: 'Chapter 1: Nightmare Begins',
        trackNumber: 1,
      );

      expect(result, isNotNull);
      expect(await result!.exists(), isTrue);
      expect(result.path.endsWith('chapter_1_hi.mp3'), isTrue);

      // Verify file content begins with ID3
      final fileBytes = await result.readAsBytes();
      expect(fileBytes[0], 0x49); // 'I'
      expect(fileBytes[1], 0x44); // 'D'
      expect(fileBytes[2], 0x33); // '3'

      // 3. Test StorageService methods
      expect(storage.hasOfflineAudiobook('shadow_slave', 'chapter_1', 'hi'), isTrue);
      expect(storage.hasOfflineAudiobook('shadow_slave', 'chapter_1'), isTrue);
      expect(storage.hasOfflineAudiobook('shadow_slave', 'chapter_1', 'es'), isFalse);
      expect(storage.hasOfflineAudiobook('shadow_slave', 'chapter_999'), isFalse);

      final downloadedChapters = storage.getDownloadedAudiobookChapterIds('shadow_slave');
      expect(downloadedChapters, contains('chapter_1'));

      final langMap = storage.getDownloadedAudiobookLanguages('shadow_slave');
      expect(langMap['chapter_1'], contains('hi'));

      final storageBytes = storage.getAudiobookStorageBytes('shadow_slave');
      expect(storageBytes, equals(fileBytes.length));

      final totalBytes = storage.getTotalAudiobookStorageBytes();
      expect(totalBytes, equals(fileBytes.length));

      // 4. Test deletion
      await storage.deleteAudiobookChapter('shadow_slave', 'chapter_1', 'hi');
      expect(storage.hasOfflineAudiobook('shadow_slave', 'chapter_1', 'hi'), isFalse);
      expect(storage.getAudiobookStorageBytes('shadow_slave'), 0);
    });
  });
}
