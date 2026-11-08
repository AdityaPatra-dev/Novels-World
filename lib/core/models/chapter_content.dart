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
  /// Preserves paragraphs intact and groups consecutive short lines into natural
  /// continuous narrative blocks, eliminating stop-and-start delays between short lines
  /// and delivering seamless audiobook playback across both mobile and web.
  List<String> toSentences() {
    final List<String> rawUnits = [];
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;

      // Keep standard paragraphs intact for continuous speech
      if (trimmed.length <= 600) {
        rawUnits.add(trimmed);
      } else {
        // Chunk unusually massive mega-paragraphs at major sentence boundaries into ~400 char segments
        final RegExp sentenceRegex = RegExp(r'[^.!?]+(?:[.!?]+["' r"'\s]*)");
        final matches = sentenceRegex.allMatches(trimmed);
        if (matches.isEmpty) {
          rawUnits.add(trimmed);
        } else {
          final StringBuffer chunk = StringBuffer();
          for (final m in matches) {
            final s = m.group(0)?.trim() ?? '';
            if (s.isEmpty) continue;
            if (chunk.isNotEmpty && (chunk.length + s.length > 450)) {
              rawUnits.add(chunk.toString().trim());
              chunk.clear();
            }
            if (chunk.isNotEmpty) chunk.write(' ');
            chunk.write(s);
          }
          if (chunk.isNotEmpty) {
            rawUnits.add(chunk.toString().trim());
          }
        }
      }
    }

    // Merge consecutive short lines (e.g. dialogue, short beats < 180 chars)
    // into continuous narrative blocks so they read continuously without stopping.
    final List<String> units = [];
    final StringBuffer buffer = StringBuffer();

    for (final unit in rawUnits) {
      if (unit.length >= 180) {
        if (buffer.isNotEmpty) {
          units.add(buffer.toString().trim());
          buffer.clear();
        }
        units.add(unit);
      } else {
        if (buffer.isNotEmpty && (buffer.length + unit.length + 1 > 360)) {
          units.add(buffer.toString().trim());
          buffer.clear();
        }
        if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(unit);
      }
    }
    if (buffer.isNotEmpty) {
      units.add(buffer.toString().trim());
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
