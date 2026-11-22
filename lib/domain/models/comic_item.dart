import 'comic_source.dart';

/// Lightweight comic summary item shared across Explore, Search, Library, and History.
class ComicSummary {
  const ComicSummary({
    required this.id,
    required this.source,
    required this.title,
    required this.coverUrl,
    this.token = '',
    this.subtitle = '',
    this.category = '',
    this.author = '',
    this.rating,
    this.pageCount,
    this.posted = '',
    this.tags = const [],
    this.isExHentai = false,
    this.liked = false,
    this.isFavorite = false,
  });

  final String id;
  final ComicSource source;
  final String token;
  final String title;
  final String subtitle;
  final String coverUrl;
  final String category;
  final String author;
  final double? rating;
  final int? pageCount;
  final String posted;
  final List<String> tags;
  final bool isExHentai;
  final bool liked;
  final bool isFavorite;

  String get uniqueKey => '${source.name}:$id';

  String get badgeLabel =>
      source == ComicSource.ehentai && isExHentai ? 'ExH' : source.shortLabel;

  ComicSummary copyWith({
    String? id,
    ComicSource? source,
    String? token,
    String? title,
    String? subtitle,
    String? coverUrl,
    String? category,
    String? author,
    double? rating,
    int? pageCount,
    String? posted,
    List<String>? tags,
    bool? isExHentai,
    bool? liked,
    bool? isFavorite,
  }) {
    return ComicSummary(
      id: id ?? this.id,
      source: source ?? this.source,
      token: token ?? this.token,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      coverUrl: coverUrl ?? this.coverUrl,
      category: category ?? this.category,
      author: author ?? this.author,
      rating: rating ?? this.rating,
      pageCount: pageCount ?? this.pageCount,
      posted: posted ?? this.posted,
      tags: tags ?? this.tags,
      isExHentai: isExHentai ?? this.isExHentai,
      liked: liked ?? this.liked,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source.name,
    'token': token,
    'title': title,
    'subtitle': subtitle,
    'coverUrl': coverUrl,
    'category': category,
    'author': author,
    'rating': rating,
    'pageCount': pageCount,
    'posted': posted,
    'tags': tags,
    'isExHentai': isExHentai,
    'liked': liked,
    'isFavorite': isFavorite,
  };

  factory ComicSummary.fromJson(Map<String, dynamic> json) {
    return ComicSummary(
      id: (json['id'] ?? '').toString(),
      source: ComicSource.fromString(json['source']?.toString()),
      token: (json['token'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toDouble(),
      pageCount: (json['pageCount'] as num?)?.toInt(),
      posted: (json['posted'] ?? '').toString(),
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      isExHentai: json['isExHentai'] == true,
      liked: json['liked'] == true,
      isFavorite: json['isFavorite'] == true,
    );
  }
}

/// Chapter or episode inside a comic (primarily for JMComic multi-chapter works).
class ComicChapter {
  const ComicChapter({
    required this.id,
    required this.title,
    required this.sort,
    required this.index,
  });

  final String id;
  final String title;
  final String sort;
  final int index;
}

/// Comment entry on a comic or gallery detail page.
class ComicComment {
  const ComicComment({
    required this.id,
    required this.author,
    required this.content,
    required this.postedAt,
    this.avatarUrl = '',
    this.score = '',
    this.level = '',
  });

  final String id;
  final String author;
  final String content;
  final String postedAt;
  final String avatarUrl;
  final String score;
  final String level;
}

/// Preview thumbnail entry for E-Hentai galleries (supports standalone & CSS sprite sheets).
class EhPreviewItem {
  const EhPreviewItem({
    required this.pageNumber,
    required this.pageToken,
    required this.pageUrl,
    required this.thumbUrl,
    this.isSprite = false,
    this.xOffset = 0,
    this.yOffset = 0,
    this.width = 0,
    this.height = 0,
  });

  final int pageNumber;
  final String pageToken;
  final String pageUrl;
  final String thumbUrl;
  final bool isSprite;
  final int xOffset;
  final int yOffset;
  final int width;
  final int height;
}

/// Complete detail model for a comic / gallery.
class ComicDetail {
  const ComicDetail({
    required this.summary,
    this.titleJpn = '',
    this.description = '',
    this.views = '',
    this.likes = '',
    this.favoriteCount = '',
    this.uploader = '',
    this.language = '',
    this.fileSize = '',
    this.posted = '',
    this.ratingCount = 0,
    this.isFavorited = false,
    this.isLiked = false,
    this.favoriteFolderName = '',
    this.tagGroups = const {},
    this.chapters = const [],
    this.previews = const [],
    this.totalPreviewPages = 1,
    this.comments = const [],
    this.related = const [],
  });

  final ComicSummary summary;
  final String titleJpn;
  final String description;
  final String views;
  final String likes;
  final String favoriteCount;
  final String uploader;
  final String language;
  final String fileSize;
  final String posted;
  final int ratingCount;
  final bool isFavorited;
  final bool isLiked;
  final String favoriteFolderName;
  final Map<String, List<String>> tagGroups;
  final List<ComicChapter> chapters;
  final List<EhPreviewItem> previews;
  final int totalPreviewPages;
  final List<ComicComment> comments;
  final List<ComicSummary> related;

  ComicDetail copyWith({
    ComicSummary? summary,
    bool? isFavorited,
    bool? isLiked,
    String? favoriteFolderName,
    List<EhPreviewItem>? previews,
    List<ComicComment>? comments,
  }) {
    return ComicDetail(
      summary: summary ?? this.summary,
      titleJpn: titleJpn,
      description: description,
      views: views,
      likes: likes,
      favoriteCount: favoriteCount,
      uploader: uploader,
      language: language,
      fileSize: fileSize,
      posted: posted,
      ratingCount: ratingCount,
      isFavorited: isFavorited ?? this.isFavorited,
      isLiked: isLiked ?? this.isLiked,
      favoriteFolderName: favoriteFolderName ?? this.favoriteFolderName,
      tagGroups: tagGroups,
      chapters: chapters,
      previews: previews ?? this.previews,
      totalPreviewPages: totalPreviewPages,
      comments: comments ?? this.comments,
      related: related,
    );
  }
}

/// Paginated list response shared by both sources.
class ComicListResult {
  const ComicListResult({
    required this.items,
    this.total = 0,
    this.hasMore = false,
    this.nextCursor,
    this.prevCursor,
    this.redirectAid,
    this.totalText = '',
  });

  final List<ComicSummary> items;
  final int total;
  final bool hasMore;
  final String? nextCursor;
  final String? prevCursor;
  final String? redirectAid;
  final String totalText;
}

/// Folder / category descriptor for cloud favorites (JMComic `folder_list` & E-Hentai `favcat`).
class CloudFavoriteFolder {
  const CloudFavoriteFolder({
    required this.id,
    required this.name,
    this.count,
  });

  final String id;
  final String name;
  final int? count;
}

/// Paginated cloud favorites response containing both items and cloud folders.
class CloudFavoritesResult {
  const CloudFavoritesResult({
    required this.items,
    this.folders = const [],
    this.total = 0,
    this.hasMore = false,
    this.nextCursor,
    this.totalText = '',
  });

  final List<ComicSummary> items;
  final List<CloudFavoriteFolder> folders;
  final int total;
  final bool hasMore;
  final String? nextCursor;
  final String totalText;
}

/// Category block returned by JMComic `/categories`.
class JmCategoryGroup {
  const JmCategoryGroup({
    required this.title,
    required this.tags,
  });

  final String title;
  final List<String> tags;
}

class JmCategoryItem {
  const JmCategoryItem({
    required this.id,
    required this.name,
    required this.slug,
  });

  final String id;
  final String name;
  final String slug;
}

class JmCategoriesData {
  const JmCategoriesData({
    required this.categories,
    required this.blocks,
  });

  final List<JmCategoryItem> categories;
  final List<JmCategoryGroup> blocks;
}

/// Weekly ranking period metadata for JMComic.
class JmWeekPeriod {
  const JmWeekPeriod({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class JmWeekType {
  const JmWeekType({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class JmWeekMeta {
  const JmWeekMeta({
    required this.periods,
    required this.types,
  });

  final List<JmWeekPeriod> periods;
  final List<JmWeekType> types;
}

/// Promotion section on JMComic home feed.
class JmPromoteSection {
  const JmPromoteSection({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<ComicSummary> items;
}
