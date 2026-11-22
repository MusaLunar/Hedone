import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/theme/md3_tokens.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../../domain/models/reader_models.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/comic_card.dart';
import '../../widgets/jm_descrambled_image.dart';
import '../reader/comic_reader_screen.dart';
import 'detail_view_model.dart';

class ComicDetailScreen extends StatefulWidget {
  const ComicDetailScreen({
    super.key,
    required this.deps,
    required this.summary,
    this.onSearchTag,
  });

  final AppDependencies deps;
  final ComicSummary summary;
  final void Function(ComicSource source, String tagQuery)? onSearchTag;

  @override
  State<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends State<ComicDetailScreen> {
  late final DetailViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = DetailViewModel(deps: widget.deps, initialSummary: widget.summary);
    _vm.loadDetail();
    widget.deps.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onStoreChanged);
    _vm.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _openReader({
    ComicChapter? chapter,
    int startPageIndex = 0,
  }) {
    final detail = _vm.detail;
    final summary = _vm.summary;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicReaderScreen(
          deps: widget.deps,
          summary: summary,
          detail: detail,
          initialChapter: chapter,
          initialPageIndex: startPageIndex,
        ),
      ),
    );
  }

  void _handleStartOrContinue() {
    final detail = _vm.detail;
    final progress = _vm.readingProgress;
    if (widget.summary.source == ComicSource.jmcomic && detail != null) {
      ComicChapter target = detail.chapters.first;
      var pageIdx = 0;
      if (progress != null) {
        final match = detail.chapters.where((c) => c.id == progress.chapterId);
        if (match.isNotEmpty) {
          target = match.first;
          pageIdx = progress.pageIndex;
        }
      }
      _openReader(chapter: target, startPageIndex: pageIdx);
    } else {
      _openReader(startPageIndex: progress?.pageIndex ?? 0);
    }
  }

  Future<void> _showFavoriteDialog() async {
    final folders = widget.deps.store.folders;
    final currentFolderId = widget.deps.store.favoriteFolderFor(
      _vm.summary.source,
      _vm.summary.id,
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final horizontal = Md3Breakpoints.pageMargin(
          MediaQuery.sizeOf(ctx).width,
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              0,
              horizontal,
              Md3Spacing.s16,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '收藏到书架',
                      style: Md3Typography.emphasized(
                        Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: Md3Spacing.s12),
                    ...folders.map((folder) {
                      final selected = currentFolderId == folder.id;
                      return ListTile(
                        leading: Icon(
                          selected
                              ? Icons.folder_special
                              : Icons.folder_outlined,
                          color: selected
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                        title: Text(folder.name),
                        trailing: selected ? const Icon(Icons.check) : null,
                        onTap: () async {
                          await _vm.saveToFavoriteFolder(folder.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已加入「${folder.name}」')),
                            );
                          }
                        },
                      );
                    }),
                    if (currentFolderId != null)
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                        title: Text(
                          '移出本地收藏',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                        onTap: () async {
                          await _vm.removeLocalFavorite();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.cloud_sync_outlined),
                      title: Text(
                        _vm.summary.source == ComicSource.jmcomic
                            ? '同步 JMComic 云端收藏'
                            : '同步 E-Hentai 云端收藏',
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final msg = await _vm.toggleCloudFavorite();
                        if (mounted && msg != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDownloadDialog() async {
    final detail = _vm.detail;
    if (detail == null) return;

    if (_vm.summary.source == ComicSource.ehentai) {
      await widget.deps.downloadService.enqueueEhGallery(detail: detail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入下载队列')),
        );
      }
      return;
    }

    final selectedIds = <String>{
      for (final ch in detail.chapters) ch.id,
    };

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
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  0,
                  horizontal,
                  Md3Spacing.s16,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 560,
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              '选择下载章节 (${selectedIds.length}/${detail.chapters.length})',
                              style: Md3Typography.tabularFigures(
                                Md3Typography.emphasized(
                                  Theme.of(ctx).textTheme.titleMedium,
                                ),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  if (selectedIds.length ==
                                      detail.chapters.length) {
                                    selectedIds.clear();
                                  } else {
                                    selectedIds.addAll(
                                      detail.chapters.map((c) => c.id),
                                    );
                                  }
                                });
                              },
                              child: Text(
                                selectedIds.length == detail.chapters.length
                                    ? '全不选'
                                    : '全选',
                              ),
                            ),
                          ],
                        ),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: detail.chapters.length,
                            itemBuilder: (_, index) {
                              final ch = detail.chapters[index];
                              final checked = selectedIds.contains(ch.id);
                              return CheckboxListTile(
                                value: checked,
                                title: Text(ch.title),
                                onChanged: (v) {
                                  setModalState(() {
                                    if (v == true) {
                                      selectedIds.add(ch.id);
                                    } else {
                                      selectedIds.remove(ch.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: Md3Spacing.s12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: selectedIds.isEmpty
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    for (final ch in detail.chapters) {
                                      if (selectedIds.contains(ch.id)) {
                                        await widget.deps.downloadService
                                            .enqueueJmChapter(
                                          summary: detail.summary,
                                          chapter: ch,
                                        );
                                      }
                                    }
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '已添加 ${selectedIds.length} 个章节到下载队列',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('开始下载并自动拼图还原'),
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

  void _copyId() {
    final s = _vm.summary;
    final text = s.source == ComicSource.jmcomic
        ? 'JM${s.id}'
        : '${s.id}/${s.token}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ID: $text')),
    );
  }

  void _triggerTagSearch(String namespace, String tag) {
    final source = _vm.summary.source;
    final query = source == ComicSource.ehentai
        ? (tag.contains(' ') ? '$namespace:"$tag"' : '$namespace:$tag')
        : tag;
    if (widget.onSearchTag != null) {
      Navigator.of(context).pop();
      widget.onSearchTag!(source, query);
    } else {
      Navigator.of(context).pop(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final windowClass = Md3Breakpoints.ofWidth(windowWidth);
    final pageMargin = Md3Breakpoints.pageMargin(windowWidth);

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final detail = _vm.detail;
        final summary = _vm.summary;
        final progress = _vm.readingProgress;
        final hasProgress = progress != null && progress.totalPages > 0;

        if (windowClass.isTwoPaneEligible) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                summary.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Md3Typography.emphasized(textTheme.titleMedium),
              ),
              actions: [
                IconButton(
                  tooltip: '复制编号',
                  onPressed: _copyId,
                  icon: const Icon(Icons.copy_rounded),
                ),
                IconButton(
                  tooltip: '刷新详情',
                  onPressed: () => _vm.loadDetail(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: pageMargin),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Supporting Leading Fixed Pane (360dp / 412dp per MD3 layout spec)
                  SizedBox(
                    width: Md3Breakpoints.fixedPaneWidth(windowWidth),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(
                        top: Md3Spacing.s16,
                        bottom: Md3Spacing.s32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeroHeaderRow(
                            context,
                            summary: summary,
                            detail: detail,
                            compactCover: false,
                          ),
                          if (detail != null) ...[
                            const SizedBox(height: Md3Spacing.s16),
                            _buildActionRow(
                              cs: cs,
                              hasProgress: hasProgress,
                              progress: progress,
                            ),
                            const SizedBox(height: Md3Spacing.s16),
                            _buildMetaCard(summary, detail),
                            if (detail.description.isNotEmpty) ...[
                              const SizedBox(height: Md3Spacing.s12),
                              _buildDescriptionCard(cs, textTheme, detail),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Md3Breakpoints.paneSpacer),
                  // Trailing Flexible Pane
                  Expanded(
                    child: _buildTwoPaneTrailingPane(
                      context,
                      detail: detail,
                      summary: summary,
                      progress: progress,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Single-Pane Layout (< 840dp: Compact & Medium)
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                actions: [
                  IconButton(
                    tooltip: '复制编号',
                    onPressed: _copyId,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    tooltip: '刷新详情',
                    onPressed: () => _vm.loadDetail(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: 0.28,
                        child: HedoneImage(
                          url: summary.coverUrl,
                          httpClient: widget.deps.httpClient,
                          fit: BoxFit.cover,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              cs.surface.withValues(alpha: 0.3),
                              cs.surface,
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            pageMargin,
                            56,
                            pageMargin,
                            Md3Spacing.s16,
                          ),
                          child: _buildHeroHeaderRow(
                            context,
                            summary: summary,
                            detail: detail,
                            compactCover: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_vm.isLoading && detail == null)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_vm.error != null && detail == null)
                SliverFillRemaining(
                  child: AsyncStatePlaceholder(
                    isLoading: false,
                    error: _vm.error,
                    isEmpty: true,
                    onRetry: () => _vm.loadDetail(),
                  ),
                )
              else if (detail != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    pageMargin,
                    Md3Spacing.s8,
                    pageMargin,
                    Md3Spacing.s32,
                  ),
                  sliver: SliverList.list(
                    children: [
                      _buildActionRow(
                        cs: cs,
                        hasProgress: hasProgress,
                        progress: progress,
                      ),
                      const SizedBox(height: Md3Spacing.s16),
                      _buildMetaCard(summary, detail),
                      if (detail.description.isNotEmpty) ...[
                        const SizedBox(height: Md3Spacing.s12),
                        _buildDescriptionCard(cs, textTheme, detail),
                      ],
                      ..._buildDetailSections(
                        context,
                        summary: summary,
                        detail: detail,
                        progress: progress,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroHeaderRow(
    BuildContext context, {
    required ComicSummary summary,
    required ComicDetail? detail,
    required bool compactCover,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment:
          compactCover ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Md3Shapes.medium),
          child: SizedBox(
            width: compactCover ? 120 : 132,
            height: compactCover ? 165 : 182,
            child: HedoneImage(
              url: summary.coverUrl,
              httpClient: widget.deps.httpClient,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: Md3Spacing.s16),
        Expanded(
          child: Column(
            mainAxisAlignment: compactCover
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Md3Spacing.s8,
                runSpacing: Md3Spacing.s4,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      summary.badgeLabel,
                      style: TextStyle(color: cs.onPrimaryContainer),
                    ),
                    backgroundColor: cs.primaryContainer,
                  ),
                  if (summary.category.isNotEmpty)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(summary.category),
                    ),
                ],
              ),
              const SizedBox(height: Md3Spacing.s8),
              SelectableText(
                summary.title,
                maxLines: compactCover ? 3 : 4,
                style: Md3Typography.emphasized(textTheme.titleMedium),
              ),
              if (detail != null && detail.titleJpn.isNotEmpty) ...[
                const SizedBox(height: Md3Spacing.s4),
                Text(
                  detail.titleJpn,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Md3Spacing.s8),
              GestureDetector(
                onLongPress: _copyId,
                child: Text(
                  summary.source == ComicSource.jmcomic
                      ? 'JM${summary.id} · ${summary.author}'
                      : 'GID ${summary.id} · ${detail?.uploader ?? summary.author}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow({
    required ColorScheme cs,
    required bool hasProgress,
    required ReadingProgress? progress,
  }) {
    // Only ONE primary FilledButton per screen; secondary actions are tonal icon buttons.
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: _handleStartOrContinue,
            icon: Icon(
              hasProgress
                  ? Icons.play_arrow_rounded
                  : Icons.menu_book_rounded,
            ),
            label: Text(
              hasProgress
                  ? '继续阅读 (${progress!.chapterTitle} · P.${progress.pageIndex + 1})'
                  : '开始阅读',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Md3Typography.tabularFigures(null),
            ),
          ),
        ),
        const SizedBox(width: Md3Spacing.s8),
        IconButton.filledTonal(
          tooltip: '收藏',
          onPressed: _showFavoriteDialog,
          icon: Icon(
            _vm.isLocalFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: _vm.isLocalFavorite ? cs.error : null,
          ),
        ),
        const SizedBox(width: Md3Spacing.s4),
        IconButton.filledTonal(
          tooltip: '下载',
          onPressed: _showDownloadDialog,
          icon: const Icon(Icons.download_rounded),
        ),
      ],
    );
  }

  Widget _buildMetaCard(ComicSummary summary, ComicDetail detail) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Md3Spacing.s16),
        child: Wrap(
          spacing: Md3Spacing.s16,
          runSpacing: Md3Spacing.s8,
          children: [
            if (summary.rating != null)
              _MetaStat(
                icon: Icons.star_rounded,
                label:
                    '${summary.rating!.toStringAsFixed(2)} (${detail.ratingCount})',
              ),
            if (summary.pageCount != null && summary.pageCount! > 0)
              _MetaStat(
                icon: Icons.collections_outlined,
                label: '${summary.pageCount} 页',
              ),
            if (detail.views.isNotEmpty)
              _MetaStat(
                icon: Icons.visibility_outlined,
                label: '${detail.views} 阅读',
              ),
            if (detail.likes.isNotEmpty)
              _MetaStat(
                icon: Icons.thumb_up_outlined,
                label: '${detail.likes} 赞',
              ),
            if (detail.language.isNotEmpty)
              _MetaStat(
                icon: Icons.translate_rounded,
                label: detail.language,
              ),
            if (detail.fileSize.isNotEmpty)
              _MetaStat(
                icon: Icons.sd_storage_outlined,
                label: detail.fileSize,
              ),
            if (detail.posted.isNotEmpty)
              _MetaStat(
                icon: Icons.schedule_rounded,
                label: detail.posted,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionCard(
    ColorScheme cs,
    TextTheme textTheme,
    ComicDetail detail,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Md3Spacing.s16),
        child: Text(
          detail.description,
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildTwoPaneTrailingPane(
    BuildContext context, {
    required ComicDetail? detail,
    required ComicSummary summary,
    required ReadingProgress? progress,
  }) {
    if (_vm.isLoading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_vm.error != null && detail == null) {
      return AsyncStatePlaceholder(
        isLoading: false,
        error: _vm.error,
        isEmpty: true,
        onRetry: () => _vm.loadDetail(),
      );
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }
    return ListView(
      padding: const EdgeInsets.only(
        top: Md3Spacing.s8,
        bottom: Md3Spacing.s32,
      ),
      children: _buildDetailSections(
        context,
        summary: summary,
        detail: detail,
        progress: progress,
      ),
    );
  }

  List<Widget> _buildDetailSections(
    BuildContext context, {
    required ComicSummary summary,
    required ComicDetail detail,
    required ReadingProgress? progress,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return [
      if (detail.tagGroups.isNotEmpty) ...[
        const SizedBox(height: Md3Spacing.s16),
        Text(
          '标签与属性（点击可搜索）',
          style: Md3Typography.emphasized(textTheme.titleSmall),
        ),
        const SizedBox(height: Md3Spacing.s8),
        ...detail.tagGroups.entries.map((entry) {
          final ns = entry.key;
          final nsDisplay = summary.source == ComicSource.ehentai &&
                  widget.deps.store.translateEhTags
              ? widget.deps.tagTranslator.translateNamespace(ns)
              : ns;
          return Padding(
            padding: const EdgeInsets.only(bottom: Md3Spacing.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nsDisplay,
                  style: Md3Typography.emphasized(
                    textTheme.labelMedium?.copyWith(color: cs.primary),
                  ),
                ),
                const SizedBox(height: Md3Spacing.s8),
                Wrap(
                  spacing: Md3Spacing.s8,
                  runSpacing: Md3Spacing.s8,
                  children: entry.value.map((tag) {
                    final label = summary.source == ComicSource.ehentai
                        ? widget.deps.tagTranslator.formatTagDisplay(
                            ns,
                            tag,
                            enabled: widget.deps.store.translateEhTags,
                          )
                        : tag;
                    return ActionChip(
                      label: Text(label),
                      onPressed: () => _triggerTagSearch(ns, tag),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }),
      ],

      if (summary.source == ComicSource.jmcomic && detail.chapters.isNotEmpty) ...[
        const SizedBox(height: Md3Spacing.s16),
        Text(
          '章节列表 (${detail.chapters.length})',
          style: Md3Typography.tabularFigures(
            Md3Typography.emphasized(textTheme.titleSmall),
          ),
        ),
        const SizedBox(height: Md3Spacing.s8),
        Wrap(
          spacing: Md3Spacing.s8,
          runSpacing: Md3Spacing.s8,
          children: detail.chapters.map((ch) {
            final isCurrent = progress?.chapterId == ch.id;
            return ChoiceChip(
              selected: isCurrent,
              label: Text(ch.title),
              onSelected: (_) => _openReader(
                chapter: ch,
                startPageIndex: isCurrent ? progress!.pageIndex : 0,
              ),
            );
          }).toList(),
        ),
      ],

      if (summary.source == ComicSource.ehentai && detail.previews.isNotEmpty) ...[
        const SizedBox(height: Md3Spacing.s16),
        Row(
          children: [
            Text(
              '画廊预览 (点击缩略图跳页阅读)',
              style: Md3Typography.emphasized(textTheme.titleSmall),
            ),
            const Spacer(),
            if (detail.totalPreviewPages > 1)
              Text(
                '第 ${_vm.currentPreviewPage + 1}/${detail.totalPreviewPages} 页',
                style: Md3Typography.tabularFigures(
                  textTheme.labelMedium?.copyWith(color: cs.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: Md3Spacing.s8),
        if (_vm.isLoadingPreviews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Md3Spacing.s24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: Md3Spacing.s8,
              crossAxisSpacing: Md3Spacing.s8,
              childAspectRatio: 0.72,
            ),
            itemCount: detail.previews.length,
            itemBuilder: (_, index) {
              final prev = detail.previews[index];
              return InkWell(
                borderRadius: BorderRadius.circular(Md3Shapes.small),
                onTap: () => _openReader(
                  startPageIndex: prev.pageNumber - 1,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Md3Shapes.small),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      EhPreviewThumbWidget(
                        preview: prev,
                        httpClient: widget.deps.httpClient,
                      ),
                      Positioned(
                        right: Md3Spacing.s4,
                        bottom: Md3Spacing.s4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Md3Spacing.s8,
                            vertical: Md3Spacing.s2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(
                              Md3Shapes.extraSmall,
                            ),
                          ),
                          child: Text(
                            '${prev.pageNumber}',
                            style: Md3Typography.tabularFigures(
                              textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        if (detail.totalPreviewPages > 1) ...[
          const SizedBox(height: Md3Spacing.s12),
          Wrap(
            spacing: Md3Spacing.s8,
            runSpacing: Md3Spacing.s8,
            children: List.generate(detail.totalPreviewPages, (i) {
              return ChoiceChip(
                selected: _vm.currentPreviewPage == i,
                label: Text('${i + 1}'),
                onSelected: (_) => _vm.loadPreviewPage(i),
              );
            }),
          ),
        ],
      ],

      // Comments
      const SizedBox(height: Md3Spacing.s24),
      Row(
        children: [
          Text(
            '评论 (${detail.comments.length})',
            style: Md3Typography.tabularFigures(
              Md3Typography.emphasized(textTheme.titleSmall),
            ),
          ),
          const Spacer(),
          if (summary.source == ComicSource.jmcomic)
            TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ctrl = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('发表评论'),
                    content: TextField(
                      controller: ctrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '输入你的看法...',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('发送'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final err = await _vm.postJmComment(ctrl.text);
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(err ?? '评论已发表')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.comment_outlined, size: 18),
              label: const Text('发表'),
            ),
        ],
      ),
      const SizedBox(height: Md3Spacing.s8),
      if (detail.comments.isEmpty)
        Text(
          '暂无评论',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        )
      else
        ...detail.comments.take(20).map(
              (c) => Card(
                margin: const EdgeInsets.only(bottom: Md3Spacing.s8),
                child: Padding(
                  padding: const EdgeInsets.all(Md3Spacing.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            c.author,
                            style: Md3Typography.emphasized(
                              textTheme.labelLarge,
                            ),
                          ),
                          if (c.level.isNotEmpty) ...[
                            const SizedBox(width: Md3Spacing.s8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Md3Spacing.s8,
                                vertical: Md3Spacing.s2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(
                                  Md3Shapes.extraSmall,
                                ),
                              ),
                              child: Text(
                                c.level,
                                style: textTheme.labelSmall?.copyWith(
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (c.score.isNotEmpty)
                            Text(
                              c.score,
                              style: Md3Typography.tabularFigures(
                                textTheme.labelSmall?.copyWith(
                                  color: cs.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: Md3Spacing.s4),
                      Text(c.content, style: textTheme.bodyMedium),
                      if (c.postedAt.isNotEmpty) ...[
                        const SizedBox(height: Md3Spacing.s4),
                        Text(
                          c.postedAt,
                          style: textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

      // Related Comics
      if (detail.related.isNotEmpty) ...[
        const SizedBox(height: Md3Spacing.s24),
        Text(
          '相关推荐',
          style: Md3Typography.emphasized(textTheme.titleSmall),
        ),
        const SizedBox(height: Md3Spacing.s12),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: detail.related.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: Md3Spacing.cardHorizontalGap),
            itemBuilder: (_, i) {
              final item = detail.related[i];
              return SizedBox(
                width: 140,
                child: ComicCard(
                  comic: item,
                  httpClient: widget.deps.httpClient,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ComicDetailScreen(
                          deps: widget.deps,
                          summary: item,
                          onSearchTag: widget.onSearchTag,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ];
  }
}

class _MetaStat extends StatelessWidget {
  const _MetaStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: Md3Spacing.s4),
        Text(
          label,
          style: Md3Typography.tabularFigures(
            Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
