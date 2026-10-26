import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/tts/tts_model_registry.dart';
import 'package:novels_world/tts/sleep_timer_service.dart';
import 'package:novels_world/tts/ring_buffer_manager.dart';
import 'package:novels_world/tts/voice_calibration.dart';
import 'package:novels_world/tts/services/edge_drm.dart';
import 'package:novels_world/tts/services/edge_tts_client.dart';
import 'package:novels_world/core/utils/text_cleaner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Phase 2: Neural TTS Engine & Real-Time Audio Architecture', () {
    test('TtsModelRegistry catalogs the 5 specialized novel models with distinct advantages', () {
      final models = TtsModelRegistry.models;
      expect(models.length, greaterThanOrEqualTo(5));

      final edge = TtsModelRegistry.getModel(TtsModelRegistry.edgeNeuralId);
      expect(edge.name, contains('Microsoft Neural HD'));
      expect(edge.voices, contains(contains('en-US-ChristopherNeural')));
      expect(edge.voices, contains(contains('en-US-JennyNeural')));

      final kokoro = TtsModelRegistry.getModel(TtsModelRegistry.kokoroId);
      expect(kokoro.name, contains('Kokoro-82M'));
      expect(kokoro.voices, contains(contains('en-US-AndrewMultilingualNeural')));

      final piper = TtsModelRegistry.getModel(TtsModelRegistry.piperId);
      expect(piper.name, contains('Piper Fast'));
      expect(piper.voices, contains(contains('en-US-SteffanNeural')));

      final sherpa = TtsModelRegistry.getModel(TtsModelRegistry.sherpaId);
      expect(sherpa.name, contains('Sherpa-Matcha'));
      expect(sherpa.voices, contains(contains('en-SG-WayneNeural')));
    });

    test('SleepTimerService countdown and volume fade calculation', () {
      final timer = SleepTimerService();
      expect(timer.isActive, false);

      timer.setMode(SleepTimerMode.minutes15);
      expect(timer.isActive, true);
      expect(timer.remainingSeconds, 15 * 60);
      expect(timer.formattedRemaining, '15:00');

      timer.cancel();
      expect(timer.isActive, false);
      expect(timer.formattedRemaining, 'Off');
    });

    test('RingBufferManager sentence loading and navigation', () {
      final manager = RingBufferManager();
      final sampleSentences = [
        'The morning sun rose over the mist-covered mountains.',
        'Linley opened his eyes, feeling the surge of spiritual energy.',
        '"Today, I shall break through the Nascent Soul realm," he declared.',
      ];

      manager.loadSentences(sampleSentences, startIndex: 0);

      expect(manager.sentences.length, 3);
      expect(manager.currentIndex, 0);

      // Verify speed and pitch calibration
      manager.setSpeed(1.5);
      expect(manager.speed, 1.5);

      // Verify default engine is Edge Neural HD and default voice is Christopher
      expect(manager.activeEngine.id, TtsModelRegistry.edgeNeuralId);
      expect(manager.activeVoice, 'en-US-ChristopherNeural');

      // Verify switching engines
      manager.switchEngine(TtsModelRegistry.piperId);
      expect(manager.activeEngine.id, TtsModelRegistry.piperId);

      manager.switchEngine(TtsModelRegistry.sherpaId);
      expect(manager.activeEngine.id, TtsModelRegistry.sherpaId);

      // Verify sentence pause pacing setting
      manager.setSentencePause(350);
      expect(manager.sentencePauseMs, 350);

      // Verify custom voice selection
      manager.setVoice('am_michael');
      expect(manager.activeVoice, 'am_michael');
    });

    test('VoiceCalibration maps distinct pitches and vocal personalities', () {
      final jenny = VoiceCalibration.getProfile('en-US-JennyNeural');
      final christopher = VoiceCalibration.getProfile('en-US-ChristopherNeural');
      final sonia = VoiceCalibration.getProfile('en-GB-SoniaNeural');
      final ryan = VoiceCalibration.getProfile('en-GB-RyanNeural');

      // Female narrator pitch > 1.0 vs deep baritone male pitch < 0.85
      expect(jenny.basePitch, greaterThan(1.0));
      expect(jenny.gender, 'Female');
      expect(christopher.basePitch, lessThan(0.85));
      expect(christopher.gender, 'Male');

      // British profiles have UK accent
      expect(sonia.accent, 'UK');
      expect(ryan.accent, 'UK');
      expect(ryan.basePitch, lessThan(0.80));
    });

    test('TextCleaner prepareSentenceForSpeech enhances audio prosody and eliminates abrupt cuts', () {
      // Abbreviation expansions
      expect(TextCleaner.prepareSentenceForSpeech('Mr. Li met Dr. Chen.'), contains('Mister Li met Doctor Chen.'));
      expect(TextCleaner.prepareSentenceForSpeech('Read Vol. 2 Ch. 5.'), contains('Volume 2 Chapter 5.'));

      // Brackets cleaned to natural pause for speech
      expect(TextCleaner.prepareSentenceForSpeech('[System Notice] Quest completed!'), contains('System Notice. Quest completed!'));

      // Quotes and ellipses formatted cleanly
      final cleanQuote = TextCleaner.prepareSentenceForSpeech('"I will conquer this realm..."');
      expect(cleanQuote, isNot(startsWith('"')));
      expect(cleanQuote, isNot(startsWith('“')));
      expect(cleanQuote, endsWith('realm...'));
    });

    test('EdgeDrm generates compliant v2 DRM tokens (<16 hex CS64>-<64 hex SHA256>)', () {
      final token = EdgeDrm.generateSecMsGecV2(1700000000);
      expect(token, '2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2');

      final token2 = EdgeDrm.generateSecMsGecV2(1720000000);
      expect(token2, '576EF243D9E6C36D-B73D5ADB984074BAE7860791FCA9CE1D28D1F6678CE5644A7981ACCA7E3C0EF2');

      final liveToken = EdgeDrm.generateSecMsGecV2();
      expect(liveToken, matches(RegExp(r'^[0-9A-F]{16}-[0-9A-F]{64}$')));
      expect(EdgeDrm.secMsGecVersion, startsWith('2-'));
    });
  });
}

