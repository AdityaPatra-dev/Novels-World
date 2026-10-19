abstract class TtsEngineInterface {
  String get id;
  String get name;
  String get description;
  bool get isOfflineNeural;
  List<String> get availableVoices;

  Future<void> initialize();

  /// Synthesizes a single sentence to a playable audio file (WAV/MP3).
  /// Returns the absolute file path, or null if synthesis failed.
  Future<String?> synthesizeSentenceToFile(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
  });

  /// Plays a sentence directly (used for direct system audio stream if supported).
  Future<void> speakSentenceDirect(
    String sentence, {
    required String voice,
    required double speed,
    required double pitch,
    required Function() onDone,
  });

  Future<void> stop();
  Future<void> dispose();
}

