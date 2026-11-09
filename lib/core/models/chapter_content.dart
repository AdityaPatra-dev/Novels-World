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

  /// Extracts flowing narrative units for continuous, fluid audiobook playback.
  /// Combines paragraphs into natural narrative sections (~600-800 characters)
  /// separated by '\n\n', so the TTS engine reads paragraphs and lines continuously
  /// in one breath with zero pause, exactly like reading from line to line within a paragraph,
  /// while preserving standard novel book typography and layout.
  List<String> toSentences() {
    final List<String> rawParagraphs = [];
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('[IMAGE:')) {
        rawParagraphs.add(trimmed);
        continue;
      }

      // If a single paragraph is unusually massive (>600 chars), break it at sentence boundaries
      if (trimmed.length <= 600) {
        rawParagraphs.add(trimmed);
      } else {
        final RegExp sentenceRegex = RegExp(r'[^.!?]+(?:[.!?]+["' r"'\s]*)");
        final matches = sentenceRegex.allMatches(trimmed);
        if (matches.isEmpty) {
          rawParagraphs.add(trimmed);
        } else {
          final StringBuffer chunk = StringBuffer();
          for (final m in matches) {
            final s = m.group(0)?.trim() ?? '';
            if (s.isEmpty) continue;
            if (chunk.isNotEmpty && (chunk.length + s.length > 450)) {
              rawParagraphs.add(chunk.toString().trim());
              chunk.clear();
            }
            if (chunk.isNotEmpty) chunk.write(' ');
            chunk.write(s);
          }
          if (chunk.isNotEmpty) {
            rawParagraphs.add(chunk.toString().trim());
          }
        }
      }
    }

    // Group paragraphs into natural flowing reading blocks (~650-800 characters)
    // joined by '\n\n' so the TTS reads continuously from paragraph to paragraph
    // with ZERO delay, exactly like lines inside a paragraph!
    final List<String> units = [];
    final StringBuffer buffer = StringBuffer();

    for (final p in rawParagraphs) {
      if (p.startsWith('[IMAGE:')) {
        if (buffer.isNotEmpty) {
          units.add(buffer.toString().trim());
          buffer.clear();
        }
        units.add(p);
        continue;
      }
      if (buffer.isNotEmpty && (buffer.length + p.length + 2 > 700)) {
        units.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) {
        buffer.write('\n\n');
      }
      buffer.write(p);
    }
    if (buffer.isNotEmpty) {
      units.add(buffer.toString().trim());
    }

    return units.isNotEmpty ? units : rawParagraphs;
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
