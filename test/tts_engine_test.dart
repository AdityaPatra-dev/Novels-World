import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/tts/tts_model_registry.dart';
import 'package:novels_world/tts/sleep_timer_service.dart';
import 'package:novels_world/tts/ring_buffer_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2: Neural TTS Engine & Real-Time Audio Architecture', () {
    test('TtsModelRegistry catalogs the 3 specialized novel models', () {
      final models = TtsModelRegistry.models;
      expect(models.length, greaterThanOrEqualTo(4));

      final kokoro = TtsModelRegistry.getModel(TtsModelRegistry.kokoroId);
      expect(kokoro.name, contains('Kokoro-82M'));
      expect(kokoro.voices, contains(contains('af_bella')));

      final piper = TtsModelRegistry.getModel(TtsModelRegistry.piperId);
      expect(piper.name, contains('Piper TTS'));
      expect(piper.voices, contains(contains('en_US-lessac-high')));

      final sherpa = TtsModelRegistry.getModel(TtsModelRegistry.sherpaId);
      expect(sherpa.name, contains('Sherpa-Matcha'));
      expect(sherpa.voices, contains(contains('cjk_storyteller_bilingual')));
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

      // Verify switching engines
      manager.switchEngine(TtsModelRegistry.piperId);
      expect(manager.activeEngine.id, TtsModelRegistry.piperId);

      manager.switchEngine(TtsModelRegistry.sherpaId);
      expect(manager.activeEngine.id, TtsModelRegistry.sherpaId);
    });
  });
}

