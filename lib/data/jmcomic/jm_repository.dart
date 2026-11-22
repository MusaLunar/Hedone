import '../../core/storage/local_store.dart';
import '../../domain/models/comic_item.dart';
import '../../domain/models/comic_source.dart';
import '../../domain/models/reader_models.dart';
import 'jm_api_service.dart';

class JmChapterPayload {
  const JmChapterPayload({
    required this.chapterId,
    required this.title,
    required this.scrambleId,
    required this.pages,
  });

  final String chapterId;
  final String title;
  final int scrambleId;
  final List<ComicPageData> pages;
}

/// High-level JMComic3 repository mapping API payloads into unified domain models.
class JmRepository {
  JmRepository({
    required JmApiService api,
    required LocalStore store,
  }) : _api = api,
       _store = store;

  final JmApiService _api;
  final LocalStore _store;

  String coverUrl(String id) {
    final base = _store.jmImgHost.replaceAll(RegExp(r'/+$'), '');
    return '$base/media/albums/${id}_3x4.jpg';
  }

  ComicSummary _mapSummary(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString();
    final catMap = item['category'];
    final subCatMap = item['category_sub'];
    final catTitle = catMap is Map ? (catMap['title']?.toString() ?? '') : '';
    final subTitle = subCatMap is Map ? (subCatMap['title']?.toString() ?? '') : '';
    final categoryLabel = [catTitle, subTitle]
        .where((s) => s.isNotEmpty)
        .toSet()
        .join(' · ');

    final rawAuthor = item['author'];
    final author = rawAuthor is List
        ? rawAuthor.map((e) => e.toString()).join(', ')
        : (rawAuthor?.toString() ?? '');

    final rawImage = (item['image'] ?? '').toString();
    final resolvedCover = rawImage.startsWith('http')
        ? rawImage
        : coverUrl(id);

    return ComicSummary(
      id: id,
      source: ComicSource.jmcomic,
      title: (item['name'] ?? '').toString().trim(),
      subtitle: author,
      coverUrl: resolvedCover,
      category: categoryLabel,
      author: author,
      posted: (item['adddate'] ?? '').toString(),
      liked: item['liked'] == true,
      isFavorite: item['is_favorite'] == true,
    );
  }

  Future<List<JmPromoteSection>> fetchPromote() async {
    await _api.ensureInitialized();
    final raw = await _api.get('promote');
    if (raw is! List) return const [];

    final sections = <JmPromoteSection>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final content = map['content'];
      if (content is! List || content.isEmpty) continue;
      final items = content
          .whereType<Map>()
          .map((e) => _mapSummary(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
      if (items.isEmpty) continue;
      sections.add(
        JmPromoteSection(
          id: (map['id'] ?? '').toString(),
          title: (map['title'] ?? '精选推荐').toString(),
          items: items,
        ),
      );
    }
    return sections;
  }

  Future<ComicListResult> fetchLatest({int page = 1}) async {
    await _api.ensureInitialized();
    final raw = await _api.get('latest', queryParameters: {'page': page});
    return _parseComicList(raw);
  }

  Future<JmCategoriesData> fetchCategories() async {
    await _api.ensureInitialized();
    final raw = await _api.get('categories');
    if (raw is! Map) {
      return const JmCategoriesData(categories: [], blocks: []);
    }
    final map = Map<String, dynamic>.from(raw);
    final categories = (map['categories'] as List? ?? const [])
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          return JmCategoryItem(
            id: (m['id'] ?? '').toString(),
            name: (m['name'] ?? '').toString(),
            slug: (m['slug'] ?? '').toString(),
          );
        })
        .toList();

    final blocks = (map['blocks'] as List? ?? const [])
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          final tags = (m['content'] as List? ?? const [])
              .map((t) => t.toString())
              .where((t) => t.isNotEmpty)
              .toList();
          return JmCategoryGroup(
            title: (m['title'] ?? '').toString(),
            tags: tags,
          );
        })
        .where((g) => g.tags.isNotEmpty)
        .toList();

    return JmCategoriesData(categories: categories, blocks: blocks);
  }

  Future<ComicListResult> fetchCategoryFilter({
    String categorySlug = '0',
    String sort = 'mr',
    int page = 1,
  }) async {
    await _api.ensureInitialized();
    final raw = await _api.get(
      'categories/filter',
      queryParameters: {
        'page': page,
        'o': sort,
        'c': categorySlug,
      },
    );
    return _parseComicList(raw);
  }

  Future<JmWeekMeta> fetchWeeklyMeta() async {
    await _api.ensureInitialized();
    final raw = await _api.get('week');
    if (raw is! Map) {
      return const JmWeekMeta(periods: [], types: []);
    }
    final map = Map<String, dynamic>.from(raw);
    final periods = (map['categories'] as List? ?? const [])
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          final title = (m['title'] ?? '').toString().trim();
          final time = (m['time'] ?? '').toString().trim();
          return JmWeekPeriod(
            id: (m['id'] ?? '').toString(),
            label: title.isNotEmpty ? '$title ($time)' : time,
          );
        })
        .toList();

    final types = (map['type'] as List? ?? const [])
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          final id = (m['id'] ?? '').toString();
          var label = (m['title'] ?? '').toString().trim();
          if (label.isEmpty && id == 'hanman') label = '韩漫';
          return JmWeekType(id: id, label: label.isEmpty ? id : label);
        })
        .toList();

    return JmWeekMeta(periods: periods, types: types);
  }

  Future<ComicListResult> fetchWeeklyList({
    required String categoryId,
    required String typeId,
    int page = 0,
  }) async {
    await _api.ensureInitialized();
    final raw = await _api.get(
      'week/filter',
      queryParameters: {
        'id': categoryId,
        'type': typeId,
        'page': page,
      },
    );
    return _parseComicList(raw);
  }

  Future<ComicListResult> search({
    required String query,
    String sort = 'mv',
    int page = 1,
  }) async {
    await _api.ensureInitialized();
    final raw = await _api.get(
      'search',
      queryParameters: {
        'search_query': query.trim(),
        'o': sort,
        'page': page,
      },
    );
    return _parseComicList(raw);
  }

  Future<List<String>> fetchHotTags() async {
    await _api.ensureInitialized();
    final raw = await _api.get('hot_tags');
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  Future<ComicDetail> fetchDetail(String id) async {
    await _api.ensureInitialized();
    final raw = await _api.get('album', queryParameters: {'id': id});
    if (raw is! Map) {
      throw const JmApiException('漫画详情数据为空');
    }
    final map = Map<String, dynamic>.from(raw);
    final albumId = (map['id'] ?? id).toString();
    final authors = _stringList(map['author']);
    final tags = _stringList(map['tags']);
    final works = _stringList(map['works']);
    final actors = _stringList(map['actors']);

    final tagGroups = <String, List<String>>{};
    if (authors.isNotEmpty) tagGroups['作者'] = authors;
    if (works.isNotEmpty) tagGroups['原作'] = works;
    if (actors.isNotEmpty) tagGroups['角色'] = actors;
    if (tags.isNotEmpty) tagGroups['标签'] = tags;

    final rawSeries = map['series'] as List? ?? const [];
    final chapters = <ComicChapter>[];
    for (var i = 0; i < rawSeries.length; i++) {
      final entry = rawSeries[i];
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final sortStr = (m['sort'] ?? '${i + 1}').toString();
      final nameStr = (m['name'] ?? '').toString().trim();
      chapters.add(
        ComicChapter(
          id: (m['id'] ?? '').toString(),
          title: nameStr.isNotEmpty ? '第$sortStr话 $nameStr' : '第$sortStr话',
          sort: sortStr,
          index: i,
        ),
      );
    }
    if (chapters.isEmpty) {
      chapters.add(
        ComicChapter(
          id: albumId,
          title: '全一话',
          sort: '1',
          index: 0,
        ),
      );
    }

    final related = (map['related_list'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => _mapSummary(Map<String, dynamic>.from(e)))
        .toList();

    final summary = ComicSummary(
      id: albumId,
      source: ComicSource.jmcomic,
      title: (map['name'] ?? '').toString().trim(),
      subtitle: authors.join(', '),
      coverUrl: coverUrl(albumId),
      author: authors.join(', '),
      pageCount: int.tryParse((map['total_photos'] ?? '').toString()),
      posted: (map['addtime'] ?? '').toString(),
      tags: tags,
      liked: map['liked'] == true,
      isFavorite: map['is_favorite'] == true,
    );

    List<ComicComment> comments = const [];
    try {
      comments = await fetchComments(comicId: albumId, page: 1);
    } catch (_) {}

    return ComicDetail(
      summary: summary,
      description: (map['description'] ?? '').toString().trim(),
      views: (map['total_views'] ?? '').toString(),
      likes: (map['likes'] ?? '').toString(),
      posted: (map['addtime'] ?? '').toString(),
      isFavorited: map['is_favorite'] == true,
      isLiked: map['liked'] == true,
      tagGroups: tagGroups,
      chapters: chapters,
      comments: comments,
      related: related,
    );
  }

  Future<JmChapterPayload> fetchChapterPages(String chapterId) async {
    await _api.ensureInitialized();
    dynamic raw;
    try {
      raw = await _api.get('comic_read', queryParameters: {'id': chapterId});
    } catch (_) {
      raw = await _api.get('chapter', queryParameters: {'id': chapterId});
    }
    if (raw is! Map) {
      throw const JmApiException('章节图片数据为空');
    }
    final map = Map<String, dynamic>.from(raw);
    final cid = (map['id'] ?? chapterId).toString();
    final scrambleId =
        int.tryParse((map['scramble_id'] ?? '220980').toString()) ?? 220980;
    final title = (map['name'] ?? '').toString().trim();
    final rawImages = map['images'] as List? ?? const [];

    final base = _store.jmImgHost.replaceAll(RegExp(r'/+$'), '');
    final pages = <ComicPageData>[];
    for (var i = 0; i < rawImages.length; i++) {
      final entry = rawImages[i];
      String url;
      int pageNumber = i + 1;
      if (entry is Map) {
        url = (entry['image'] ?? '').toString();
        pageNumber = (entry['page'] as num?)?.toInt() ?? (i + 1);
      } else {
        final fileName = entry.toString();
        url = fileName.startsWith('http')
            ? fileName
            : '$base/media/photos/$cid/$fileName';
      }
      pages.add(
        ComicPageData(
          pageIndex: i,
          pageNumber: pageNumber,
          imageUrl: url,
          chapterId: cid,
          scrambleId: scrambleId,
          isScrambled: true,
        ),
      );
    }

    return JmChapterPayload(
      chapterId: cid,
      title: title,
      scrambleId: scrambleId,
      pages: pages,
    );
  }

  Future<List<ComicComment>> fetchComments({
    required String comicId,
    int page = 1,
  }) async {
    await _api.ensureInitialized();
    final raw = await _api.get(
      'forum',
      queryParameters: {
        'page': page,
        'mode': 'manhua',
        'aid': comicId,
      },
    );
    if (raw is! Map) return const [];
    final list = raw['list'] as List? ?? const [];
    return list.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      final expInfo = m['expinfo'] is Map
          ? Map<String, dynamic>.from(m['expinfo'] as Map)
          : const <String, dynamic>{};
      final rawContent = (m['content'] ?? '').toString();
      final cleanContent = rawContent
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      final photo = (m['photo'] ?? '').toString();
      final avatarUrl = photo.isNotEmpty && !photo.startsWith('http')
          ? '${_store.jmImgHost}/media/users/$photo'
          : photo;

      return ComicComment(
        id: (m['CID'] ?? '').toString(),
        author: (m['nickname'] ?? m['username'] ?? '匿名').toString(),
        avatarUrl: avatarUrl,
        content: cleanContent,
        postedAt: (m['addtime'] ?? '').toString(),
        score: (m['likes'] ?? '').toString(),
        level: expInfo['level_name']?.toString() ?? '',
      );
    }).toList();
  }

  Future<void> login(String username, String password) async {
    await _api.ensureInitialized();
    final data = await _api.post(
      'login',
      fields: {
        'username': username.trim(),
        'password': password,
      },
    );
    if (data is! Map) {
      throw const JmApiException('登录响应格式错误');
    }
    final map = Map<String, dynamic>.from(data);
    await _store.setJmAuth(
      jwtToken: (map['jwttoken'] ?? '').toString(),
      avsCookie: (map['s'] ?? '').toString(),
      username: (map['username'] ?? username).toString(),
    );
  }

  Future<CloudFavoritesResult> fetchCloudFavorites({
    int page = 1,
    String folderId = '0',
    String sort = 'mr',
  }) async {
    await _api.ensureInitialized();
    final raw = await _api.get(
      'favorite',
      queryParameters: {
        'page': page,
        'folder_id': folderId,
        'o': sort,
      },
    );
    return parseCloudFavoritesResponse(raw, page: page);
  }

  /// Parses JMComic `/favorite` response preserving both comics and `folder_list`.
  CloudFavoritesResult parseCloudFavoritesResponse(
    dynamic raw, {
    int page = 1,
  }) {
    if (raw is List) {
      final listRes = _parseComicList(raw);
      return CloudFavoritesResult(
        items: listRes.items,
        folders: const [],
        total: listRes.total,
        hasMore: listRes.hasMore,
      );
    }
    if (raw is! Map) {
      return const CloudFavoritesResult(items: [], folders: []);
    }
    final map = Map<String, dynamic>.from(raw);
    final listRes = _parseComicList(map);
    final rawFolders = map['folder_list'] as List? ?? const [];
    final folders = <CloudFavoriteFolder>[];
    final seenIds = <String>{};
    for (final entry in rawFolders) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final fid = (m['FID'] ?? m['fid'] ?? '').toString().trim();
      final name = (m['name'] ?? '').toString().trim();
      if (fid.isEmpty || name.isEmpty || fid == '0' || seenIds.contains(fid)) {
        continue;
      }
      seenIds.add(fid);
      final countVal = int.tryParse((m['total'] ?? m['count'] ?? '').toString());
      folders.add(
        CloudFavoriteFolder(
          id: fid,
          name: name,
          count: countVal,
        ),
      );
    }

    final items = listRes.items;
    final total = listRes.total;
    final fetchedSoFar = (page - 1) * 20 + items.length;
    final hasMore = items.isNotEmpty &&
        (total > 0 ? fetchedSoFar < total : items.length >= 20);

    return CloudFavoritesResult(
      items: items,
      folders: folders,
      total: total,
      hasMore: hasMore,
      totalText: total > 0 ? '共 $total 部' : '',
    );
  }

  Future<bool> toggleCloudFavorite(String comicId) async {
    await _api.ensureInitialized();
    final raw = await _api.post('favorite', fields: {'aid': comicId});
    if (raw is Map) {
      final status = raw['status']?.toString();
      return status == 'ok' || raw['is_favorite'] == true;
    }
    return true;
  }

  Future<void> sendComment(String comicId, String comment) async {
    await _api.ensureInitialized();
    await _api.post(
      'comment',
      fields: {
        'aid': comicId,
        'comment': comment.trim(),
      },
    );
  }

  ComicListResult _parseComicList(dynamic raw) {
    if (raw is List) {
      final items = raw
          .whereType<Map>()
          .map((e) => _mapSummary(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
      return ComicListResult(items: items, total: items.length, hasMore: items.length >= 20);
    }
    if (raw is! Map) {
      return const ComicListResult(items: []);
    }
    final map = Map<String, dynamic>.from(raw);
    final rawList = (map['content'] ?? map['list']) as List? ?? const [];
    final items = rawList
        .whereType<Map>()
        .map((e) => _mapSummary(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList();
    final total = int.tryParse((map['total'] ?? '0').toString()) ?? items.length;
    final redirectAid = map['redirect_aid']?.toString();
    return ComicListResult(
      items: items,
      total: total,
      hasMore: items.length >= 20,
      redirectAid: (redirectAid != null && redirectAid.isNotEmpty && redirectAid != '0')
          ? redirectAid
          : null,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }
}
