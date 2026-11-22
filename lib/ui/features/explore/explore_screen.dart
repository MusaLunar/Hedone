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
import 'explore_view_model.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.deps,
    required this.onSearchTag,
    required this.onOpenSettings,
  });

  final AppDependencies deps;
  final void Function(ComicSource source, String tagQuery) onSearchTag;
  final VoidCallback onOpenSettings;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final ExploreViewModel _vm;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _vm = ExploreViewModel(deps: widget.deps);
    _vm.ensureLoaded();
    _scrollController.addListener(_onScroll);
    widget.deps.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onStoreChanged);
    _scrollController.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      _vm.loadMore();
    }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final windowWidth = MediaQuery.sizeOf(context).width;
        final margin = Md3Breakpoints.pageMargin(windowWidth);
        final isCompact = Md3Breakpoints.ofWidth(windowWidth).isCompact;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Md3Shapes.small),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 28,
                      height: 28,
                    ),
                  ),
                ),
                const SizedBox(width: Md3Spacing.s12),
                Text(
                  'Hedone',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            actions: [
              if (isCompact)
                IconButton(
                  key: const Key('theme_mode_toggle_button'),
                  tooltip: isDark ? '切换浅色模式' : '切换深色模式',
                  onPressed: () => widget.deps.store.toggleDarkLightMode(
                    Theme.of(context).brightness,
                  ),
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  ),
                ),
              IconButton(
                tooltip: _vm.scope == SourceScope.ehentai
                    ? (widget.deps.ehRepo.isExHentai
                        ? '当前站点: ExHentai'
                        : '当前站点: E-Hentai')
                    : '当前线路: ${widget.deps.store.jmApiHost}',
                onPressed: widget.onOpenSettings,
                icon: Icon(
                  Icons.dns_outlined,
                  color: cs.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: '刷新列表',
                onPressed: _vm.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: Md3Spacing.s4),
            ],
          ),
          body: Column(
            children: [
              // FlClash/Prism Sliding Capsule Source Switcher
              Padding(
                padding: EdgeInsets.fromLTRB(
                  margin,
                  Md3Spacing.s4,
                  margin,
                  Md3Spacing.s8,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: PrismSegmentedControl<SourceScope>(
                    value: _vm.scope,
                    onChanged: _vm.setScope,
                    segments: const [
                      (SourceScope.all, '双源聚合'),
                      (SourceScope.jmcomic, 'JMComic'),
                      (SourceScope.ehentai, 'E-Hentai'),
                    ],
                  ),
                ),
              ),

              if (_vm.scope == SourceScope.jmcomic) _buildJmSubBar(margin),
              if (_vm.scope == SourceScope.ehentai) _buildEhSubBar(margin),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _vm.refresh,
                  child: _buildBody(context, margin),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJmSubBar(double margin) {
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 0, margin, Md3Spacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: JmExploreTab.values.map((tab) {
                return Padding(
                  padding: const EdgeInsets.only(right: Md3Spacing.s8),
                  child: ChoiceChip(
                    selected: _vm.jmTab == tab,
                    label: Text(tab.label),
                    onSelected: (_) => _vm.setJmTab(tab),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_vm.jmTab == JmExploreTab.weekly && _vm.jmWeekMeta != null) ...[
            const SizedBox(height: Md3Spacing.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _vm.selectedWeekPeriodId.isNotEmpty
                          ? _vm.selectedWeekPeriodId
                          : null,
                      items: _vm.jmWeekMeta!.periods
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _vm.setWeekFilter(periodId: v);
                      },
                    ),
                  ),
                  const SizedBox(width: Md3Spacing.s12),
                  ..._vm.jmWeekMeta!.types.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(right: Md3Spacing.s8),
                      child: FilterChip(
                        selected: _vm.selectedWeekTypeId == t.id,
                        label: Text(t.label),
                        onSelected: (_) => _vm.setWeekFilter(typeId: t.id),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEhSubBar(double margin) {
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 0, margin, Md3Spacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: EhExploreTab.values.map((tab) {
                return Padding(
                  padding: const EdgeInsets.only(right: Md3Spacing.s8),
                  child: ChoiceChip(
                    selected: _vm.ehTab == tab,
                    label: Text(tab.label),
                    onSelected: (_) => _vm.setEhTab(tab),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_vm.ehTab == EhExploreTab.frontPage) ...[
            const SizedBox(height: Md3Spacing.s8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: EhUrl.categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: Md3Spacing.s8),
                itemBuilder: (_, i) {
                  final cat = EhUrl.categories[i];
                  final enabled = (widget.deps.store.ehCategoryMask & cat.bit) != 0;
                  return FilterChip(
                    selected: enabled,
                    label: Text(cat.label),
                    onSelected: (_) => _vm.toggleEhCategoryBit(cat.bit),
                  );
                },
              ),
            ),
          ],
          if (_vm.ehTab == EhExploreTab.toplist) ...[
            const SizedBox(height: Md3Spacing.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: EhUrl.toplistBoards.map((board) {
                  return Padding(
                    padding: const EdgeInsets.only(right: Md3Spacing.s8),
                    child: FilterChip(
                      selected: _vm.ehToplistBoard == board.id,
                      label: Text(board.label),
                      onSelected: (_) => _vm.setEhToplistBoard(board.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, double margin) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final bottomInset = PrismBottomInsetScope.of(context);

    if (_vm.scope == SourceScope.jmcomic && _vm.jmTab == JmExploreTab.promote) {
      if (_vm.jmPromoteSections.isEmpty) {
        return AsyncStatePlaceholder(
          isLoading: _vm.isLoading,
          error: _vm.error,
          isEmpty: true,
          useSkeletonOnLoad: true,
          actionLabel: '刷新推荐',
          onAction: _vm.refresh,
          onRetry: _vm.refresh,
        );
      }
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(
          margin,
          Md3Spacing.s4,
          margin,
          Md3Spacing.s32 + bottomInset,
        ),
        itemCount: _vm.jmPromoteSections.length,
        itemBuilder: (context, idx) {
          final section = _vm.jmPromoteSections[idx];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Md3Spacing.s12),
                child: Text(
                  section.title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                height: 248,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: section.items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: Md3Spacing.cardHorizontalGap),
                  itemBuilder: (_, i) {
                    final item = section.items[i];
                    return SizedBox(
                      width: 152,
                      child: ComicCard(
                        comic: item,
                        httpClient: widget.deps.httpClient,
                        progress: widget.deps.store
                            .getProgress(item.source, item.id),
                        onTap: () => _openDetail(item),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    }

    final List<ComicSummary> items;
    final bool hasMore;
    switch (_vm.scope) {
      case SourceScope.all:
        items = _vm.aggItems;
        hasMore = _vm.aggHasMore;
      case SourceScope.jmcomic:
        items = _vm.jmTab == JmExploreTab.latest
            ? _vm.jmLatestItems
            : _vm.jmWeekItems;
        hasMore = _vm.jmTab == JmExploreTab.latest
            ? _vm.jmLatestHasMore
            : _vm.jmWeekHasMore;
      case SourceScope.ehentai:
        items = _vm.ehItems;
        hasMore = _vm.ehHasMore;
    }

    if (items.isEmpty) {
      return AsyncStatePlaceholder(
        isLoading: _vm.isLoading,
        error: _vm.error,
        isEmpty: true,
        useSkeletonOnLoad: true,
        actionLabel: '重新加载',
        onAction: _vm.refresh,
        onRetry: _vm.refresh,
      );
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (_vm.scope == SourceScope.all && _vm.aggFeatured.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    margin,
                    Md3Spacing.s8,
                    margin,
                    Md3Spacing.s8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(Md3Spacing.s12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(Md3Shapes.largeIncreased),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: Md3Spacing.s4,
                            bottom: Md3Spacing.s12,
                          ),
                          child: Text(
                            'JMComic 精选推荐',
                            style: textTheme.titleSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 232,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _vm.aggFeatured.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: Md3Spacing.cardHorizontalGap),
                            itemBuilder: (_, i) {
                              final item = _vm.aggFeatured[i];
                              return SizedBox(
                                width: 144,
                                child: ComicCard(
                                  comic: item,
                                  httpClient: widget.deps.httpClient,
                                  progress: widget.deps.store
                                      .getProgress(item.source, item.id),
                                  onTap: () => _openDetail(item),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    margin,
                    Md3Spacing.s16,
                    margin,
                    Md3Spacing.s8,
                  ),
                  child: Text(
                    '双源最新混排',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                margin,
                Md3Spacing.s4,
                margin,
                (hasMore || _vm.isLoadingMore)
                    ? Md3Spacing.s16
                    : Md3Spacing.s24 + bottomInset,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 196,
                  mainAxisSpacing: Md3Spacing.cardVerticalGap,
                  crossAxisSpacing: Md3Spacing.cardHorizontalGap,
                  childAspectRatio: 0.62,
                ),
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
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
            if (hasMore || _vm.isLoadingMore)
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
            left: margin,
            right: margin,
            bottom: Md3Spacing.s16 + bottomInset,
            child: InlineErrorBanner(
              message: _vm.error!,
              onRetry: _vm.refresh,
            ),
          ),
      ],
    );
  }
}
