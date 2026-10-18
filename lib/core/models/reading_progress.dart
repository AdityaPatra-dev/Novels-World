class ReadingProgress {
  final String novelId;
  final String chapterId;
  final double scrollOffset; // 0.0 to 1.0 (or pixel offset)
  final int activeSentenceIndex;
  final DateTime lastReadAt;

  const ReadingProgress({
    required this.novelId,
    required this.chapterId,
    this.scrollOffset = 0.0,
    this.activeSentenceIndex = 0,
    required this.lastReadAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'novelId': novelId,
      'chapterId': chapterId,
      'scrollOffset': scrollOffset,
      'activeSentenceIndex': activeSentenceIndex,
      'lastReadAt': lastReadAt.toIso8601String(),
    };
  }

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      novelId: json['novelId'] as String,
      chapterId: json['chapterId'] as String,
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      activeSentenceIndex: json['activeSentenceIndex'] as int? ?? 0,
      lastReadAt: DateTime.tryParse(json['lastReadAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

