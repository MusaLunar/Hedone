import 'comic_item.dart';
import 'comic_source.dart';

/// Four built-in comic reader viewing modes.
enum ReaderMode {
  webtoon,
  rtlPaged,
  ltrPaged,
  doublePage;

  String get label => switch (this) {
    ReaderMode.webtoon => '条漫模式',
    ReaderMode.rtlPaged => '日漫右翻左',
    ReaderMode.ltrPaged => '左翻右',
    ReaderMode.doublePage => '双页并排',
  };

  static ReaderMode fromString(String? value) {
    return ReaderMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReaderMode.webtoon,
    );
  }
}

/// Represents one page inside the comic reader.
class ComicPageData {
  const ComicPageData({
    required this.pageIndex,
    required this.pageNumber,
    this.imageUrl,
    this.localFilePath,
    this.chapterId = '',
    this.scrambleId = 220980,
    this.ehPageToken,
    this.ehPageUrl,
    this.skipHathKey,
    this.isScrambled = false,
    this.isLoading = false,
    this.errorMessage,
  });

  final int pageIndex;
  final int pageNumber;
  final String? imageUrl;
  final String? localFilePath;
  final String chapterId;
  final int scrambleId;
  final String? ehPageToken;
  final String? ehPageUrl;
  final String? skipHathKey;
  final bool isScrambled;
  final bool isLoading;
  final String? errorMessage;

  ComicPageData copyWith({
    String? imageUrl,
    String? localFilePath,
    String? ehPageToken,
    String? ehPageUrl,
    String? skipHathKey,
    bool? isScrambled,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ComicPageData(
      pageIndex: pageIndex,
      pageNumber: pageNumber,
      imageUrl: imageUrl ?? this.imageUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      chapterId: chapterId,
      scrambleId: scrambleId,
      ehPageToken: ehPageToken ?? this.ehPageToken,
      ehPageUrl: ehPageUrl ?? this.ehPageUrl,
      skipHathKey: skipHathKey ?? this.skipHathKey,
      isScrambled: isScrambled ?? this.isScrambled,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Persisted reading progress per comic.
class ReadingProgress {
  const ReadingProgress({
    required this.source,
    required this.comicId,
    required this.chapterId,
    required this.chapterTitle,
    required this.pageIndex,
    required this.totalPages,
    required this.updatedAtMs,
    required this.summary,
  });

  final ComicSource source;
  final String comicId;
  final String chapterId;
  final String chapterTitle;
  final int pageIndex;
  final int totalPages;
  final int updatedAtMs;
  final ComicSummary summary;

  String get uniqueKey => '${source.name}:$comicId';

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'comicId': comicId,
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'pageIndex': pageIndex,
    'totalPages': totalPages,
    'updatedAtMs': updatedAtMs,
    'summary': summary.toJson(),
  };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      source: ComicSource.fromString(json['source']?.toString()),
      comicId: (json['comicId'] ?? '').toString(),
      chapterId: (json['chapterId'] ?? '').toString(),
      chapterTitle: (json['chapterTitle'] ?? '').toString(),
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      summary: ComicSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
      ),
    );
  }
}

/// Local favorite folder.
class FavoriteFolder {
  const FavoriteFolder({
    required this.id,
    required this.name,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final int createdAtMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAtMs': createdAtMs,
  };

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) {
    return FavoriteFolder(
      id: (json['id'] ?? 'default').toString(),
      name: (json['name'] ?? '默认收藏').toString(),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Saved favorite comic entry.
class FavoriteEntry {
  const FavoriteEntry({
    required this.folderId,
    required this.addedAtMs,
    required this.summary,
  });

  final String folderId;
  final int addedAtMs;
  final ComicSummary summary;

  Map<String, dynamic> toJson() => {
    'folderId': folderId,
    'addedAtMs': addedAtMs,
    'summary': summary.toJson(),
  };

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) {
    return FavoriteEntry(
      folderId: (json['folderId'] ?? 'default').toString(),
      addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
      summary: ComicSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
      ),
    );
  }
}
