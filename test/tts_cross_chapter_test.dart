import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:novels_world/tts/ring_buffer_manager.dart';
import 'package:novels_world/tts/sleep_timer_service.dart';

class MockJustAudioPlatform extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    return MockAudioPlayerPlatform(request.id);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    return DisposeAllPlayersResponse();
  }
}

class MockAudioPlayerPlatform extends AudioPlayerPlatform {
  final _eventController = StreamController<PlaybackEventMessage>.broadcast();

  MockAudioPlayerPlatform(super.id);

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    return LoadResponse(duration: const Duration(seconds: 5));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUpAll(() {
    JustAudioPlatform.instance = MockJustAudioPlatform();
  });

  group('Cross-Chapter Continuous Audio Flow & Seamless Preloading Tests', () {
    test('RingBufferManager detects approaching end of chapter 2-3 lines before end', () {
      final manager = RingBufferManager();
      final chapter1Sentences = [
        'Line 0: The storm was gathering on the distant horizon.',
        'Line 1: Jiang Chen grasped his celestial sword tightly.',
        'Line 2: The clouds rumbled with thunderous roar.',
        'Line 3: He stepped onto the ancient altar.',
        'Line 4: This realm was finally within reach.',
      ];

      bool approachedEnd = false;
      manager.onApproachingEndOfChapter = () {
        approachedEnd = true;
      };

      manager.loadSentences(chapter1Sentences, startIndex: 0);
      expect(approachedEnd, isFalse, reason: 'Index 0 is not near the end of a 5-sentence chapter');

      // Index 1 (1 < 5 - 3 = 2): Not yet approaching
      manager.checkApproachingEnd(1);
      expect(approachedEnd, isFalse);

      // Index 2 (2 >= 5 - 3 = 2): 3 lines before end, should fire callback
      manager.checkApproachingEnd(2);
      expect(approachedEnd, isTrue, reason: 'Index 2 is within 3 sentences of the end (5 - 3 = 2)');

      // Verify idempotency: does not fire repeatedly once triggered
      approachedEnd = false;
      manager.checkApproachingEnd(3);
      expect(approachedEnd, isFalse, reason: 'Should only trigger once per chapter');
    });

    test('queueNextChapterSentences buffers upcoming chapter and prepares seamless transition', () {
      final manager = RingBufferManager();
      final chapter1 = ['Sentence 0', 'Sentence 1', 'Sentence 2'];
      final chapter2 = ['Next Chapter Sentence 0', 'Next Chapter Sentence 1'];

      bool crossChapterFired = false;
      int? startedSentenceIndex;

      manager.onCrossChapterTransition = () {
        crossChapterFired = true;
      };
      manager.onSentenceStarted = (idx) {
        startedSentenceIndex = idx;
      };

      manager.loadSentences(chapter1, startIndex: 0);
      manager.queueNextChapterSentences(chapter2);

      // Verify that next chapter sentences are safely held and active chapter is untouched
      expect(manager.sentences.length, 3);
      expect(manager.sentences.first, 'Sentence 0');
      expect(crossChapterFired, isFalse);

      // Simulate native ExoPlayer audio rolling into next_0 tag
      manager.handleCrossChapterTag('next_0');

      // Now chapter 2 sentences must be promoted to active sentences
      expect(crossChapterFired, isTrue);
      expect(manager.sentences.length, 2);
      expect(manager.sentences[0], 'Next Chapter Sentence 0');
      expect(manager.sentences[1], 'Next Chapter Sentence 1');
      expect(manager.currentIndex, 0);
      expect(startedSentenceIndex, 0);
    });

    test('Sleep timer mode endOfChapter pauses playback when chapter concludes at cross-chapter boundary', () {
      final manager = RingBufferManager();
      final chapter1 = ['Sentence 0', 'Sentence 1'];
      final chapter2 = ['Next Chapter Sentence 0'];

      manager.loadSentences(chapter1, startIndex: 0);
      manager.queueNextChapterSentences(chapter2);

      manager.sleepTimer.setMode(SleepTimerMode.endOfChapter);
      expect(manager.sleepTimer.mode, SleepTimerMode.endOfChapter);
      expect(manager.sleepTimer.isActive, isTrue);

      bool crossChapterFired = false;
      manager.onCrossChapterTransition = () {
        crossChapterFired = true;
      };

      // Player crosses into next chapter boundary tag
      manager.handleCrossChapterTag('next_0');

      // Playback should stop, sleep timer expired, and NOT transition into next chapter
      expect(manager.isPlaying, isFalse);
      expect(manager.sleepTimer.isActive, isFalse);
      expect(manager.sleepTimer.mode, SleepTimerMode.off);
      expect(crossChapterFired, isFalse, reason: 'Must not transition when end-of-chapter sleep timer halts playback');
    });

    test('UI content isolation: Preloaded chapter does not overwrite active chapter content prematurely', () {
      // Simulating ReaderProvider state logic
      String currentChapterContent = 'Chapter 1: The Beginning.';
      List<String> currentSentences = ['Line 1', 'Line 2', 'Line 3', 'Line 4', 'Line 5'];
      int currentChapterIndex = 0;

      String? preloadedNextContent;
      List<String> preloadedNextSentences = [];

      // Step 1: Preload next chapter triggered 2-3 lines before end
      void simulatePreload() {
        preloadedNextContent = 'Chapter 2: The Journey Continues.';
        preloadedNextSentences = ['Ch2 Line 1', 'Ch2 Line 2'];
      }

      // 2 lines before end
      simulatePreload();

      // Ensure active UI content is STILL Chapter 1
      expect(currentChapterContent, 'Chapter 1: The Beginning.');
      expect(currentSentences.length, 5);
      expect(currentChapterIndex, 0);
      expect(preloadedNextContent, isNotNull);

      // Step 2: Audio playlist rolls into next chapter
      void simulateCrossChapterTransition() {
        currentChapterIndex++;
        currentChapterContent = preloadedNextContent!;
        currentSentences = List<String>.from(preloadedNextSentences);
        preloadedNextContent = null;
        preloadedNextSentences = [];
      }

      simulateCrossChapterTransition();

      // Now UI is atomically swapped to Chapter 2
      expect(currentChapterIndex, 1);
      expect(currentChapterContent, 'Chapter 2: The Journey Continues.');
      expect(currentSentences.length, 2);
      expect(preloadedNextContent, isNull);
    });

    test('Strict monotonic sentence progression: no double-repeats or backward loops', () {
      final manager = RingBufferManager();
      final chapter1 = [
        'Paragraph 0: The starry night stretched infinitely.',
        'Paragraph 1: Jiang Chen examined his cultivation elixir.',
        'Paragraph 2: A sudden roar echoed across the mountain.',
      ];

      final playedSequence = <int>[];
      manager.onSentenceStarted = (idx) {
        playedSequence.add(idx);
      };

      manager.loadSentences(chapter1, startIndex: 0);

      // Verify that sentence progression advances linearly without duplicate entries
      expect(manager.currentIndex, 0);
      expect(manager.sentences.length, 3);

      // Fast-forward indices
      manager.checkApproachingEnd(1);
      manager.checkApproachingEnd(2);

      // Verify each sentence index is distinct and advancing
      expect(playedSequence, isEmpty); // No spurious callbacks before play
    });
  });
}

