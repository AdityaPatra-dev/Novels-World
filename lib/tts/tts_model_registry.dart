class TtsModelInfo {
  final String id;
  final String name;
  final String category;
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
  static const String edgeNeuralId = 'edge_neural';
  static const String kokoroId = 'kokoro';
  static const String piperId = 'piper';
  static const String sherpaId = 'sherpa';
  static const String systemId = 'system';

  static const List<TtsModelInfo> models = [
    TtsModelInfo(
      id: edgeNeuralId,
      name: 'Microsoft Neural HD (Studio AI)',
      category: 'Ultra-Realistic Studio (Gold Standard)',
      description:
          'Premier studio AI narrator with human breathing, emotional sentence prosody, and fluid pacing. The ultimate audiobook experience for webnovels.',
      estimatedSizeMb: 0.0,
      defaultVoice: 'en-US-ChristopherNeural',
      voices: [
        'en-US-ChristopherNeural (Christopher - Heroic Baritone)',
        'en-US-JennyNeural (Jenny - Warm Expressive Narrator)',
        'en-US-GuyNeural (Guy - Relaxed Conversational)',
        'en-US-AriaNeural (Aria - Dynamic High-Clarity)',
        'en-GB-SoniaNeural (Sonia - British Fantasy Lore)',
        'en-GB-RyanNeural (Ryan - British Aristocratic Sage)',
        'en-US-BrianNeural (Brian - Deep Wisdom & Worldbuilding)',
        'en-US-AvaNeural (Ava - Gentle Bedside Storyteller)',
      ],
      isDownloaded: true,
    ),
    TtsModelInfo(
      id: kokoroId,
      name: 'Kokoro-82M (Expressive Audiobook)',
      category: 'Warm Dramatic Storyteller (Audiophile)',
      description:
          'Acoustic literary model calibrated with deliberate pacing, rich chest resonance, and dramatic dialogue acting.',
      estimatedSizeMb: 82.0,
      defaultVoice: 'en-US-AndrewMultilingualNeural',
      voices: [
        'en-US-AndrewMultilingualNeural (Andrew - Audio Drama Baritone)',
        'en-US-EmmaMultilingualNeural (Emma - Emotional Literature Narrator)',
        'en-US-EricNeural (Eric - Dynamic Protagonist)',
        'en-US-MichelleNeural (Michelle - Contemporary Urban Fantasy)',
        'en-US-RogerNeural (Roger - Gravelly Grimdark & Noir)',
        'en-GB-ThomasNeural (Thomas - British Grand Chronicler)',
      ],
      isDownloaded: true,
    ),
    TtsModelInfo(
      id: piperId,
      name: 'Piper Fast Neural (Speed Reading)',
      category: 'High-Speed Articulation & Clarity',
      description:
          'Ultra-fast neural acoustic model tuned with bright treble and rapid consonant clarity. Ideal for 1.25x-2.5x speed listening.',
      estimatedSizeMb: 45.0,
      defaultVoice: 'en-US-SteffanNeural',
      voices: [
        'en-US-SteffanNeural (Steffan - Rapid Crisp Articulation)',
        'en-GB-LibbyNeural (Libby - Fast Snappy British)',
        'en-CA-ClaraNeural (Clara - High-Clarity Progression)',
        'en-CA-LiamNeural (Liam - Rapid Progression Male)',
        'en-AU-NatashaNeural (Natasha - Crystal Clear Articulation)',
      ],
      isDownloaded: true,
    ),
    TtsModelInfo(
      id: sherpaId,
      name: 'Sherpa-Matcha (Cultivation & Asian Webnovels)',
      category: 'Asian Webnovel Specialist (Xianxia & Romaji)',
      description:
          'Features a built-in phonetic transliterator for Xianxia cultivation terms (Qi -> Chee, Dantian -> Dan-tien, Dao -> Dow) and Asian light novels.',
      estimatedSizeMb: 60.0,
      defaultVoice: 'en-SG-WayneNeural',
      voices: [
        'en-SG-WayneNeural (Wayne - Xianxia Cultivation Sage)',
        'en-SG-LunaNeural (Luna - Light Novel & Xianxia Maiden)',
        'en-IN-PrabhatNeural (Prabhat - Eastern Lore Master)',
        'en-IN-NeerjaExpressiveNeural (Neerja - Expressive Mythos Narrator)',
        'en-HK-YanNeural (Yan - Asian Martial World Chronicler)',
      ],
      isDownloaded: true,
    ),
    TtsModelInfo(
      id: systemId,
      name: 'Device Native (Offline Hardware)',
      category: 'Zero-Download Hardware Engine',
      description:
          'Direct hardware voice synthesizer on your device (Google TTS / Samsung). Works completely offline with zero data usage.',
      estimatedSizeMb: 0.0,
      defaultVoice: 'default',
      voices: [
        'System Default Voice (Device Offline Hardware)',
      ],
      isDownloaded: true,
    ),
  ];

  static TtsModelInfo getModel(String id) {
    return models.firstWhere((m) => m.id == id, orElse: () => models.first);
  }
}
