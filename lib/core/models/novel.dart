class Novel {
  final String id;
  final String sourceId;
  final String title;
  final String author;
  final String description;
  final String coverUrl;
  final List<String> genres;
  final String status; // ONGOING, COMPLETED, UNKNOWN
  final String sourceUrl;
  final bool inLibrary;
  final String? lastReadChapterId;
  final DateTime? lastReadAt;

  const Novel({
    required this.id,
    required this.sourceId,
    required this.title,
    this.author = 'Unknown Author',
    this.description = '',
    this.coverUrl = '',
    this.genres = const [],
    this.status = 'UNKNOWN',
    required this.sourceUrl,
    this.inLibrary = false,
    this.lastReadChapterId,
    this.lastReadAt,
  });

  Novel copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? author,
    String? description,
    String? coverUrl,
    List<String>? genres,
    String? status,
    String? sourceUrl,
    bool? inLibrary,
    String? lastReadChapterId,
    DateTime? lastReadAt,
  }) {
    return Novel(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      genres: genres ?? this.genres,
      status: status ?? this.status,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      inLibrary: inLibrary ?? this.inLibrary,
      lastReadChapterId: lastReadChapterId ?? this.lastReadChapterId,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceId': sourceId,
      'title': title,
      'author': author,
      'description': description,
      'coverUrl': coverUrl,
      'genres': genres,
      'status': status,
      'sourceUrl': sourceUrl,
      'inLibrary': inLibrary,
      'lastReadChapterId': lastReadChapterId,
      'lastReadAt': lastReadAt?.toIso8601String(),
    };
  }

  factory Novel.fromJson(Map<String, dynamic> json) {
    return Novel(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String,
      author: json['author'] as String? ?? 'Unknown Author',
      description: json['description'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      genres: (json['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      status: json['status'] as String? ?? 'UNKNOWN',
      sourceUrl: json['sourceUrl'] as String,
      inLibrary: json['inLibrary'] as bool? ?? false,
      lastReadChapterId: json['lastReadChapterId'] as String?,
      lastReadAt: json['lastReadAt'] != null ? DateTime.tryParse(json['lastReadAt'] as String) : null,
    );
  }
}

