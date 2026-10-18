import 'package:flutter/material.dart';

enum ReaderTheme {
  light,
  sepia,
  dark,
  amoled,
}

class ReaderSettings {
  final ReaderTheme theme;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final bool autoScrollWithTTS;
  final double ttsSpeed;
  final String ttsEngine; // 'kokoro', 'piper', 'sherpa'
  final String ttsVoice;

  const ReaderSettings({
    this.theme = ReaderTheme.dark,
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.fontFamily = 'Lora',
    this.autoScrollWithTTS = true,
    this.ttsSpeed = 1.0,
    this.ttsEngine = 'kokoro',
    this.ttsVoice = 'af_bella',
  });

  Color get backgroundColor {
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFFFAF9F6);
      case ReaderTheme.sepia:
        return const Color(0xFFF4ECD8);
      case ReaderTheme.dark:
        return const Color(0xFF1E1E24);
      case ReaderTheme.amoled:
        return Colors.black;
    }
  }

  Color get textColor {
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFF2B2B2B);
      case ReaderTheme.sepia:
        return const Color(0xFF433422);
      case ReaderTheme.dark:
        return const Color(0xFFE2E2E6);
      case ReaderTheme.amoled:
        return const Color(0xFFD6D6D6);
    }
  }

  Color get highlightColor {
    switch (theme) {
      case ReaderTheme.light:
        return Colors.amber.withValues(alpha: 0.35);
      case ReaderTheme.sepia:
        return const Color(0xFFD4A373).withValues(alpha: 0.4);
      case ReaderTheme.dark:
        return Colors.indigo.withValues(alpha: 0.4);
      case ReaderTheme.amoled:
        return Colors.deepPurple.withValues(alpha: 0.5);
    }
  }

  ReaderSettings copyWith({
    ReaderTheme? theme,
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    bool? autoScrollWithTTS,
    double? ttsSpeed,
    String? ttsEngine,
    String? ttsVoice,
  }) {
    return ReaderSettings(
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      autoScrollWithTTS: autoScrollWithTTS ?? this.autoScrollWithTTS,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsVoice: ttsVoice ?? this.ttsVoice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme.name,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'autoScrollWithTTS': autoScrollWithTTS,
      'ttsSpeed': ttsSpeed,
      'ttsEngine': ttsEngine,
      'ttsVoice': ttsVoice,
    };
  }

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      theme: ReaderTheme.values.firstWhere(
        (e) => e.name == json['theme'],
        orElse: () => ReaderTheme.dark,
      ),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.6,
      fontFamily: json['fontFamily'] as String? ?? 'Lora',
      autoScrollWithTTS: json['autoScrollWithTTS'] as bool? ?? true,
      ttsSpeed: (json['ttsSpeed'] as num?)?.toDouble() ?? 1.0,
      ttsEngine: json['ttsEngine'] as String? ?? 'kokoro',
      ttsVoice: json['ttsVoice'] as String? ?? 'af_bella',
    );
  }
}
