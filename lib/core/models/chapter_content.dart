class ChapterContent {
  final String chapterId;
  final String novelId;
  final String title;
  final String rawText;
  final List<String> paragraphs;

  const ChapterContent({
    required this.chapterId,
    required this.novelId,
    required this.title,
    required this.rawText,
    required this.paragraphs,
  });

  /// Extracts narrative units for continuous, fluid audiobook playback.
  /// Preserves paragraphs intact so the TTS engine speaks multi-sentence thoughts
  /// with natural human prosody, emotional inflection, and zero audio gaps between lines.
  List<String> toSentences() {
    final List<String> units = [];
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;

      // Keep standard paragraphs (under 600 characters) completely intact for continuous speech
      if (trimmed.length <= 600) {
        units.add(trimmed);
      } else {
        // Only break up unusually massive mega-paragraphs at major sentence boundaries
        final RegExp sentenceRegex = RegExp(r'[^.!?]+(?:[.!?]+["' r"'\s]*)");
        final matches = sentenceRegex.allMatches(trimmed);
        if (matches.isEmpty) {
          units.add(trimmed);
        } else {
          int lastIndex = 0;
          for (final match in matches) {
            final s = match.group(0)?.trim();
            if (s != null && s.isNotEmpty) {
              units.add(s);
            }
            lastIndex = match.end;
          }
          if (lastIndex < trimmed.length) {
            final rem = trimmed.substring(lastIndex).trim();
            if (rem.isNotEmpty) units.add(rem);
          }
        }
      }
    }
    return units;
  }

  Map<String, dynamic> toJson() {
    return {
      'chapterId': chapterId,
      'novelId': novelId,
      'title': title,
      'rawText': rawText,
      'paragraphs': paragraphs,
    };
  }

  factory ChapterContent.fromJson(Map<String, dynamic> json) {
    return ChapterContent(
      chapterId: json['chapterId'] as String,
      novelId: json['novelId'] as String,
      title: json['title'] as String? ?? '',
      rawText: json['rawText'] as String? ?? '',
      paragraphs: (json['paragraphs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
