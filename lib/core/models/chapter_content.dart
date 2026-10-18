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

  /// Extracts clean sentence segments from the chapter text.
  /// Used both for Karaoke-style active reading highlighting and real-time TTS synthesis.
  List<String> toSentences() {
    final List<String> sentences = [];
    final RegExp sentenceRegex = RegExp(r'[^.!?]+(?:[.!?]+["' r"'\s]*)");

    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;

      final matches = sentenceRegex.allMatches(trimmed);
      if (matches.isEmpty) {
        sentences.add(trimmed);
      } else {
        int lastIndex = 0;
        for (final match in matches) {
          final sentence = match.group(0)?.trim();
          if (sentence != null && sentence.isNotEmpty) {
            sentences.add(sentence);
          }
          lastIndex = match.end;
        }
        if (lastIndex < trimmed.length) {
          final remaining = trimmed.substring(lastIndex).trim();
          if (remaining.isNotEmpty) {
            sentences.add(remaining);
          }
        }
      }
    }
    return sentences;
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
      title: json['title'] as String,
      rawText: json['rawText'] as String,
      paragraphs: (json['paragraphs'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

