class VoiceProfile {
  final String id;
  final String displayName;
  final String description;
  final String gender;
  final String accent;
  final double basePitch;
  final double baseSpeed;
  final List<String> targetVoiceKeywords;

  const VoiceProfile({
    required this.id,
    required this.displayName,
    required this.description,
    required this.gender,
    required this.accent,
    required this.basePitch,
    required this.baseSpeed,
    required this.targetVoiceKeywords,
  });
}

class VoiceCalibration {
  static const List<VoiceProfile> profiles = [
    // -------------------------------------------------------------
    // Category 1: Microsoft Neural HD (Premier Studio Flagship)
    // -------------------------------------------------------------
    VoiceProfile(
      id: 'en-US-ChristopherNeural',
      displayName: 'Christopher (Studio Heroic Baritone)',
      description: 'Deep, rich, cinematic narration - ideal for LitRPG, cultivation & action novels',
      gender: 'Male',
      accent: 'US',
      basePitch: 0.80,
      baseSpeed: 0.95,
      targetVoiceKeywords: ['en-us-x-iol', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-JennyNeural',
      displayName: 'Jenny (Studio Warm Storyteller)',
      description: 'Emotional, lifelike female voice with natural breathing pauses and expressive dialogue',
      gender: 'Female',
      accent: 'US',
      basePitch: 1.05,
      baseSpeed: 0.95,
      targetVoiceKeywords: ['en-us-x-sfg', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-GuyNeural',
      displayName: 'Guy (Studio Conversational)',
      description: 'Modern, authentic conversational narrator with fluid sentence pacing',
      gender: 'Male',
      accent: 'US',
      basePitch: 0.95,
      baseSpeed: 0.98,
      targetVoiceKeywords: ['en-us-x-iob', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-AriaNeural',
      displayName: 'Aria (Studio High-Clarity)',
      description: 'Crystal-clear, engaging female narration with impeccable articulation',
      gender: 'Female',
      accent: 'US',
      basePitch: 1.10,
      baseSpeed: 0.96,
      targetVoiceKeywords: ['en-us-x-tpd', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-GB-SoniaNeural',
      displayName: 'Sonia (British Fantasy Lore)',
      description: 'Elegant British female voice for medieval, historical fantasy and high drama',
      gender: 'Female',
      accent: 'UK',
      basePitch: 1.04,
      baseSpeed: 0.90,
      targetVoiceKeywords: ['en-gb', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-GB-RyanNeural',
      displayName: 'Ryan (British Aristocratic Sage)',
      description: 'Distinguished British narrator with authoritative gravitas for grand worldbuilding',
      gender: 'Male',
      accent: 'UK',
      basePitch: 0.76,
      baseSpeed: 0.88,
      targetVoiceKeywords: ['en-gb', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-BrianNeural',
      displayName: 'Brian (Deep Grimdark & Wisdom)',
      description: 'Resonant, gravelly baritone for dark fantasy, mysteries, and grim epics',
      gender: 'Male',
      accent: 'US',
      basePitch: 0.72,
      baseSpeed: 0.90,
      targetVoiceKeywords: ['en-us-x-iol', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-AvaNeural',
      displayName: 'Ava (Gentle Bedside Storyteller)',
      description: 'Soothing, gentle female voice calibrated for relaxing evening reading sessions',
      gender: 'Female',
      accent: 'US',
      basePitch: 1.02,
      baseSpeed: 0.92,
      targetVoiceKeywords: ['en-us-x-sfg', 'female', 'en-us'],
    ),

    // -------------------------------------------------------------
    // Category 2: Kokoro-82M (Audiophile Expressive Audiobook Drama)
    // -------------------------------------------------------------
    VoiceProfile(
      id: 'en-US-AndrewMultilingualNeural',
      displayName: 'Andrew (Audio Drama Baritone)',
      description: 'Cinematic, rich audio drama narrator with dynamic character dialogue resonance',
      gender: 'Male',
      accent: 'US',
      basePitch: 0.82,
      baseSpeed: 0.93,
      targetVoiceKeywords: ['en-us-x-iol', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-EmmaMultilingualNeural',
      displayName: 'Emma (Emotional Literature Narrator)',
      description: 'Expressive literary female voice with nuanced emotional depth for romantic & dramatic plots',
      gender: 'Female',
      accent: 'US',
      basePitch: 1.02,
      baseSpeed: 0.94,
      targetVoiceKeywords: ['en-us-x-sfg', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-EricNeural',
      displayName: 'Eric (Dynamic Protagonist)',
      description: 'Youthful, energetic male voice perfect for shonen, progression fantasy and battle scenes',
      gender: 'Male',
      accent: 'US',
      basePitch: 0.96,
      baseSpeed: 0.98,
      targetVoiceKeywords: ['en-us-x-iob', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-MichelleNeural',
      displayName: 'Michelle (Modern Urban Fantasy)',
      description: 'Confident, versatile contemporary female narrator for mystery, thriller & urban fantasy',
      gender: 'Female',
      accent: 'US',
      basePitch: 1.04,
      baseSpeed: 0.96,
      targetVoiceKeywords: ['en-us-x-tpd', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-US-RogerNeural',
      displayName: 'Roger (Gravelly Grimdark & Noir)',
      description: 'Deep, weathered male timbre tailored for post-apocalyptic, detective & grim novels',
      gender: 'Male',
      accent: 'US',
      basePitch: 0.74,
      baseSpeed: 0.90,
      targetVoiceKeywords: ['en-us-x-iol', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-GB-ThomasNeural',
      displayName: 'Thomas (British Grand Chronicler)',
      description: 'Aristocratic British narrator suited for high court intrigue and expansive history',
      gender: 'Male',
      accent: 'UK',
      basePitch: 0.85,
      baseSpeed: 0.90,
      targetVoiceKeywords: ['en-gb', 'male', 'en-us'],
    ),

    // -------------------------------------------------------------
    // Category 3: Piper Fast Neural (Speed Reading & Crisp Articulation)
    // -------------------------------------------------------------
    VoiceProfile(
      id: 'en-US-SteffanNeural',
      displayName: 'Steffan (Rapid Crisp Articulation)',
      description: 'High-tempo masculine articulation engineered for rapid speed binge reading (1.25x-2.5x)',
      gender: 'Male',
      accent: 'US',
      basePitch: 0.92,
      baseSpeed: 1.05,
      targetVoiceKeywords: ['en-us', 'male'],
    ),
    VoiceProfile(
      id: 'en-GB-LibbyNeural',
      displayName: 'Libby (Fast Snappy British)',
      description: 'Snappy British female cadence delivering rapid dialogue without consonant blurring',
      gender: 'Female',
      accent: 'UK',
      basePitch: 1.05,
      baseSpeed: 1.04,
      targetVoiceKeywords: ['en-gb', 'female'],
    ),
    VoiceProfile(
      id: 'en-CA-ClaraNeural',
      displayName: 'Clara (High-Clarity Progression)',
      description: 'Crisp Canadian neutral tone designed for high-speed LitRPG stat screens and fast lore',
      gender: 'Female',
      accent: 'Canada',
      basePitch: 1.00,
      baseSpeed: 1.02,
      targetVoiceKeywords: ['en-ca', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-CA-LiamNeural',
      displayName: 'Liam (Rapid Progression Male)',
      description: 'Clear, modern cadence focused on swift progression fantasy storytelling',
      gender: 'Male',
      accent: 'Canada',
      basePitch: 0.88,
      baseSpeed: 1.04,
      targetVoiceKeywords: ['en-ca', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-AU-NatashaNeural',
      displayName: 'Natasha (Crystal Clear Articulation)',
      description: 'High-frequency Australian clarity engineered for noisy environments and fast speeds',
      gender: 'Female',
      accent: 'Australia',
      basePitch: 1.02,
      baseSpeed: 1.02,
      targetVoiceKeywords: ['en-au', 'female', 'en-us'],
    ),

    // -------------------------------------------------------------
    // Category 4: Sherpa-Matcha (Asian Webnovels, Xianxia & Cultivation)
    // -------------------------------------------------------------
    VoiceProfile(
      id: 'en-SG-WayneNeural',
      displayName: 'Wayne (Xianxia Cultivation Sage)',
      description: 'Deep, measured Asian storytelling cadence calibrated for Daoist cultivation & sect elders',
      gender: 'Male',
      accent: 'Asia',
      basePitch: 0.88,
      baseSpeed: 0.92,
      targetVoiceKeywords: ['en-sg', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-SG-LunaNeural',
      displayName: 'Luna (Light Novel & Xianxia Maiden)',
      description: 'Graceful female timbre designed for Japanese light novels, Korean webnovels & fairy maidens',
      gender: 'Female',
      accent: 'Asia',
      basePitch: 1.08,
      baseSpeed: 0.94,
      targetVoiceKeywords: ['en-sg', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-IN-PrabhatNeural',
      displayName: 'Prabhat (Eastern Lore Master)',
      description: 'Authoritative Eastern cadence with rich inflection for mythical realms and grand scriptures',
      gender: 'Male',
      accent: 'India',
      basePitch: 0.86,
      baseSpeed: 0.92,
      targetVoiceKeywords: ['en-in', 'male', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-IN-NeerjaExpressiveNeural',
      displayName: 'Neerja (Expressive Mythos Narrator)',
      description: 'Lyrical, vibrant storytelling cadence for epic eastern folklore and cultivation sagas',
      gender: 'Female',
      accent: 'India',
      basePitch: 1.04,
      baseSpeed: 0.93,
      targetVoiceKeywords: ['en-in', 'female', 'en-us'],
    ),
    VoiceProfile(
      id: 'en-HK-YanNeural',
      displayName: 'Yan (Asian Martial World Chronicler)',
      description: 'Dynamic Hong Kong English narrator suited for Wuxia martial arts tournaments & sect wars',
      gender: 'Female',
      accent: 'Hong Kong',
      basePitch: 1.02,
      baseSpeed: 0.94,
      targetVoiceKeywords: ['en-hk', 'female', 'en-us'],
    ),

    // -------------------------------------------------------------
    // Category 5: Device Native (Offline Hardware Fallback)
    // -------------------------------------------------------------
    VoiceProfile(
      id: 'default',
      displayName: 'System Default Voice (Device Offline)',
      description: 'On-device hardware voice synthesizer (Google / Samsung TTS). 100% offline with zero data.',
      gender: 'System',
      accent: 'Device',
      basePitch: 1.0,
      baseSpeed: 1.0,
      targetVoiceKeywords: ['en-us', 'default'],
    ),
  ];

  static VoiceProfile getProfile(String voiceId) {
    final cleanId = voiceId.split(' ').first.trim();
    return profiles.firstWhere(
      (p) => p.id == cleanId || voiceId.contains(p.id) || p.displayName.contains(voiceId),
      orElse: () => profiles.first,
    );
  }
}
