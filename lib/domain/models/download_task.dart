import 'comic_item.dart';
import 'comic_source.dart';

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed;

  String get label => switch (this) {
    DownloadStatus.queued => '队列中',
    DownloadStatus.downloading => '下载中',
    DownloadStatus.paused => '已暂停',
    DownloadStatus.completed => '已完成',
    DownloadStatus.failed => '失败',
  };

  static DownloadStatus fromString(String? value) {
    return DownloadStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DownloadStatus.queued,
    );
  }
}

class DownloadPageAsset {
  const DownloadPageAsset({
    required this.pageNumber,
    required this.localPath,
    this.imageUrl,
    this.ehPageToken,
    this.ehPageUrl,
    this.completed = false,
  });

  final int pageNumber;
  final String localPath;
  final String? imageUrl;
  final String? ehPageToken;
  final String? ehPageUrl;
  final bool completed;

  DownloadPageAsset copyWith({
    String? imageUrl,
    String? localPath,
    String? ehPageToken,
    String? ehPageUrl,
    bool? completed,
  }) {
    return DownloadPageAsset(
      pageNumber: pageNumber,
      localPath: localPath ?? this.localPath,
      imageUrl: imageUrl ?? this.imageUrl,
      ehPageToken: ehPageToken ?? this.ehPageToken,
      ehPageUrl: ehPageUrl ?? this.ehPageUrl,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'pageNumber': pageNumber,
    'localPath': localPath,
    'imageUrl': imageUrl,
    'ehPageToken': ehPageToken,
    'ehPageUrl': ehPageUrl,
    'completed': completed,
  };

  factory DownloadPageAsset.fromJson(Map<String, dynamic> json) {
    return DownloadPageAsset(
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 1,
      localPath: (json['localPath'] ?? '').toString(),
      imageUrl: json['imageUrl']?.toString(),
      ehPageToken: json['ehPageToken']?.toString(),
      ehPageUrl: json['ehPageUrl']?.toString(),
      completed: json['completed'] == true,
    );
  }
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.source,
    required this.summary,
    required this.chapterId,
    required this.chapterTitle,
    required this.scrambleId,
    required this.status,
    required this.downloadedCount,
    required this.totalCount,
    required this.createdAtMs,
    required this.pages,
    this.errorMessage,
  });

  final String id;
  final ComicSource source;
  final ComicSummary summary;
  final String chapterId;
  final String chapterTitle;
  final int scrambleId;
  final DownloadStatus status;
  final int downloadedCount;
  final int totalCount;
  final int createdAtMs;
  final List<DownloadPageAsset> pages;
  final String? errorMessage;

  double get progress => totalCount <= 0 ? 0 : downloadedCount / totalCount;

  DownloadTask copyWith({
    DownloadStatus? status,
    int? downloadedCount,
    int? totalCount,
    List<DownloadPageAsset>? pages,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DownloadTask(
      id: id,
      source: source,
      summary: summary,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      scrambleId: scrambleId,
      status: status ?? this.status,
      downloadedCount: downloadedCount ?? this.downloadedCount,
      totalCount: totalCount ?? this.totalCount,
      createdAtMs: createdAtMs,
      pages: pages ?? this.pages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source.name,
    'summary': summary.toJson(),
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'scrambleId': scrambleId,
    'status': status.name,
    'downloadedCount': downloadedCount,
    'totalCount': totalCount,
    'createdAtMs': createdAtMs,
    'pages': pages.map((e) => e.toJson()).toList(),
    'errorMessage': errorMessage,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: (json['id'] ?? '').toString(),
      source: ComicSource.fromString(json['source']?.toString()),
      summary: ComicSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
      ),
      chapterId: (json['chapterId'] ?? '').toString(),
      chapterTitle: (json['chapterTitle'] ?? '').toString(),
      scrambleId: (json['scrambleId'] as num?)?.toInt() ?? 220980,
      status: DownloadStatus.fromString(json['status']?.toString()),
      downloadedCount: (json['downloadedCount'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      pages: (json['pages'] as List?)
              ?.map((e) => DownloadPageAsset.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList() ??
          const [],
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}
