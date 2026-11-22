import 'package:flutter/material.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/theme/md3_tokens.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../../domain/models/download_task.dart';
import '../../prism/prism_navigation_dock.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/jm_descrambled_image.dart';
import '../../widgets/md3_segmented_list.dart';
import '../detail/comic_detail_screen.dart';
import '../reader/comic_reader_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    required this.deps,
    required this.onSearchTag,
    this.onExplore,
  });

  final AppDependencies deps;
  final void Function(ComicSource source, String tagQuery) onSearchTag;
  final VoidCallback? onExplore;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    widget.deps.store.addListener(_onChanged);
    widget.deps.downloadService.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onChanged);
    widget.deps.downloadService.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _openOfflineReader(DownloadTask task) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicReaderScreen(
          deps: widget.deps,
          summary: task.summary,
          initialChapter: ComicChapter(
            id: task.chapterId,
            title: task.chapterTitle,
            sort: '1',
            index: 0,
          ),
          offlineTask: task,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = widget.deps.store.downloads;
    final pageMargin = Md3Breakpoints.pageMargin(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '离线下载',
          style: Md3Typography.emphasized(theme.textTheme.titleLarge),
        ),
      ),
      body: tasks.isEmpty
          ? AsyncStatePlaceholder(
              isLoading: false,
              error: null,
              isEmpty: true,
              emptyTitle: '暂无下载任务',
              emptySubtitle: '在漫画详情页点击下载，JMComic 图片将自动拼接还原后缓存到本地',
              actionLabel: widget.onExplore != null ? '前往探索' : null,
              onAction: widget.onExplore,
              onRetry: _noop,
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                pageMargin,
                Md3Spacing.s12,
                pageMargin,
                Md3Spacing.s24 + PrismBottomInsetScope.of(context),
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: Md3SegmentedListGroup(
                      children: tasks.map((task) {
                        return _DownloadTaskItem(
                          task: task,
                          deps: widget.deps,
                          onTap: task.status == DownloadStatus.completed
                              ? () => _openOfflineReader(task)
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ComicDetailScreen(
                                        deps: widget.deps,
                                        summary: task.summary,
                                        onSearchTag: widget.onSearchTag,
                                      ),
                                    ),
                                  );
                                },
                          onOpenOfflineReader: () => _openOfflineReader(task),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DownloadTaskItem extends StatelessWidget {
  const _DownloadTaskItem({
    required this.task,
    required this.deps,
    required this.onTap,
    required this.onOpenOfflineReader,
  });

  final DownloadTask task;
  final AppDependencies deps;
  final VoidCallback onTap;
  final VoidCallback onOpenOfflineReader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
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
                  url: task.summary.coverUrl,
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
                          task.summary.badgeLabel,
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
                          task.summary.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Md3Typography.emphasized(
                            theme.textTheme.titleSmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Md3Spacing.s4),
                  Text(
                    '${task.chapterTitle} · ${task.status.label} (${task.downloadedCount}/${task.totalCount})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Md3Typography.tabularFigures(
                      theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (task.errorMessage != null) ...[
                    const SizedBox(height: Md3Spacing.s2),
                    Text(
                      task.errorMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: Md3Spacing.s8),
                  LinearProgressIndicator(value: task.progress),
                ],
              ),
            ),
            const SizedBox(width: Md3Spacing.s4),
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.queued)
              IconButton(
                tooltip: '暂停',
                onPressed: () => deps.downloadService.pauseTask(task.id),
                icon: const Icon(Icons.pause_rounded),
              )
            else if (task.status == DownloadStatus.paused ||
                task.status == DownloadStatus.failed)
              IconButton(
                tooltip: '继续 / 重试',
                onPressed: () => deps.downloadService.resumeTask(task.id),
                icon: const Icon(Icons.play_arrow_rounded),
              )
            else
              IconButton(
                tooltip: '离线阅读',
                onPressed: onOpenOfflineReader,
                icon: const Icon(Icons.menu_book_rounded),
              ),
            IconButton(
              tooltip: '删除',
              onPressed: () => deps.downloadService.deleteTask(task.id),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}
