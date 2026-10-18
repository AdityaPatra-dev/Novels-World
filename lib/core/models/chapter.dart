class Chapter {
  final String id;
  final String novelId;
  final String title;
  final double? chapterNumber;
  final String url;
  final String? releaseDate;
  final bool isDownloaded;

  const Chapter({
    required this.id,
    required this.novelId,
    required this.title,
    this.chapterNumber,
    required this.url,
    this.releaseDate,
    this.isDownloaded = false,
  });

  Chapter copyWith({
    String? id,
    String? novelId,
    String? title,
    double? chapterNumber,
    String? url,
    String? releaseDate,
    bool? isDownloaded,
  }) {
    return Chapter(
      id: id ?? this.id,
      novelId: novelId ?? this.novelId,
      title: title ?? this.title,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      url: url ?? this.url,
      releaseDate: releaseDate ?? this.releaseDate,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'novelId': novelId,
      'title': title,
      'chapterNumber': chapterNumber,
      'url': url,
      'releaseDate': releaseDate,
      'isDownloaded': isDownloaded,
    };
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      novelId: json['novelId'] as String,
      title: json['title'] as String,
      chapterNumber: (json['chapterNumber'] as num?)?.toDouble(),
      url: json['url'] as String,
      releaseDate: json['releaseDate'] as String?,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
    );
  }
}

