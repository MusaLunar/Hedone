import 'package:flutter/material.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/theme/md3_tokens.dart';
import '../../../data/ehentai/eh_url.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../prism/prism_navigation_dock.dart';
import '../../prism/prism_segmented_control.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/comic_card.dart';
import '../detail/comic_detail_screen.dart';
import '../library/jm_batch_import_screen.dart';
import 'search_view_model.dart';

class SearchRequest {
  const SearchRequest({
    required this.source,
    required this.query,
    required this.token,
  });

  final ComicSource source;
  final String query;
  final int token;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.deps,
    this.externalRequest,
    required this.onSearchTag,
  });

  final AppDependencies deps;
  final SearchRequest? externalRequest;
  final void Function(ComicSource source, String tagQuery) onSearchTag;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final SearchViewModel _vm;
  late final TextEditingController _textController;
  late final TabController _discoveryTabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _vm = SearchViewModel(deps: widget.deps);
    _textController = TextEditingController();
    _discoveryTabController = TabController(length: 2, vsync: this);
    _vm.loadMeta();
    _scrollController.addListener(_onScroll);
    widget.deps.store.addListener(_onStoreChanged);
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final req = widget.externalRequest;
    if (req != null && req.token != oldWidget.externalRequest?.token) {
      _textController.text = req.query;
      _vm.setScope(
        req.source == ComicSource.jmcomic
            ? SourceScope.jmcomic
            : SourceScope.ehentai,
      );
      _vm.executeSearch(req.query);
    }
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onStoreChanged);
    _scrollController.dispose();
    _textController.dispose();
    _discoveryTabController.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 340) {
      _vm.loadMore();
    }
  }

  void _submitSearch(String raw) {
    final trimmed = raw.trim();
    final direct = SearchViewModel.detectDirectTarget(trimmed);
    if (direct != null) {
      _openDetail(
        ComicSummary(
          id: direct.id,
          token: direct.token,
          source: direct.source,
          title: direct.source == ComicSource.jmcomic
              ? 'JM${direct.id}'
              : '画廊 ${direct.id}',
          coverUrl: direct.source == ComicSource.jmcomic
              ? widget.deps.jmRepo.coverUrl(direct.id)
              : '',
          isExHentai: widget.deps.ehRepo.isExHentai,
        ),
      );
      return;
    }
    _vm.executeSearch(trimmed);
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

  void _applySuggestion(String fullTag) {
    final current = _textController.text.trim();
    final parts = current.isEmpty ? <String>[] : current.split(RegExp(r'\s+'));
    if (parts.isNotEmpty) {
      parts.removeLast();
    }
    parts.add(fullTag);
    final nextText = '${parts.join(' ')} ';
    _textController.text = nextText;
    _textController.selection = TextSelection.collapsed(offset: nextText.length);
    _vm.updateSuggestions('');
  }

  Future<void> _showEhAdvancedSheet() async {
    final minPageCtrl =
        TextEditingController(text: _vm.ehMinPages?.toString() ?? '');
    final maxPageCtrl =
        TextEditingController(text: _vm.ehMaxPages?.toString() ?? '');
    var tempMask = _vm.ehCategoryMask;
    var tempMinRating = _vm.ehMinRating;
    var tempExpunged = _vm.ehIncludeExpunged;
    var tempTorrents = _vm.ehOnlyTorrents;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final horizontal = Md3Breakpoints.pageMargin(
              MediaQuery.sizeOf(ctx).width,
            );
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  0,
                  horizontal,
                  Md3Spacing.s16 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'E-Hentai 高级筛选',
                          style: Md3Typography.emphasized(
                            Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: Md3Spacing.s12),
                        Text('包含分类', style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: Md3Spacing.s8),
                        Wrap(
                          spacing: Md3Spacing.s8,
                          runSpacing: Md3Spacing.s8,
                          children: EhUrl.categories.map((cat) {
                            final selected = (tempMask & cat.bit) != 0;
                            return FilterChip(
                              selected: selected,
                              label: Text(cat.label),
                              onSelected: (v) {
                                setModalState(() {
                                  tempMask = v
                                      ? (tempMask | cat.bit)
                                      : (tempMask & ~cat.bit);
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: Md3Spacing.s16),
                        Text('最低评分', style: Theme.of(ctx).textTheme.labelLarge),
                        const SizedBox(height: Md3Spacing.s8),
                        Wrap(
                          spacing: Md3Spacing.s8,
                          children: [null, 2, 3, 4, 5].map((r) {
                            return ChoiceChip(
                              selected: tempMinRating == r,
                              label: Text(r == null ? '不限' : '$r 星及以上'),
                              onSelected: (_) =>
                                  setModalState(() => tempMinRating = r),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: Md3Spacing.s16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: minPageCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '最少页数',
                                ),
                              ),
                            ),
                            const SizedBox(width: Md3Spacing.s12),
                            Expanded(
                              child: TextField(
                                controller: maxPageCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '最多页数',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Md3Spacing.s8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('包含已删除画廊 (Expunged)'),
                          value: tempExpunged,
                          onChanged: (v) =>
                              setModalState(() => tempExpunged = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('仅显示包含种子的画廊'),
                          value: tempTorrents,
                          onChanged: (v) =>
                              setModalState(() => tempTorrents = v),
                        ),
                        const SizedBox(height: Md3Spacing.s12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              final minP =
                                  int.tryParse(minPageCtrl.text.trim()) ?? 0;
                              final maxP =
                                  int.tryParse(maxPageCtrl.text.trim()) ?? 0;
                              final hasAdv = tempMinRating != null ||
                                  minP > 0 ||
                                  maxP > 0 ||
                                  tempExpunged ||
                                  tempTorrents;
                              _vm.updateEhFilters(
                                categoryMask: tempMask == 0
                                    ? EhUrl.allCategoryMask
                                    : tempMask,
                                advanced: hasAdv,
                                minRating: tempMinRating,
                                clearMinRating: tempMinRating == null,
                                minPages: minP,
                                maxPages: maxP,
                                includeExpunged: tempExpunged,
                                onlyTorrents: tempTorrents,
                              );
                              Navigator.pop(ctx);
                              _vm.setScope(SourceScope.ehentai);
                              _vm.executeSearch(_textController.text);
                            },
                            child: const Text('应用并搜索 E-Hentai'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
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
    final cs = theme.colorScheme;
    final pageMargin = Md3Breakpoints.pageMargin(MediaQuery.sizeOf(context).width);
    final directTarget = SearchViewModel.detectDirectTarget(_textController.text);

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              '搜索与分类',
              style: Md3Typography.emphasized(theme.textTheme.titleLarge),
            ),
            actions: [
              IconButton(
                tooltip: '批量识别 JM 车牌号',
                onPressed: _openBatchImport,
                icon: const Icon(Icons.playlist_add_rounded),
              ),
              IconButton(
                tooltip: 'E-Hentai 高级筛选',
                onPressed: _showEhAdvancedSheet,
                icon: Badge(
                  isLabelVisible: _vm.ehAdvanced ||
                      _vm.ehCategoryMask != EhUrl.allCategoryMask,
                  child: const Icon(Icons.filter_list_rounded),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // M3 SearchBar + Source Scope (max 720dp per search-bar spec)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pageMargin,
                      Md3Spacing.s4,
                      pageMargin,
                      Md3Spacing.s8,
                    ),
                    child: Column(
                      children: [
                        SearchBar(
                          controller: _textController,
                          hintText: '搜索关键词、标签（支持中文EH标签）、JM车号或EH链接',
                          leading: const Icon(Icons.search_rounded),
                          trailing: [
                            if (_textController.text.isNotEmpty)
                              IconButton(
                                tooltip: '清空',
                                onPressed: () {
                                  _textController.clear();
                                  _vm.clearResults();
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            IconButton(
                              tooltip: '搜索',
                              onPressed: () =>
                                  _submitSearch(_textController.text),
                              icon: const Icon(Icons.arrow_forward_rounded),
                            ),
                          ],
                          onChanged: (v) {
                            _vm.updateSuggestions(v);
                            setState(() {});
                          },
                          onSubmitted: _submitSearch,
                        ),
                        const SizedBox(height: Md3Spacing.s8),
                        Row(
                          children: [
                            Expanded(
                              child: PrismSegmentedControl<SourceScope>(
                                value: _vm.scope,
                                onChanged: _vm.setScope,
                                segments: const [
                                  (SourceScope.all, '双源'),
                                  (SourceScope.jmcomic, 'JM'),
                                  (SourceScope.ehentai, 'EH'),
                                ],
                              ),
                            ),
                            if (_vm.scope != SourceScope.ehentai &&
                                _vm.hasExecutedSearch) ...[
                              const SizedBox(width: Md3Spacing.s8),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _vm.jmSort,
                                  items: SearchViewModel.jmSorts
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s.code,
                                          child: Text(s.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) _vm.setJmSort(v);
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Direct jump banner if user typed JM ID or EH URL
              if (directTarget != null)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        pageMargin,
                        0,
                        pageMargin,
                        Md3Spacing.s8,
                      ),
                      child: ListTile(
                        tileColor: cs.primaryContainer,
                        textColor: cs.onPrimaryContainer,
                        iconColor: cs.onPrimaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Md3Shapes.medium),
                        ),
                        leading: const Icon(Icons.bolt_rounded),
                        title: Text(
                          directTarget.source == ComicSource.jmcomic
                              ? '直达 JMComic 车号：JM${directTarget.id}'
                              : '直达 E-Hentai 画廊：${directTarget.id}',
                        ),
                        trailing: const Icon(Icons.open_in_new_rounded),
                        onTap: () => _submitSearch(_textController.text),
                      ),
                    ),
                  ),
                ),

              // Bilingual E-Hentai tag suggestions
              if (_vm.suggestions.isNotEmpty)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 720,
                      maxHeight: 220,
                    ),
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: pageMargin),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(Md3Shapes.large),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _vm.suggestions.length,
                        itemBuilder: (_, i) {
                          final s = _vm.suggestions[i];
                          return ListTile(
                            title: Text('${s.chinese} (${s.fullTag})'),
                            trailing: Text(
                              s.namespaceZh,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.primary,
                              ),
                            ),
                            onTap: () => _applySuggestion(s.fullTag),
                          );
                        },
                      ),
                    ),
                  ),
                ),

              Expanded(
                child: _vm.hasExecutedSearch
                    ? _buildSearchResults(pageMargin)
                    : _buildDiscoveryBrowser(pageMargin),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchResults(double pageMargin) {
    final bottomInset = PrismBottomInsetScope.of(context);
    if (_vm.results.isEmpty) {
      return AsyncStatePlaceholder(
        isLoading: _vm.isSearching,
        error: _vm.error,
        isEmpty: true,
        useSkeletonOnLoad: true,
        emptyTitle: '没有找到相关漫画',
        emptySubtitle: '试试更换关键词、调整分类或切换数据源',
        actionLabel: '返回分类',
        onAction: _vm.clearResults,
        onRetry: () {
          if (_vm.activeCategorySlug.isNotEmpty) {
            _vm.searchByJmCategory(_vm.activeCategorySlug);
          } else {
            _vm.executeSearch(_vm.query, saveHistory: false);
          }
        },
      );
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pageMargin,
                Md3Spacing.s4,
                pageMargin,
                (_vm.hasMore || _vm.isLoadingMore)
                    ? Md3Spacing.s16
                    : Md3Spacing.s24 + bottomInset,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: Md3Spacing.cardVerticalGap,
                  crossAxisSpacing: Md3Spacing.cardHorizontalGap,
                  childAspectRatio: 0.62,
                ),
                itemCount: _vm.results.length,
                itemBuilder: (_, idx) {
                  final item = _vm.results[idx];
                  return ComicCard(
                    comic: item,
                    httpClient: widget.deps.httpClient,
                    progress:
                        widget.deps.store.getProgress(item.source, item.id),
                    onTap: () => _openDetail(item),
                  );
                },
              ),
            ),
            if (_vm.hasMore || _vm.isLoadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: Md3Spacing.s32 + bottomInset),
                  child: Center(
                    child: _vm.isLoadingMore
                        ? const CircularProgressIndicator()
                        : OutlinedButton(
                            onPressed: _vm.loadMore,
                            child: const Text('加载更多'),
                          ),
                  ),
                ),
              ),
          ],
        ),
        if (_vm.error != null)
          Positioned(
            left: pageMargin,
            right: pageMargin,
            bottom: Md3Spacing.s16 + bottomInset,
            child: InlineErrorBanner(
              message: _vm.error!,
              onRetry: () => _vm.executeSearch(_vm.query, saveHistory: false),
            ),
          ),
      ],
    );
  }

  Widget _buildDiscoveryBrowser(double pageMargin) {
    final history = widget.deps.store.searchHistory;

    return Column(
      children: [
        if (history.isNotEmpty)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  pageMargin,
                  Md3Spacing.s4,
                  pageMargin,
                  Md3Spacing.s4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '搜索历史',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: widget.deps.store.clearSearchHistory,
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: history.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: Md3Spacing.s8),
                        itemBuilder: (_, i) {
                          final q = history[i];
                          return InputChip(
                            label: Text(q),
                            onPressed: () {
                              _textController.text = q;
                              _submitSearch(q);
                            },
                            onDeleted: () =>
                                widget.deps.store.removeSearchQuery(q),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        TabBar(
          controller: _discoveryTabController,
          tabs: const [
            Tab(text: 'JMComic 分类与标签'),
            Tab(text: 'E-Hentai 分类导航'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _discoveryTabController,
            children: [
              _buildJmCategoryTab(pageMargin),
              _buildEhCategoryTab(pageMargin),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJmCategoryTab(double pageMargin) {
    if (_vm.loadingMeta && _vm.jmCategories == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _vm.jmCategories;
    final theme = Theme.of(context);
    final bottomInset = PrismBottomInsetScope.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageMargin,
        Md3Spacing.s16,
        pageMargin,
        Md3Spacing.s24 + bottomInset,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_vm.jmHotTags.isNotEmpty) ...[
                  Text(
                    '热门搜索',
                    style: Md3Typography.emphasized(theme.textTheme.titleSmall),
                  ),
                  const SizedBox(height: Md3Spacing.s8),
                  Wrap(
                    spacing: Md3Spacing.s8,
                    runSpacing: Md3Spacing.s8,
                    children: _vm.jmHotTags.map((tag) {
                      return ActionChip(
                        label: Text(tag),
                        onPressed: () {
                          _textController.text = tag;
                          _vm.setScope(SourceScope.jmcomic);
                          _vm.executeSearch(tag);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: Md3Spacing.s16),
                ],
                if (data != null && data.categories.isNotEmpty) ...[
                  Text(
                    '作品分区',
                    style: Md3Typography.emphasized(theme.textTheme.titleSmall),
                  ),
                  const SizedBox(height: Md3Spacing.s8),
                  Wrap(
                    spacing: Md3Spacing.s8,
                    runSpacing: Md3Spacing.s8,
                    children: data.categories.map((cat) {
                      final slugOrId =
                          cat.slug.isNotEmpty ? cat.slug : cat.id;
                      return FilledButton.tonal(
                        onPressed: () => _vm.searchByJmCategory(slugOrId),
                        child: Text(cat.name),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: Md3Spacing.s16),
                ],
                if (data != null)
                  ...data.blocks.map((block) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Md3Spacing.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            block.title,
                            style: Md3Typography.emphasized(
                              theme.textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(height: Md3Spacing.s8),
                          Wrap(
                            spacing: Md3Spacing.s8,
                            runSpacing: Md3Spacing.s8,
                            children: block.tags.map((tag) {
                              return ActionChip(
                                label: Text(tag),
                                onPressed: () {
                                  _textController.text = tag;
                                  _vm.setScope(SourceScope.jmcomic);
                                  _vm.executeSearch(tag);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEhCategoryTab(double pageMargin) {
    final theme = Theme.of(context);
    final bottomInset = PrismBottomInsetScope.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageMargin,
        Md3Spacing.s16,
        pageMargin,
        Md3Spacing.s24 + bottomInset,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '点击分类直接浏览 E-Hentai 对应分区',
                  style: Md3Typography.emphasized(theme.textTheme.titleSmall),
                ),
                const SizedBox(height: Md3Spacing.s12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisSpacing: Md3Spacing.s8,
                    crossAxisSpacing: Md3Spacing.s8,
                    childAspectRatio: 2.3,
                  ),
                  itemCount: EhUrl.categories.length,
                  itemBuilder: (_, i) {
                    final cat = EhUrl.categories[i];
                    return Card(
                      color: cat.color.withValues(alpha: 0.18),
                      child: InkWell(
                        onTap: () {
                          _vm.updateEhFilters(categoryMask: cat.bit);
                          _vm.setScope(SourceScope.ehentai);
                          _vm.executeSearch(
                            _textController.text,
                            saveHistory: false,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Md3Spacing.s12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: cat.color,
                                  borderRadius: BorderRadius.circular(
                                    Md3Shapes.extraSmall,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Md3Spacing.s8),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat.label,
                                      style: Md3Typography.emphasized(
                                        theme.textTheme.titleSmall,
                                      ),
                                    ),
                                    Text(
                                      cat.key,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: Md3Spacing.s24),
                Text(
                  '常用中文汉化快速检索',
                  style: Md3Typography.emphasized(theme.textTheme.titleSmall),
                ),
                const SizedBox(height: Md3Spacing.s8),
                Wrap(
                  spacing: Md3Spacing.s8,
                  runSpacing: Md3Spacing.s8,
                  children: [
                    r'language:chinese$',
                    r'language:chinese$ f:"sole female$"',
                    r'language:chinese$ o:"full color$"',
                    r'language:chinese$ p:"blue archive$"',
                    r'language:chinese$ p:"genshin impact$"',
                    r'language:chinese$ o:uncensored$',
                  ].map((preset) {
                    return ActionChip(
                      label: Text(preset),
                      onPressed: () {
                        _textController.text = preset;
                        _vm.updateEhFilters(categoryMask: EhUrl.allCategoryMask);
                        _vm.setScope(SourceScope.ehentai);
                        _vm.executeSearch(preset);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
