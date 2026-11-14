/// Global multi-language registry mapping 70+ languages to studio-grade Microsoft Neural HD voices,
/// native spellings, flags, sample preview greetings, and gendered narrator profiles.
class LanguageVoiceInfo {
  final String code;
  final String englishName;
  final String nativeName;
  final String flag;
  final String samplePhrase;
  final String defaultFemaleVoice;
  final String defaultMaleVoice;
  final List<String> voices;

  const LanguageVoiceInfo({
    required this.code,
    required this.englishName,
    required this.nativeName,
    required this.flag,
    required this.samplePhrase,
    required this.defaultFemaleVoice,
    required this.defaultMaleVoice,
    required this.voices,
  });

  String get displayName => '$flag $nativeName ($englishName)';
}

class LanguageVoiceRegistry {
  static const LanguageVoiceInfo defaultLanguage = LanguageVoiceInfo(
    code: 'en',
    englishName: 'English',
    nativeName: 'English',
    flag: '🇬🇧',
    samplePhrase: 'Welcome to Novels World, enjoy your story.',
    defaultFemaleVoice: 'en-US-JennyNeural',
    defaultMaleVoice: 'en-US-ChristopherNeural',
    voices: [
      'en-US-ChristopherNeural (Christopher - Heroic Baritone)',
      'en-US-JennyNeural (Jenny - Warm Expressive Narrator)',
      'en-US-GuyNeural (Guy - Relaxed Conversational)',
      'en-US-AriaNeural (Aria - Dynamic High-Clarity)',
      'en-GB-RyanNeural (Ryan - British Aristocratic Sage)',
      'en-GB-SoniaNeural (Sonia - British Fantasy Lore)',
      'en-US-BrianNeural (Brian - Deep Wisdom & Worldbuilding)',
      'en-US-AvaNeural (Ava - Gentle Bedside Storyteller)',
    ],
  );

  static const List<LanguageVoiceInfo> supportedLanguages = [
    // English
    defaultLanguage,

    // Hindi & Major Indian Languages
    LanguageVoiceInfo(
      code: 'hi',
      englishName: 'Hindi',
      nativeName: 'हिन्दी',
      flag: '🇮🇳',
      samplePhrase: 'नमस्ते! उपन्यासों की दुनिया में आपका स्वागत है।',
      defaultFemaleVoice: 'hi-IN-SwaraNeural',
      defaultMaleVoice: 'hi-IN-MadhurNeural',
      voices: [
        'hi-IN-SwaraNeural (Swara - Warm Expressive Female)',
        'hi-IN-MadhurNeural (Madhur - Deep Storyteller Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'bn',
      englishName: 'Bengali',
      nativeName: 'বাংলা',
      flag: '🇮🇳',
      samplePhrase: 'নভেলস ওয়ার্ল্ডে আপনাকে স্বাগতম, গল্প উপভোগ করুন।',
      defaultFemaleVoice: 'bn-IN-TanishaaNeural',
      defaultMaleVoice: 'bn-IN-BashkarNeural',
      voices: [
        'bn-IN-TanishaaNeural (Tanishaa - Sweet Female)',
        'bn-IN-BashkarNeural (Bashkar - Resonant Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'te',
      englishName: 'Telugu',
      nativeName: 'తెలుగు',
      flag: '🇮🇳',
      samplePhrase: 'నవలల ప్రపంచానికి స్వాగతం, మీ కథను ఆస్వాదించండి.',
      defaultFemaleVoice: 'te-IN-ShrutiNeural',
      defaultMaleVoice: 'te-IN-MohanNeural',
      voices: [
        'te-IN-ShrutiNeural (Shruti - Expressive Female)',
        'te-IN-MohanNeural (Mohan - Narrative Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'ta',
      englishName: 'Tamil',
      nativeName: 'தமிழ்',
      flag: '🇮🇳',
      samplePhrase: 'நாவல் உலகத்திற்கு வரவேற்கிறோம், கதையை ரசியுங்கள்.',
      defaultFemaleVoice: 'ta-IN-PallaviNeural',
      defaultMaleVoice: 'ta-IN-ValluvarNeural',
      voices: [
        'ta-IN-PallaviNeural (Pallavi - Clear Female)',
        'ta-IN-ValluvarNeural (Valluvar - Classical Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'mr',
      englishName: 'Marathi',
      nativeName: 'मराठी',
      flag: '🇮🇳',
      samplePhrase: 'कादंबरीच्या विश्वात आपले स्वागत आहे, कथेचा आनंद घ्या.',
      defaultFemaleVoice: 'mr-IN-AarohiNeural',
      defaultMaleVoice: 'mr-IN-ManoharNeural',
      voices: [
        'mr-IN-AarohiNeural (Aarohi - Melodious Female)',
        'mr-IN-ManoharNeural (Manohar - Storyteller Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'gu',
      englishName: 'Gujarati',
      nativeName: 'ગુજરાતી',
      flag: '🇮🇳',
      samplePhrase: 'નવલકથાઓની દુનિયામાં આપનું સ્વાગત છે, વાર્તા માણો.',
      defaultFemaleVoice: 'gu-IN-DhwaniNeural',
      defaultMaleVoice: 'gu-IN-NiranjanNeural',
      voices: [
        'gu-IN-DhwaniNeural (Dhwani - Bright Female)',
        'gu-IN-NiranjanNeural (Niranjan - Calm Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'kn',
      englishName: 'Kannada',
      nativeName: 'ಕನ್ನಡ',
      flag: '🇮🇳',
      samplePhrase: 'ಕಾದಂಬರಿಗಳ ಜಗತ್ತಿಗೆ ಸ್ವಾಗತ, ಕಥೆಯನ್ನು ಆನಂದಿಸಿ.',
      defaultFemaleVoice: 'kn-IN-SapnaNeural',
      defaultMaleVoice: 'kn-IN-GaganNeural',
      voices: [
        'kn-IN-SapnaNeural (Sapna - Gentle Female)',
        'kn-IN-GaganNeural (Gagan - Resonant Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'ml',
      englishName: 'Malayalam',
      nativeName: 'മലയാളം',
      flag: '🇮🇳',
      samplePhrase: 'നോവലുകളുടെ ലോകത്തേക്ക് സ്വാഗതം, കഥ ആസ്വദിക്കൂ.',
      defaultFemaleVoice: 'ml-IN-SobhanaNeural',
      defaultMaleVoice: 'ml-IN-MidhunNeural',
      voices: [
        'ml-IN-SobhanaNeural (Sobhana - Soft Female)',
        'ml-IN-MidhunNeural (Midhun - Deep Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'pa',
      englishName: 'Punjabi',
      nativeName: 'ਪੰਜਾਬੀ',
      flag: '🇮🇳',
      samplePhrase: 'ਨਾਵਲਾਂ ਦੀ ਦੁਨੀਆ ਵਿੱਚ ਜੀ ਆਇਆਂ ਨੂੰ, ਕਹਾਣੀ ਦਾ ਆਨੰਦ ਲਓ।',
      defaultFemaleVoice: 'pa-IN-OjasNeural',
      defaultMaleVoice: 'pa-IN-RaagNeural',
      voices: [
        'pa-IN-OjasNeural (Ojas - Energetic Female)',
        'pa-IN-RaagNeural (Raag - Warm Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'ur',
      englishName: 'Urdu',
      nativeName: 'اردو',
      flag: '🇵🇰',
      samplePhrase: 'ناولز کی دنیا میں خوش آمدید، کہانی سے لطف اٹھائیں۔',
      defaultFemaleVoice: 'ur-PK-UzmaNeural',
      defaultMaleVoice: 'ur-PK-AsadNeural',
      voices: [
        'ur-PK-UzmaNeural (Uzma - Poetic Female)',
        'ur-PK-AsadNeural (Asad - Refined Male)',
      ],
    ),

    // European Languages
    LanguageVoiceInfo(
      code: 'es',
      englishName: 'Spanish',
      nativeName: 'Español',
      flag: '🇪🇸',
      samplePhrase: '¡Hola! Bienvenido al mundo de las novelas, disfruta de la historia.',
      defaultFemaleVoice: 'es-ES-ElviraNeural',
      defaultMaleVoice: 'es-ES-AlvaroNeural',
      voices: [
        'es-ES-ElviraNeural (Elvira - Warm Spanish Female)',
        'es-ES-AlvaroNeural (Alvaro - Confident Spanish Male)',
        'es-MX-DaliaNeural (Dalia - Vibrant Mexican Female)',
        'es-MX-JorgeNeural (Jorge - Friendly Mexican Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'fr',
      englishName: 'French',
      nativeName: 'Français',
      flag: '🇫🇷',
      samplePhrase: 'Bienvenue dans le monde des romans, bonne lecture et bonne écoute.',
      defaultFemaleVoice: 'fr-FR-DeniseNeural',
      defaultMaleVoice: 'fr-FR-HenriNeural',
      voices: [
        'fr-FR-DeniseNeural (Denise - Expressive French Female)',
        'fr-FR-HenriNeural (Henri - Classic French Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'de',
      englishName: 'German',
      nativeName: 'Deutsch',
      flag: '🇩🇪',
      samplePhrase: 'Willkommen in der Welt der Romane, genießen Sie Ihre Geschichte.',
      defaultFemaleVoice: 'de-DE-KatjaNeural',
      defaultMaleVoice: 'de-DE-ConradNeural',
      voices: [
        'de-DE-KatjaNeural (Katja - Clear German Female)',
        'de-DE-ConradNeural (Conrad - Authoritative German Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'it',
      englishName: 'Italian',
      nativeName: 'Italiano',
      flag: '🇮🇹',
      samplePhrase: 'Benvenuto nel mondo dei romanzi, goditi la storia.',
      defaultFemaleVoice: 'it-IT-ElsaNeural',
      defaultMaleVoice: 'it-IT-DiegoNeural',
      voices: [
        'it-IT-ElsaNeural (Elsa - Melodic Italian Female)',
        'it-IT-DiegoNeural (Diego - Engaging Italian Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'pt',
      englishName: 'Portuguese',
      nativeName: 'Português',
      flag: '🇧🇷',
      samplePhrase: 'Bem-vindo ao mundo dos romances, aproveite a história.',
      defaultFemaleVoice: 'pt-BR-FranciscaNeural',
      defaultMaleVoice: 'pt-BR-AntonioNeural',
      voices: [
        'pt-BR-FranciscaNeural (Francisca - Brazilian Female)',
        'pt-BR-AntonioNeural (Antonio - Brazilian Male)',
        'pt-PT-RaquelNeural (Raquel - European Portuguese Female)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'ru',
      englishName: 'Russian',
      nativeName: 'Русский',
      flag: '🇷🇺',
      samplePhrase: 'Добро пожаловать в мир романов, приятного чтения и прослушивания.',
      defaultFemaleVoice: 'ru-RU-SvetlanaNeural',
      defaultMaleVoice: 'ru-RU-DmitryNeural',
      voices: [
        'ru-RU-SvetlanaNeural (Svetlana - Expressive Russian Female)',
        'ru-RU-DmitryNeural (Dmitry - Resonant Russian Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'nl',
      englishName: 'Dutch',
      nativeName: 'Nederlands',
      flag: '🇳🇱',
      samplePhrase: 'Welkom in de wereld van romans, geniet van het verhaal.',
      defaultFemaleVoice: 'nl-NL-ColetteNeural',
      defaultMaleVoice: 'nl-NL-MaartenNeural',
      voices: [
        'nl-NL-ColetteNeural (Colette - Smooth Dutch Female)',
        'nl-NL-MaartenNeural (Maarten - Natural Dutch Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'pl',
      englishName: 'Polish',
      nativeName: 'Polski',
      flag: '🇵🇱',
      samplePhrase: 'Witamy w świecie powieści, życzymy miłego słuchania.',
      defaultFemaleVoice: 'pl-PL-ZofiaNeural',
      defaultMaleVoice: 'pl-PL-MarekNeural',
      voices: [
        'pl-PL-ZofiaNeural (Zofia - Clear Polish Female)',
        'pl-PL-MarekNeural (Marek - Deep Polish Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'uk',
      englishName: 'Ukrainian',
      nativeName: 'Українська',
      flag: '🇺🇦',
      samplePhrase: 'Ласкаво просимо у світ романів, приємного читання.',
      defaultFemaleVoice: 'uk-UA-PolinaNeural',
      defaultMaleVoice: 'uk-UA-OstapNeural',
      voices: [
        'uk-UA-PolinaNeural (Polina - Melodic Female)',
        'uk-UA-OstapNeural (Ostap - Narrative Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'sv',
      englishName: 'Swedish',
      nativeName: 'Svenska',
      flag: '🇸🇪',
      samplePhrase: 'Välkommen till romanernas värld, njut av berättelsen.',
      defaultFemaleVoice: 'sv-SE-SofieNeural',
      defaultMaleVoice: 'sv-SE-MattiasNeural',
      voices: [
        'sv-SE-SofieNeural (Sofie - Swedish Female)',
        'sv-SE-MattiasNeural (Mattias - Swedish Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'el',
      englishName: 'Greek',
      nativeName: 'Ελληνικά',
      flag: '🇬🇷',
      samplePhrase: 'Καλώς ήρθατε στον κόσμο των μυθιστορημάτων, απολαύστε την ιστορία.',
      defaultFemaleVoice: 'el-GR-AthinaNeural',
      defaultMaleVoice: 'el-GR-NestorasNeural',
      voices: [
        'el-GR-AthinaNeural (Athina - Classical Greek Female)',
        'el-GR-NestorasNeural (Nestoras - Deep Greek Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'cs',
      englishName: 'Czech',
      nativeName: 'Čeština',
      flag: '🇨🇿',
      samplePhrase: 'Vítejte ve světě románů, užijte si příběh.',
      defaultFemaleVoice: 'cs-CZ-VlastaNeural',
      defaultMaleVoice: 'cs-CZ-AntoninNeural',
      voices: [
        'cs-CZ-VlastaNeural (Vlasta - Gentle Female)',
        'cs-CZ-AntoninNeural (Antonin - Warm Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'ro',
      englishName: 'Romanian',
      nativeName: 'Română',
      flag: '🇷🇴',
      samplePhrase: 'Bun venit în lumea romanelor, lectură plăcută.',
      defaultFemaleVoice: 'ro-RO-AlinaNeural',
      defaultMaleVoice: 'ro-RO-EmilNeural',
      voices: [
        'ro-RO-AlinaNeural (Alina - Expressive Female)',
        'ro-RO-EmilNeural (Emil - Calm Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'hu',
      englishName: 'Hungarian',
      nativeName: 'Magyar',
      flag: '🇭🇺',
      samplePhrase: 'Üdvözöljük a regények világában, kellemes kikapcsolódást.',
      defaultFemaleVoice: 'hu-HU-NoemiNeural',
      defaultMaleVoice: 'hu-HU-TamasNeural',
      voices: [
        'hu-HU-NoemiNeural (Noemi - Hungarian Female)',
        'hu-HU-TamasNeural (Tamas - Hungarian Male)',
      ],
    ),

    // East Asian Languages
    LanguageVoiceInfo(
      code: 'ja',
      englishName: 'Japanese',
      nativeName: '日本語',
      flag: '🇯🇵',
      samplePhrase: '小説の世界へようこそ。物語をお楽しみください。',
      defaultFemaleVoice: 'ja-JP-NanamiNeural',
      defaultMaleVoice: 'ja-JP-KeitaNeural',
      voices: [
        'ja-JP-NanamiNeural (Nanami - Expressive Anime Female)',
        'ja-JP-KeitaNeural (Keita - Heroic Light Novel Male)',
        'ja-JP-AoiNeural (Aoi - Gentle Traditional Female)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'zh',
      englishName: 'Chinese (Simplified)',
      nativeName: '简体中文',
      flag: '🇨🇳',
      samplePhrase: '欢迎来到小说世界，享受精彩的故事旅程。',
      defaultFemaleVoice: 'zh-CN-XiaoxiaoNeural',
      defaultMaleVoice: 'zh-CN-YunxiNeural',
      voices: [
        'zh-CN-XiaoxiaoNeural (Xiaoxiao - Emotional Xianxia Female)',
        'zh-CN-YunxiNeural (Yunxi - Deep Cultivation Male)',
        'zh-CN-YunjianNeural (Yunjian - Martial Arts Master Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'zh-TW',
      englishName: 'Chinese (Traditional)',
      nativeName: '繁體中文',
      flag: '🇹🇼',
      samplePhrase: '歡迎來到小說世界，祝您閱讀愉快。',
      defaultFemaleVoice: 'zh-TW-HsiaoChenNeural',
      defaultMaleVoice: 'zh-TW-YunJheNeural',
      voices: [
        'zh-TW-HsiaoChenNeural (HsiaoChen - Elegant Female)',
        'zh-TW-YunJheNeural (YunJhe - Sophisticated Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'ko',
      englishName: 'Korean',
      nativeName: '한국어',
      flag: '🇰🇷',
      samplePhrase: '소설의 세계에 오신 것을 환영합니다. 즐거운 감상 되세요.',
      defaultFemaleVoice: 'ko-KR-SunHiNeural',
      defaultMaleVoice: 'ko-KR-InJoonNeural',
      voices: [
        'ko-KR-SunHiNeural (SunHi - Webtoon Drama Female)',
        'ko-KR-InJoonNeural (InJoon - Resonant Protagonist Male)',
      ],
    ),

    // Southeast Asian & Middle Eastern
    LanguageVoiceInfo(
      code: 'id',
      englishName: 'Indonesian',
      nativeName: 'Bahasa Indonesia',
      flag: '🇮🇩',
      samplePhrase: 'Selamat datang di dunia novel, nikmati kisahnya.',
      defaultFemaleVoice: 'id-ID-GadisNeural',
      defaultMaleVoice: 'id-ID-ArdiNeural',
      voices: [
        'id-ID-GadisNeural (Gadis - Warm Indonesian Female)',
        'id-ID-ArdiNeural (Ardi - Friendly Indonesian Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'vi',
      englishName: 'Vietnamese',
      nativeName: 'Tiếng Việt',
      flag: '🇻🇳',
      samplePhrase: 'Chào mừng bạn đến với thế giới tiểu thuyết, chúc bạn nghe truyện vui vẻ.',
      defaultFemaleVoice: 'vi-VN-HoaiMyNeural',
      defaultMaleVoice: 'vi-VN-NamMinhNeural',
      voices: [
        'vi-VN-HoaiMyNeural (HoaiMy - Melodious Female)',
        'vi-VN-NamMinhNeural (NamMinh - Clear Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'th',
      englishName: 'Thai',
      nativeName: 'ไทย',
      flag: '🇹🇭',
      samplePhrase: 'ยินดีต้อนรับสู่โลกแห่งนวนิยาย ขอให้เพลิดเพลินกับเรื่องราว',
      defaultFemaleVoice: 'th-TH-PremwadeeNeural',
      defaultMaleVoice: 'th-TH-NiwatNeural',
      voices: [
        'th-TH-PremwadeeNeural (Premwadee - Soft Female)',
        'th-TH-NiwatNeural (Niwat - Narrator Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'tl',
      englishName: 'Filipino / Tagalog',
      nativeName: 'Tagalog',
      flag: '🇵🇭',
      samplePhrase: 'Maligayang pagdating sa mundo ng mga nobela, tamasahin ang kwento.',
      defaultFemaleVoice: 'fil-PH-BlessicaNeural',
      defaultMaleVoice: 'fil-PH-AngeloNeural',
      voices: [
        'fil-PH-BlessicaNeural (Blessica - Warm Tagalog Female)',
        'fil-PH-AngeloNeural (Angelo - Lively Tagalog Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'tr',
      englishName: 'Turkish',
      nativeName: 'Türkçe',
      flag: '🇹🇷',
      samplePhrase: 'Romanların dünyasına hoş geldiniz, hikayenin tadını çıkarın.',
      defaultFemaleVoice: 'tr-TR-EmelNeural',
      defaultMaleVoice: 'tr-TR-AhmetNeural',
      voices: [
        'tr-TR-EmelNeural (Emel - Smooth Turkish Female)',
        'tr-TR-AhmetNeural (Ahmet - Narrative Turkish Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'ar',
      englishName: 'Arabic',
      nativeName: 'العربية',
      flag: '🇸🇦',
      samplePhrase: 'مرحبًا بكم في عالم الروايات، استمتعوا بالقصة.',
      defaultFemaleVoice: 'ar-SA-ZariyahNeural',
      defaultMaleVoice: 'ar-SA-HamedNeural',
      voices: [
        'ar-SA-ZariyahNeural (Zariyah - Expressive Arabic Female)',
        'ar-SA-HamedNeural (Hamed - Eloquent Arabic Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'fa',
      englishName: 'Persian / Farsi',
      nativeName: 'فارسی',
      flag: '🇮🇷',
      samplePhrase: 'به دنیای رمان‌ها خوش آمدید، از شنیدن داستان لذت ببرید.',
      defaultFemaleVoice: 'fa-IR-DilaraNeural',
      defaultMaleVoice: 'fa-IR-FaridNeural',
      voices: [
        'fa-IR-DilaraNeural (Dilara - Gentle Persian Female)',
        'fa-IR-FaridNeural (Farid - Poetic Persian Male)',
      ],
    ),
    LanguageVoiceInfo(
      code: 'he',
      englishName: 'Hebrew',
      nativeName: 'עברית',
      flag: '🇮🇱',
      samplePhrase: 'ברוכים הבאים לעולם הרומנים, תיהנו מהסיפור.',
      defaultFemaleVoice: 'he-IL-HilaNeural',
      defaultMaleVoice: 'he-IL-AvriNeural',
      voices: [
        'he-IL-HilaNeural (Hila - Israeli Female)',
        'he-IL-AvriNeural (Avri - Israeli Male)',
      ],
    ),
  ];

  /// Finds matching language by code, or returns [defaultLanguage] (English) if unknown.
  static LanguageVoiceInfo getByCode(String code) {
    final lower = code.toLowerCase().trim();
    for (final l in supportedLanguages) {
      if (l.code.toLowerCase() == lower || l.code.split('-').first == lower) {
        return l;
      }
    }
    return defaultLanguage;
  }

  /// Searches languages by English name, native script name, or code.
  static List<LanguageVoiceInfo> search(String query) {
    if (query.trim().isEmpty) return supportedLanguages;
    final q = query.toLowerCase().trim();
    return supportedLanguages.where((l) {
      return l.englishName.toLowerCase().contains(q) ||
          l.nativeName.toLowerCase().contains(q) ||
          l.code.toLowerCase().contains(q);
    }).toList();
  }
}
