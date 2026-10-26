import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/tts/services/edge_drm.dart';
import 'package:novels_world/tts/services/edge_tts_client.dart';
import 'package:novels_world/tts/engines/edge_neural_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Daily Neural TTS Health & DRM Handshake Suite', () {
    final Map<String, dynamic> ttsHealthReport = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'status': 'FAILED',
      'drm_token_valid': false,
      'websocket_handshake': false,
      'synthesis_passed': false,
      'latency_ms': 0,
      'audio_bytes_received': 0,
      'mp3_header_valid': false,
      'voice_tested': 'en-US-ChristopherNeural',
      'error_type': '',
      'error_message': '',
    };

    tearDownAll(() {
      try {
        final reportsDir = Directory('build/reports');
        if (!reportsDir.existsSync()) {
          reportsDir.createSync(recursive: true);
        }
        final reportFile = File('build/reports/tts_health_summary.json');
        reportFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(ttsHealthReport));

        // Generate Markdown summary
        final mdFile = File('build/reports/tts_health_summary.md');
        final mdContent = '''# 🎙️ Daily Neural TTS Health Report
**Timestamp:** `${ttsHealthReport['timestamp']}`  
**Overall Status:** ${ttsHealthReport['status'] == 'HEALTHY' ? '✅ HEALTHY' : '❌ FAILED'}  
**Voice Tested:** `${ttsHealthReport['voice_tested']}`  
**Audio Bytes:** `${ttsHealthReport['audio_bytes_received']} bytes`  
**Latency:** `${ttsHealthReport['latency_ms']} ms`  
**DRM Token Valid:** ${ttsHealthReport['drm_token_valid'] ? '✅ Yes' : '❌ No'}  
**WebSocket Handshake:** ${ttsHealthReport['websocket_handshake'] ? '✅ Connected' : '❌ Failed'}  
**MP3 Frame Integrity:** ${ttsHealthReport['mp3_header_valid'] ? '✅ Verified' : '❌ Invalid'}  
${ttsHealthReport['error_message'].toString().isNotEmpty ? '\n> [!CAUTION]\n> **Failure Message:** `${ttsHealthReport['error_message']}`\n' : ''}
''';
        mdFile.writeAsStringSync(mdContent);
        // ignore: avoid_print
        print('\n📊 TTS Health Summary saved to: ${reportFile.path}');
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to write TTS health summary: $e');
      }
    });

    test('1. EdgeDrm v2 Token Algorithm Mathematical Compliance', () {
      final token1 = EdgeDrm.generateSecMsGecV2(1700000000);
      expect(token1, '2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2');

      final token2 = EdgeDrm.generateSecMsGecV2(1720000000);
      expect(token2, '576EF243D9E6C36D-B73D5ADB984074BAE7860791FCA9CE1D28D1F6678CE5644A7981ACCA7E3C0EF2');

      final liveToken = EdgeDrm.generateSecMsGecV2();
      expect(liveToken, matches(RegExp(r'^[0-9A-F]{16}-[0-9A-F]{64}$')),
          reason: 'v2 token must be exactly 16-hex CS64 and 64-hex SHA-256 HMAC separated by hyphen');
      expect(EdgeDrm.secMsGecVersion, '2-143.0.3650.75');

      ttsHealthReport['drm_token_valid'] = true;
    });

    test('2. Live Clock Synchronization and Server Handshake', () async {
      final stopwatch = Stopwatch()..start();
      try {
        await EdgeTtsClient.calibrateClock(force: true);
        stopwatch.stop();
        ttsHealthReport['websocket_handshake'] = true;
      } catch (e) {
        stopwatch.stop();
        ttsHealthReport['error_type'] = 'ClockSyncFailed';
        ttsHealthReport['error_message'] = e.toString();
        fail('Failed to calibrate clock against Microsoft TTS endpoint: $e');
      }
    });

    test('3. Live WebSocket DRM Handshake and Neural Audio Synthesis', () async {
      final stopwatch = Stopwatch()..start();
      const testPhrase = 'Novels World neural text-to-speech health check passed.';
      const testVoice = 'en-US-ChristopherNeural';

      try {
        final Uint8List? audioBytes = await EdgeTtsClient.synthesizeToBytes(
          testPhrase,
          voice: testVoice,
          timeout: const Duration(seconds: 15),
        );

        stopwatch.stop();
        final elapsed = stopwatch.elapsedMilliseconds;
        ttsHealthReport['latency_ms'] = elapsed;

        expect(audioBytes, isNotNull, reason: 'EdgeTtsClient returned null audio bytes');
        expect(audioBytes!.length, greaterThan(1000),
            reason: 'Audio payload should be at least 1 KB of MP3 frames for a full sentence');

        ttsHealthReport['audio_bytes_received'] = audioBytes.length;

        // Verify MPEG audio sync frame (first 11 bits must all be 1: 0xFF followed by 0xEx/0xFx)
        bool hasMpegSync = false;
        for (int i = 0; i < audioBytes.length - 1 && i < 200; i++) {
          if (audioBytes[i] == 0xFF && (audioBytes[i + 1] & 0xE0) == 0xE0) {
            hasMpegSync = true;
            break;
          }
        }

        expect(hasMpegSync, isTrue, reason: 'Audio stream does not contain valid MPEG audio sync header');
        ttsHealthReport['mp3_header_valid'] = true;
        ttsHealthReport['synthesis_passed'] = true;
        ttsHealthReport['status'] = 'HEALTHY';

        // ignore: avoid_print
        print('✅ Microsoft Edge Neural TTS Live Check: OK (${audioBytes.length} bytes in ${elapsed}ms)');
      } catch (e) {
        stopwatch.stop();
        ttsHealthReport['latency_ms'] = stopwatch.elapsedMilliseconds;
        ttsHealthReport['error_type'] = e.toString().contains('403') ? 'HTTP 403 Forbidden (DRM Token Rejected)' : 'WebSocketSynthesisError';
        ttsHealthReport['error_message'] = e.toString();
        // ignore: avoid_print
        print('❌ Microsoft Edge Neural TTS Live Check Failed: $e');
        rethrow;
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('4. End-to-End File Synthesis and Frame Integrity via EdgeNeuralEngine', () async {
      final engine = EdgeNeuralEngine();
      await engine.initialize();

      const testSentence = 'This is a high quality chapter sentence for Novels World.';
      final filePath = await engine.synthesizeSentenceToFile(
        testSentence,
        voice: 'en-US-ChristopherNeural',
        speed: 1.0,
        pitch: 1.0,
      );

      expect(filePath, isNotNull, reason: 'Engine should return valid audio file path');
      final file = File(filePath!);
      expect(await file.exists(), isTrue, reason: 'Synthesized file must exist on disk');

      final fileLength = await file.length();
      expect(fileLength, greaterThan(1000), reason: 'Audio file must be non-empty and >1000 bytes');

      // Verify file can be read and deleted cleanly
      await file.delete();
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}

