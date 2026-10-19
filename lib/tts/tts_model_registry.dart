class TtsModelInfo {
  final String id;
  final String name;
  final String category; // 'Expressive Storyteller', 'Ultra-Fast Workhorse', 'CJK Specialist', 'Zero-Download System'
  final String description;
  final double estimatedSizeMb;
  final List<String> voices;
  final String defaultVoice;
  final bool isDownloaded;

  const TtsModelInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.estimatedSizeMb,
    required this.voices,
    required this.defaultVoice,
    this.isDownloaded = false,
  });
}

class TtsModelRegistry {
  static const String kokoroId = 'kokoro';
  static const String piperId = 'piper';
  static const String sherpaId = 'sherpa';
  static const String systemId = 'system';

  static const List<TtsModelInfo> models = [
    TtsModelInfo(
      id: kokoroId,
      name: 'Kokoro-82M',
      category: 'Expressive Storyteller (Audiophile)',
      description:
          'StyleTTS2 architecture with natural cadence, emotional dialogue inflection, and breathing pauses. The gold standard for immersive novel narration.',
      estimatedSizeMb: 82.0,
      defaultVoice: 'af_bella',
      voices: [
        'af_bella (Warm Female Narrator)',
        'af_sarah (Crisp Female Storyteller)',
        'am_michael (Classic Deep Audiobook Voice)',
        'am_adam (Dynamic Male Storyteller)',
        'bf_emma (British Female Narrator)',
        'bm_george (British Male Narrator)',
      ],
      isDownloaded: true,
    ),
    TtsModelInfo(
      id: piperId,
      name: 'Piper TTS (VITS)',
      category: 'Ultra-Fast & Battery-Saver (Low-Latency)',
      description:
          'Sub-50ms latency with minimal RAM and battery consumption. Perfect for all-day continuous reading on mobile without thermal throttling.',
      estimatedSizeMb: 45.0,
      defaultVoice: 'en_US-lessac-high',
      voices: [
        'en_US-lessac-high (Studio Clarity)',
        'en_US-bryce-medium (Dynamic Male)',
        'en_US-amy-medium (Soothing Female)',
      ],
      isDownloaded: true,
    ),
    TtsModelInfo(
      id: sherpaId,
      name: 'Sherpa-Matcha (CJK)',
      category: 'Asian Light Novel Specialist (Pinyin & Romaji)',
      description:
          'Trained with CJK phonemic awareness. Accurately pronounces Xianxia cultivation terms (Dantian, Nascent Soul, Qi), Korean honorifics (Oppa, Hyung), and Japanese names.',
      estimatedSizeMb: 60.0,
      defaultVoice: 'cjk_storyteller_bilingual',
      voices: [
        'cjk_storyteller_bilingual (Xianxia & Wuxia)',
        'cjk_female_narrator (Light Novels & Isekai)',
      ],
      isDownloaded: true,
    ),
    TtsModelInfo(
      id: systemId,
      name: 'System / Device Native',
      category: 'Instant Zero-Download Fallback',
      description:
          'Uses the operating system default voice engine. Works immediately with zero model downloads required.',
      estimatedSizeMb: 0.0,
      defaultVoice: 'default',
      voices: ['System Default Voice'],
      isDownloaded: true,
    ),
  ];

  static TtsModelInfo getModel(String id) {
    return models.firstWhere((m) => m.id == id, orElse: () => models.first);
  }
}

