import 'package:flutter/material.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/theme/md3_tokens.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../../domain/models/reader_models.dart';
import '../../prism/prism_navigation_dock.dart';
import '../../prism/prism_segmented_control.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/jm_descrambled_image.dart';
import '../../widgets/md3_segmented_list.dart';
import '../detail/comic_detail_screen.dart';
import '../reader/comic_reader_screen.dart';
import 'jm_batch_import_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.deps,
    required this.onSearchTag,
    required this.onOpenSettings,
    this.onExplore,
  });

  final AppDependencies deps;
  final void Function(ComicSource source, String tagQuery) onSearchTag;
  final VoidCallback onOpenSettings;
  final VoidCallback? onExplore;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _CloudPageCache {
  const _CloudPageCache({
    required this.items,
    required this.page,
    required this.hasMore,
    this.nextCursor,
    this.totalText = '',
  });

  final List<ComicSummary> items;
  final int page;
  final bool hasMore;
  final String? nextCursor;
  final String totalText;
}

class _CloudFavoritesCache {
  final Map<ComicSource, List<CloudFavoriteFolder>> folders = {};
  final Map<String, _CloudPageCache> pages = {};
  String? jmIdentity;
  String? ehIdentity;
  ComicSource selectedSource = ComicSource.jmcomic;
  String jmFolderId = '0';
  String ehFolderId = '';
  String jmSort = 'mr';

  static String keyFor(ComicSource source, String folderId, String sort) {
    return source == ComicSource.jmcomic
        ? 'jmcomic|$folderId|$sort'
        : 'ehentai|$folderId';
  }
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  static final Expando<_CloudFavoritesCache> _cacheByStore =
      Expando<_CloudFavoritesCache>('hedone_cloud_favorites_cache');

  late final TabController _tabController;

  String _selectedFolderId = 'all';
  SourceScope _localSourceFilter = SourceScope.all;

  // Cloud favorites runtime flags
  bool _cloudLoading = false;
  bool _cloudLoadingMore = false;
  String? _cloudError;
  int _cloudRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    widget.deps.store.addListener(_onStoreChanged);
    _syncCacheIdentities();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    widget.deps.store.removeListener(_onStoreChanged);
    _tabController.dispose();
    super.dispose();
  }

  _CloudFavoritesCache _cache() {
    var cache = _cacheByStore[widget.deps.store];
    if (cache == null) {
      cache = _CloudFavoritesCache();
      _cacheByStore[widget.deps.store] = cache;
    }
    return cache;
  }

  String _sourceIdentity(ComicSource source) {
    final store = widget.deps.store;
    if (source == ComicSource.jmcomic) {
      if (!store.isJmLoggedIn) return '';
      return 'jm:${store.jmUsername}:${store.jmJwtToken.hashCode}:${store.jmAvsCookie.hashCode}';
    } else {
      if (!store.isEhLoggedIn) return '';
      return 'eh:${store.ehMemberId}:${store.ehUseExHentai}';
    }
  }

  void _syncCacheIdentities() {
    final cache = _cache();
    final jmId = _sourceIdentity(ComicSource.jmcomic);
    if (cache.jmIdentity != null && cache.jmIdentity != jmId) {
      cache.folders.remove(ComicSource.jmcomic);
      cache.pages.removeWhere((k, _) => k.startsWith('jmcomic|'));
      cache.jmFolderId = '0';
    }
    cache.jmIdentity = jmId;

    final ehId = _sourceIdentity(ComicSource.ehentai);
    if (cache.ehIdentity != null && cache.ehIdentity != ehId) {
      cache.folders.remove(ComicSource.ehentai);
      cache.pages.removeWhere((k, _) => k.startsWith('ehentai|'));
      cache.ehFolderId = '';
    }
    cache.ehIdentity = ehId;
  }

  String _activeFolderId(_CloudFavoritesCache cache, ComicSource source) {
    return source == ComicSource.jmcomic ? cache.jmFolderId : cache.ehFolderId;
  }

  String _activeCacheKey(_CloudFavoritesCache cache) {
    final source = cache.selectedSource;
    return _CloudFavoritesCache.keyFor(
      source,
      _activeFolderId(cache, source),
      cache.jmSort,
    );
  }

  bool _isLoggedIn(ComicSource source) {
    return source == ComicSource.jmcomic
        ? widget.deps.store.isJmLoggedIn
        : widget.deps.store.isEhLoggedIn;
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.index == 1) {
      _ensureCloudLoaded();
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _syncCacheIdentities();
    setState(() {});
    if (_tabController.index == 1) {
      _ensureCloudLoaded();
    }
  }

  void _ensureCloudLoaded() {
    final cache = _cache();
    final source = cache.selectedSource;
    if (!_isLoggedIn(source) || _cloudLoading) return;
    final key = _activeCacheKey(cache);
    if (cache.pages.containsKey(key)) return;
    _loadCloudFavorites();
  }

  void _openDetail(ComicSummary item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicDetailScreen(
          deps: widget.deps,
          summary: item,
          onSearchTag: widget.onSearchTag,
        ),
      ),
    );
  }

  Future<void> _loadCloudFavorites({
    bool forceRefresh = false,
    bool loadMore = false,
  }) async {
    final cache = _cache();
    final source = cache.selectedSource;
    if (!_isLoggedIn(source)) return;

    final folderId = _activeFolderId(cache, source);
    final sort = cache.jmSort;
    final key = _CloudFavoritesCache.keyFor(source, folderId, sort);
    final existing = cache.pages[key];

    if (!forceRefresh && !loadMore && existing != null) {
      if (_cloudError != null && mounted) {
        setState(() => _cloudError = null);
      }
      return;
    }
    if (loadMore && (existing == null || !existing.hasMore || _cloudLoadingMore)) {
      return;
    }

    final reqId = ++_cloudRequestSeq;
    setState(() {
      if (loadMore) {
        _cloudLoadingMore = true;
      } else {
        _cloudLoading = true;
      }
      _cloudError = null;
    });

    try {
      final CloudFavoritesResult res;
      final nextPage = loadMore ? (existing!.page + 1) : 1;
      if (source == ComicSource.jmcomic) {
        res = await widget.deps.jmRepo.fetchCloudFavorites(
          page: nextPage,
          folderId: folderId,
          sort: sort,
        );
      } else {
        res = await widget.deps.ehRepo.fetchCloudFavorites(
          favCat: folderId,
          nextCursor: loadMore ? existing?.nextCursor : null,
        );
      }
      if (!mounted) return;

      if (res.folders.isNotEmpty) {
        cache.folders[source] = res.folders;
      }

      final mergedItems = <ComicSummary>[
        if (loadMore && existing != null) ...existing.items,
      ];
      final seen = mergedItems.map((e) => e.uniqueKey).toSet();
      for (final item in res.items) {
        if (seen.add(item.uniqueKey)) {
          mergedItems.add(item);
        }
      }

      cache.pages[key] = _CloudPageCache(
        items: mergedItems,
        page: nextPage,
        hasMore: res.hasMore,
        nextCursor: res.nextCursor,
        totalText: res.totalText.isNotEmpty
            ? res.totalText
            : (existing?.totalText ?? ''),
      );
      setState(() {
        if (reqId == _cloudRequestSeq) {
          _cloudError = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (reqId == _cloudRequestSeq) {
        if (loadMore) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载更多失败：$e')),
          );
        } else {
          setState(() => _cloudError = e.toString());
        }
      }
    } finally {
      if (mounted && reqId == _cloudRequestSeq) {
        setState(() {
          _cloudLoading = false;
          _cloudLoadingMore = false;
        });
      }
    }
  }

  Future<void> _createFolderDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入收藏夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.deps.store.createFavoriteFolder(name);
    }
  }

  Future<void> _deleteHistoryWithUndo(ReadingProgress progress) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.deps.store.removeHistoryItem(progress.uniqueKey);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已删除「${progress.summary.title}」的阅读记录'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => widget.deps.store.updateProgress(progress),
        ),
      ),
    );
  }

  void _openBatchImport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JmBatchImportScreen(
          deps: widget.deps,
          onSearchTag: widget.onSearchTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pageMargin = Md3Breakpoints.pageMargin(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '书架',
          style: Md3Typography.emphasized(theme.textTheme.titleLarge),
        ),
        actions: [
          IconButton(
            tooltip: '批量识别 JM 车牌号',
            onPressed: _openBatchImport,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
          const SizedBox(width: Md3Spacing.s4),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '本地收藏'),
            Tab(text: '云端收藏'),
            Tab(text: '阅读历史'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLocalFavoritesTab(pageMargin),
          _buildCloudFavoritesTab(pageMargin),
          _buildHistoryTab(pageMargin),
        ],
      ),
    );
  }

  Widget _buildLocalFavoritesTab(double pageMargin) {
    final folders = widget.deps.store.folders;
    final allFavs = widget.deps.store.favorites;
    final filtered = allFavs.where((f) {
      if (_selectedFolderId != 'all' && f.folderId != _selectedFolderId) {
        return false;
      }
      if (_localSourceFilter == SourceScope.jmcomic &&
          f.summary.source != ComicSource.jmcomic) {
        return false;
      }
      if (_localSourceFilter == SourceScope.ehentai &&
          f.summary.source != ComicSource.ehentai) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            pageMargin,
            Md3Spacing.s8,
            pageMargin,
            Md3Spacing.s4,
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: Md3Spacing.s8),
                        child: ChoiceChip(
                          selected: _selectedFolderId == 'all',
                          label: Text('全部 (${allFavs.length})'),
                          onSelected: (_) =>
                              setState(() => _selectedFolderId = 'all'),
                        ),
                      ),
                      ...folders.map((folder) {
                        final count = allFavs
                            .where((e) => e.folderId == folder.id)
                            .length;
                        return Padding(
                          padding: const EdgeInsets.only(right: Md3Spacing.s8),
                          child: InputChip(
                            selected: _selectedFolderId == folder.id,
                            label: Text('${folder.name} ($count)'),
                            onPressed: () =>
                                setState(() => _selectedFolderId = folder.id),
                            onDeleted: folder.id == 'default'
                                ? null
                                : () {
                                    if (_selectedFolderId == folder.id) {
                                      _selectedFolderId = 'all';
                                    }
                                    widget.deps.store
                                        .deleteFavoriteFolder(folder.id);
                                  },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '新建收藏夹',
                onPressed: _createFolderDialog,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            pageMargin,
            Md3Spacing.s2,
            pageMargin,
            Md3Spacing.s8,
          ),
          child: Row(
            children: SourceScope.values.map((s) {
              return Padding(
                padding: const EdgeInsets.only(right: Md3Spacing.s8),
                child: FilterChip(
                  selected: _localSourceFilter == s,
                  label: Text(s.label),
                  onSelected: (_) => setState(() => _localSourceFilter = s),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? AsyncStatePlaceholder(
                  isLoading: false,
                  error: null,
                  isEmpty: true,
                  emptyTitle: allFavs.isEmpty ? '收藏夹为空' : '当前筛选条件下暂无收藏',
                  emptySubtitle: allFavs.isEmpty
                      ? '在漫画详情页点击爱心即可收藏到本地或云端'
                      : '可以切换收藏夹或重置数据源筛选',
                  actionLabel: allFavs.isEmpty
                      ? (widget.onExplore != null ? '去发现漫画' : null)
                      : '重置筛选',
                  onAction: allFavs.isEmpty
                      ? widget.onExplore
                      : () => setState(() {
                            _selectedFolderId = 'all';
                            _localSourceFilter = SourceScope.all;
                          }),
                  onRetry: _noop,
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    pageMargin,
                    Md3Spacing.s4,
                    pageMargin,
                    Md3Spacing.s24 + PrismBottomInsetScope.of(context),
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: Md3Spacing.cardVerticalGap,
                    crossAxisSpacing: Md3Spacing.cardHorizontalGap,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, idx) {
                    final entry = filtered[idx];
                    return ComicCard(
                      comic: entry.summary,
                      httpClient: widget.deps.httpClient,
                      progress: widget.deps.store.getProgress(
                        entry.summary.source,
                        entry.summary.id,
                      ),
                      onTap: () => _openDetail(entry.summary),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCloudFavoritesTab(double pageMargin) {
    final cache = _cache();
    final source = cache.selectedSource;
    final loggedIn = _isLoggedIn(source);
    final folders = cache.folders[source] ?? const <CloudFavoriteFolder>[];
    final activeFolderId = _activeFolderId(cache, source);
    final key = _activeCacheKey(cache);
    final pageCache = cache.pages[key];
    final items = pageCache?.items ?? const <ComicSummary>[];
    final allFolderId = source == ComicSource.jmcomic ? '0' : '';

    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pageMargin,
                Md3Spacing.s12,
                pageMargin,
                Md3Spacing.s8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PrismSegmentedControl<ComicSource>(
                      value: source,
                      onChanged: (next) {
                        setState(() {
                          cache.selectedSource = next;
                          _cloudError = null;
                        });
                        _ensureCloudLoaded();
                      },
                      segments: const [
                        (ComicSource.jmcomic, 'JMComic 云收藏'),
                        (ComicSource.ehentai, 'E-Hentai 云收藏'),
                      ],
                    ),
                  ),
                  const SizedBox(width: Md3Spacing.s8),
                  IconButton(
                    tooltip: '同步云端收藏',
                    onPressed: !loggedIn || _cloudLoading
                        ? null
                        : () => _loadCloudFavorites(forceRefresh: true),
                    icon: const Icon(Icons.sync_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (loggedIn) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              pageMargin,
              Md3Spacing.s2,
              pageMargin,
              Md3Spacing.s4,
            ),
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: Md3Spacing.s8),
                    child: ChoiceChip(
                      selected: activeFolderId == allFolderId,
                      label: const Text('全部'),
                      onSelected: (_) {
                        setState(() {
                          if (source == ComicSource.jmcomic) {
                            cache.jmFolderId = '0';
                          } else {
                            cache.ehFolderId = '';
                          }
                          _cloudError = null;
                        });
                        _ensureCloudLoaded();
                      },
                    ),
                  ),
                  ...folders.map((folder) {
                    final label = folder.count != null
                        ? '${folder.name} (${folder.count})'
                        : folder.name;
                    return Padding(
                      padding: const EdgeInsets.only(right: Md3Spacing.s8),
                      child: ChoiceChip(
                        selected: activeFolderId == folder.id,
                        label: Text(label),
                        onSelected: (_) {
                          setState(() {
                            if (source == ComicSource.jmcomic) {
                              cache.jmFolderId = folder.id;
                            } else {
                              cache.ehFolderId = folder.id;
                            }
                            _cloudError = null;
                          });
                          _ensureCloudLoaded();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          if (source == ComicSource.jmcomic || (pageCache?.totalText.isNotEmpty ?? false))
            Padding(
              padding: EdgeInsets.fromLTRB(
                pageMargin,
                Md3Spacing.s2,
                pageMargin,
                Md3Spacing.s8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: pageCache != null
                        ? Text(
                            pageCache.totalText.isNotEmpty
                                ? pageCache.totalText
                                : '已加载 ${items.length} 部',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Md3Typography.tabularFigures(
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (source == ComicSource.jmcomic) ...[
                    const SizedBox(width: Md3Spacing.s8),
                    ChoiceChip(
                      selected: cache.jmSort == 'mr',
                      label: const Text('收藏时间'),
                      onSelected: (_) {
                        if (cache.jmSort == 'mr') return;
                        setState(() {
                          cache.jmSort = 'mr';
                          _cloudError = null;
                        });
                        _ensureCloudLoaded();
                      },
                    ),
                    const SizedBox(width: Md3Spacing.s8),
                    ChoiceChip(
                      selected: cache.jmSort == 'mp',
                      label: const Text('更新时间'),
                      onSelected: (_) {
                        if (cache.jmSort == 'mp') return;
                        setState(() {
                          cache.jmSort = 'mp';
                          _cloudError = null;
                        });
                        _ensureCloudLoaded();
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
        Expanded(
          child: !loggedIn
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Md3Spacing.s24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_circle_outlined, size: 48),
                        const SizedBox(height: Md3Spacing.s12),
                        Text(
                          source == ComicSource.jmcomic
                              ? '尚未登录 JMComic 账号'
                              : '尚未登录 E-Hentai 账号',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: Md3Spacing.s12),
                        FilledButton.icon(
                          onPressed: widget.onOpenSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('前往设置登录'),
                        ),
                      ],
                    ),
                  ),
                )
              : items.isEmpty
                  ? AsyncStatePlaceholder(
                      isLoading: _cloudLoading || pageCache == null && _cloudError == null,
                      error: _cloudError,
                      isEmpty: true,
                      useSkeletonOnLoad: true,
                      emptyTitle: '当前收藏夹暂无云端收藏',
                      emptySubtitle: '可切换其他云端收藏夹或下拉刷新同步',
                      actionLabel: '重新同步',
                      onAction: () => _loadCloudFavorites(forceRefresh: true),
                      onRetry: () => _loadCloudFavorites(forceRefresh: true),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadCloudFavorites(forceRefresh: true),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              pageMargin,
                              Md3Spacing.s4,
                              pageMargin,
                              Md3Spacing.s12,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 190,
                                mainAxisSpacing: Md3Spacing.cardVerticalGap,
                                crossAxisSpacing: Md3Spacing.cardHorizontalGap,
                                childAspectRatio: 0.62,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (_, idx) {
                                  final item = items[idx];
                                  return ComicCard(
                                    comic: item,
                                    httpClient: widget.deps.httpClient,
                                    progress: widget.deps.store
                                        .getProgress(item.source, item.id),
                                    onTap: () => _openDetail(item),
                                  );
                                },
                                childCount: items.length,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                pageMargin,
                                Md3Spacing.s4,
                                pageMargin,
                                Md3Spacing.s24 + PrismBottomInsetScope.of(context),
                              ),
                              child: Center(
                                child: (pageCache?.hasMore ?? false)
                                    ? FilledButton.tonalIcon(
                                        onPressed: _cloudLoadingMore
                                            ? null
                                            : () => _loadCloudFavorites(
                                                loadMore: true,
                                              ),
                                        icon: _cloudLoadingMore
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.expand_more_rounded,
                                              ),
                                        label: Text(
                                          _cloudLoadingMore
                                              ? '加载中...'
                                              : '加载更多',
                                        ),
                                      )
                                    : Text(
                                        '已显示全部云端收藏 (${items.length})',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(double pageMargin) {
    final items = widget.deps.store.historyList;
    if (items.isEmpty) {
      return AsyncStatePlaceholder(
        isLoading: false,
        error: null,
        isEmpty: true,
        emptyTitle: '暂无阅读记录',
        emptySubtitle: '阅读过的漫画会自动记录章节和页码进度',
        actionLabel: widget.onExplore != null ? '去发现漫画' : null,
        onAction: widget.onExplore,
        onRetry: _noop,
      );
    }

    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pageMargin,
                Md3Spacing.s8,
                pageMargin,
                Md3Spacing.s4,
              ),
              child: Row(
                children: [
                  Text(
                    '共 ${items.length} 条阅读记录',
                    style: Md3Typography.tabularFigures(
                      Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('清空历史记录'),
                          content: const Text('确定清空所有阅读进度记录吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await widget.deps.store.clearHistory();
                      }
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('清空'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              pageMargin,
              Md3Spacing.s4,
              pageMargin,
              Md3Spacing.s24 + PrismBottomInsetScope.of(context),
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Md3SegmentedListGroup(
                    children: items.map((progress) {
                      return _HistoryListItem(
                        progress: progress,
                        deps: widget.deps,
                        onTapResume: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ComicReaderScreen(
                                deps: widget.deps,
                                summary: progress.summary,
                                initialChapter: ComicChapter(
                                  id: progress.chapterId,
                                  title: progress.chapterTitle,
                                  sort: '1',
                                  index: 0,
                                ),
                                initialPageIndex: progress.pageIndex,
                              ),
                            ),
                          );
                        },
                        onTapDetail: () => _openDetail(progress.summary),
                        onDelete: () => _deleteHistoryWithUndo(progress),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryListItem extends StatelessWidget {
  const _HistoryListItem({
    required this.progress,
    required this.deps,
    required this.onTapResume,
    required this.onTapDetail,
    required this.onDelete,
  });

  final ReadingProgress progress;
  final AppDependencies deps;
  final VoidCallback onTapResume;
  final VoidCallback onTapDetail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = progress.totalPages > 0
        ? ((progress.pageIndex + 1) / progress.totalPages).clamp(0.0, 1.0)
        : 0.0;

    return InkWell(
      onTap: onTapResume,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Md3Spacing.s16,
          Md3Spacing.s12,
          Md3Spacing.s8,
          Md3Spacing.s12,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Md3Shapes.small),
              child: SizedBox(
                width: 60,
                height: 84,
                child: HedoneImage(
                  url: progress.summary.coverUrl,
                  httpClient: deps.httpClient,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: Md3Spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Md3Spacing.s8,
                          vertical: Md3Spacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(
                            Md3Shapes.extraSmall,
                          ),
                        ),
                        child: Text(
                          progress.summary.badgeLabel,
                          style: Md3Typography.emphasized(
                            theme.textTheme.labelSmall?.copyWith(
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Md3Spacing.s8),
                      Expanded(
                        child: Text(
                          progress.summary.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Md3Typography.emphasized(
                            theme.textTheme.titleSmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Md3Spacing.s8),
                  Text(
                    '${progress.chapterTitle} · 第 ${progress.pageIndex + 1} / ${progress.totalPages} 页',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Md3Typography.tabularFigures(
                      theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: Md3Spacing.s8),
                  LinearProgressIndicator(value: ratio),
                ],
              ),
            ),
            IconButton(
              tooltip: '详情',
              onPressed: onTapDetail,
              icon: const Icon(Icons.info_outline_rounded),
            ),
            IconButton(
              tooltip: '删除记录',
              onPressed: onDelete,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}
