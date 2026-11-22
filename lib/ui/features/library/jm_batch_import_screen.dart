import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/theme/md3_tokens.dart';
import '../../../core/utils/jm_id_extractor.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../widgets/md3_segmented_list.dart';
import '../detail/comic_detail_screen.dart';

enum _BatchCandidateStatus {
  idle,
  fetching,
  saved,
  savedFallback,
  failed,
}

class _BatchCandidate {
  _BatchCandidate({
    required this.id,
    required this.kind,
  });

  final String id;
  final JmIdMatchKind kind;
  bool selected = true;
  _BatchCandidateStatus status = _BatchCandidateStatus.idle;
  ComicSummary? summary;
  String? errorMessage;
}

class JmBatchImportScreen extends StatefulWidget {
  const JmBatchImportScreen({
    super.key,
    required this.deps,
    this.onSearchTag,
  });

  final AppDependencies deps;
  final void Function(ComicSource source, String tagQuery)? onSearchTag;

  @override
  State<JmBatchImportScreen> createState() => _JmBatchImportScreenState();
}

class _JmBatchImportScreenState extends State<JmBatchImportScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final List<_BatchCandidate> _candidates = [];

  String _selectedFolderId = 'default';
  bool _fetchMetadata = true;
  bool _saveFallbackOnError = true;
  bool _syncCloud = false;

  bool _isImporting = false;
  bool _cancelRequested = false;
  int _processed = 0;
  int _totalToImport = 0;

  @override
  void initState() {
    super.initState();
    widget.deps.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onStoreChanged);
    _inputCtrl.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  ComicSummary _fallbackSummary(String id) {
    return ComicSummary(
      id: id,
      source: ComicSource.jmcomic,
      title: 'JM$id',
      coverUrl: widget.deps.jmRepo.coverUrl(id),
    );
  }

  void _syncFromText(String rawText) {
    if (_isImporting) return;
    final extracted = JmIdExtractor.extract(rawText);
    final previousById = {for (final c in _candidates) c.id: c};

    setState(() {
      _candidates
        ..clear()
        ..addAll(
          extracted.map((item) {
            final prev = previousById[item.id];
            if (prev != null) {
              return prev;
            }
            return _BatchCandidate(id: item.id, kind: item.kind);
          }),
        );
    });
  }

  Future<void> _pasteFromClipboard() async {
    if (_isImporting) return;
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空或不包含文本')),
        );
      }
      return;
    }
    _inputCtrl.text = text;
    _inputCtrl.selection = TextSelection.collapsed(offset: text.length);
    _syncFromText(text);
  }

  void _clearInput() {
    if (_isImporting) return;
    _inputCtrl.clear();
    _syncFromText('');
  }

  Future<void> _createFolderDialog() async {
    final ctrl = TextEditingController();
    final beforeCount = widget.deps.store.folders.length;
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
      final folders = widget.deps.store.folders;
      if (mounted && folders.length > beforeCount) {
        setState(() => _selectedFolderId = folders.last.id);
      }
    }
  }

  void _excludeExistingFavorites() {
    if (_isImporting) return;
    setState(() {
      for (final c in _candidates) {
        if (widget.deps.store.isFavorite(ComicSource.jmcomic, c.id)) {
          c.selected = false;
        }
      }
    });
  }

  void _toggleSelectAll() {
    if (_isImporting || _candidates.isEmpty) return;
    final allSelected = _candidates.every((c) => c.selected);
    setState(() {
      for (final c in _candidates) {
        c.selected = !allSelected;
      }
    });
  }

  Future<void> _runBatchImport() async {
    final queue = _candidates.where((c) => c.selected).toList();
    if (queue.isEmpty) return;

    final folders = widget.deps.store.folders;
    final targetFolderId = folders.any((f) => f.id == _selectedFolderId)
        ? _selectedFolderId
        : (folders.isNotEmpty ? folders.first.id : 'default');

    setState(() {
      _isImporting = true;
      _cancelRequested = false;
      _processed = 0;
      _totalToImport = queue.length;
      for (final item in queue) {
        item.status = _BatchCandidateStatus.idle;
        item.errorMessage = null;
      }
    });

    var savedCount = 0;
    var fallbackCount = 0;
    var failedCount = 0;
    var nextIndex = 0;

    Future<void> worker() async {
      while (!_cancelRequested) {
        if (nextIndex >= queue.length) break;
        final item = queue[nextIndex++];

        if (mounted) {
          setState(() => item.status = _BatchCandidateStatus.fetching);
        }

        ComicSummary? resolvedSummary;
        var usedFallback = false;
        String? fetchError;

        if (_fetchMetadata) {
          try {
            final detail = await widget.deps.jmRepo.fetchDetail(item.id);
            resolvedSummary = detail.summary;
          } catch (e) {
            fetchError = e.toString();
          }
        } else {
          resolvedSummary = _fallbackSummary(item.id);
        }

        if (resolvedSummary == null && _saveFallbackOnError) {
          resolvedSummary = _fallbackSummary(item.id);
          usedFallback = true;
        }

        if (resolvedSummary != null) {
          await widget.deps.store.saveFavorite(
            resolvedSummary,
            folderId: targetFolderId,
          );
          if (_syncCloud && widget.deps.store.isJmLoggedIn) {
            try {
              await widget.deps.jmRepo.toggleCloudFavorite(item.id);
            } catch (_) {
              // Cloud sync failure does not revoke local save.
            }
          }
          if (usedFallback) {
            fallbackCount++;
          } else {
            savedCount++;
          }
          if (mounted) {
            setState(() {
              item.summary = resolvedSummary;
              item.status = usedFallback
                  ? _BatchCandidateStatus.savedFallback
                  : _BatchCandidateStatus.saved;
              item.errorMessage = fetchError;
              _processed++;
            });
          }
        } else {
          failedCount++;
          if (mounted) {
            setState(() {
              item.status = _BatchCandidateStatus.failed;
              item.errorMessage = fetchError ?? '获取漫画信息失败';
              _processed++;
            });
          }
        }
      }
    }

    const workerCount = 3;
    final actualWorkers = queue.length < workerCount ? queue.length : workerCount;
    await Future.wait(List.generate(actualWorkers, (_) => worker()));

    if (!mounted) return;
    setState(() => _isImporting = false);

    final prefix = _cancelRequested ? '已停止导入' : '批量处理完成';
    final msg = '$prefix：成功 $savedCount 条，占位保存 $fallbackCount 条，失败 $failedCount 条';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openDetail(_BatchCandidate item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicDetailScreen(
          deps: widget.deps,
          summary: item.summary ?? _fallbackSummary(item.id),
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
    final folders = widget.deps.store.folders;
    final activeFolderId = folders.any((f) => f.id == _selectedFolderId)
        ? _selectedFolderId
        : (folders.isNotEmpty ? folders.first.id : 'default');
    final selectedCount = _candidates.where((c) => c.selected).length;
    final allSelected =
        _candidates.isNotEmpty && _candidates.every((c) => c.selected);

    const switchTilePadding = EdgeInsets.only(
      left: Md3Spacing.s16,
      right: Md3Spacing.s24,
      top: Md3Spacing.s4,
      bottom: Md3Spacing.s4,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '批量识别 JM 车牌号',
          style: Md3Typography.emphasized(theme.textTheme.titleLarge),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          pageMargin,
          Md3Spacing.s8,
          pageMargin,
          Md3Spacing.s32,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Md3Spacing.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '粘贴含 JM 车牌号、链接或混排文本',
                                  style: Md3Typography.emphasized(
                                    theme.textTheme.titleSmall,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed:
                                    _isImporting ? null : _pasteFromClipboard,
                                icon: const Icon(
                                  Icons.content_paste_go_rounded,
                                  size: 18,
                                ),
                                label: const Text('粘贴'),
                              ),
                              TextButton(
                                onPressed: _isImporting ? null : _clearInput,
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                          const SizedBox(height: Md3Spacing.s8),
                          TextField(
                            key: const Key('jm_batch_input'),
                            controller: _inputCtrl,
                            enabled: !_isImporting,
                            minLines: 4,
                            maxLines: 8,
                            onChanged: _syncFromText,
                            decoration: const InputDecoration(
                              hintText:
                                  '支持示例：\nJM422866 / 车牌号：512345 / https://18comic.vip/album/654321\n或直接粘贴包含多组编号的推荐文本',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Md3SectionHeader('收藏选项'),
                  Md3SegmentedListGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Md3Spacing.s16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('目标收藏夹', style: theme.textTheme.labelLarge),
                            const SizedBox(height: Md3Spacing.s8),
                            Wrap(
                              spacing: Md3Spacing.s8,
                              runSpacing: Md3Spacing.s8,
                              children: [
                                ...folders.map((folder) {
                                  return ChoiceChip(
                                    selected: activeFolderId == folder.id,
                                    label: Text(folder.name),
                                    onSelected: _isImporting
                                        ? null
                                        : (_) => setState(
                                              () => _selectedFolderId = folder.id,
                                            ),
                                  );
                                }),
                                ActionChip(
                                  avatar: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('新建收藏夹'),
                                  onPressed:
                                      _isImporting ? null : _createFolderDialog,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: switchTilePadding,
                        title: const Text('获取漫画标题与封面'),
                        subtitle: const Text('从 JMComic 接口自动补充标题、作者与封面信息'),
                        value: _fetchMetadata,
                        onChanged: _isImporting
                            ? null
                            : (v) => setState(() => _fetchMetadata = v),
                      ),
                      SwitchListTile(
                        contentPadding: switchTilePadding,
                        title: const Text('拉取失败时保存占位条目'),
                        subtitle: const Text('网络异常或离线时仍保留 JM 车牌号到收藏夹'),
                        value: _saveFallbackOnError,
                        onChanged: _isImporting
                            ? null
                            : (v) => setState(() => _saveFallbackOnError = v),
                      ),
                      if (widget.deps.store.isJmLoggedIn)
                        SwitchListTile(
                          contentPadding: switchTilePadding,
                          title: const Text('同步到 JMComic 云端收藏'),
                          subtitle: const Text('同时提交至当前已登录账号的云端收藏夹'),
                          value: _syncCloud,
                          onChanged: _isImporting
                              ? null
                              : (v) => setState(() => _syncCloud = v),
                        ),
                    ],
                  ),

                  Md3SectionHeader(
                    '识别结果 (${_candidates.length})',
                    trailing: _candidates.isEmpty
                        ? null
                        : Wrap(
                            spacing: Md3Spacing.s4,
                            children: [
                              TextButton(
                                onPressed: _isImporting
                                    ? null
                                    : _excludeExistingFavorites,
                                child: const Text('排除已收藏'),
                              ),
                              TextButton(
                                onPressed:
                                    _isImporting ? null : _toggleSelectAll,
                                child: Text(allSelected ? '取消全选' : '全选'),
                              ),
                            ],
                          ),
                  ),

                  if (_isImporting) ...[
                    Card(
                      color: cs.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(Md3Spacing.s16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '正在处理 $_processed / $_totalToImport',
                                    style: Md3Typography.tabularFigures(
                                      theme.textTheme.labelLarge,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _cancelRequested = true),
                                  child: const Text('停止'),
                                ),
                              ],
                            ),
                            const SizedBox(height: Md3Spacing.s8),
                            LinearProgressIndicator(
                              value: _totalToImport > 0
                                  ? _processed / _totalToImport
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Md3Spacing.s8),
                  ],

                  if (_candidates.isEmpty)
                    Card(
                      color: cs.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(Md3Spacing.s24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.manage_search_rounded,
                              size: 40,
                              color: cs.primary,
                            ),
                            const SizedBox(height: Md3Spacing.s12),
                            Text(
                              '等待输入或粘贴内容',
                              style: Md3Typography.emphasized(
                                theme.textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(height: Md3Spacing.s4),
                            Text(
                              '自动过滤日期、E-Hentai 画廊链接与长数字，提取有效 JM 编号并去重。',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Md3SegmentedListGroup(
                      children: _candidates.map((item) {
                        final isExisting = widget.deps.store.isFavorite(
                          ComicSource.jmcomic,
                          item.id,
                        );
                        return _CandidateRow(
                          item: item,
                          isExisting: isExisting,
                          enabled: !_isImporting,
                          onToggleSelected: () =>
                              setState(() => item.selected = !item.selected),
                          onOpenDetail: () => _openDetail(item),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: pageMargin,
              vertical: Md3Spacing.s12,
            ),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('jm_batch_import_submit'),
                    onPressed: (_isImporting || selectedCount == 0)
                        ? null
                        : _runBatchImport,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bookmark_add_rounded),
                    label: Text(
                      _isImporting
                          ? '正在收藏 ($_processed/$_totalToImport)...'
                          : '批量收藏已选 ($selectedCount)',
                      style: Md3Typography.tabularFigures(null),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.item,
    required this.isExisting,
    required this.enabled,
    required this.onToggleSelected,
    required this.onOpenDetail,
  });

  final _BatchCandidate item;
  final bool isExisting;
  final bool enabled;
  final VoidCallback onToggleSelected;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String? statusText;
    Color statusColor = cs.onSurfaceVariant;
    switch (item.status) {
      case _BatchCandidateStatus.idle:
        break;
      case _BatchCandidateStatus.fetching:
        statusText = '正在获取详情...';
        statusColor = cs.primary;
      case _BatchCandidateStatus.saved:
        statusText = '已收藏';
        statusColor = cs.primary;
      case _BatchCandidateStatus.savedFallback:
        statusText = '已保存占位';
        statusColor = cs.secondary;
      case _BatchCandidateStatus.failed:
        statusText = '失败：${item.errorMessage ?? "无法获取"}';
        statusColor = cs.error;
    }

    return InkWell(
      onTap: enabled ? onToggleSelected : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Md3Spacing.s8,
          Md3Spacing.s8,
          Md3Spacing.s8,
          Md3Spacing.s8,
        ),
        child: Row(
          children: [
            Checkbox(
              value: item.selected,
              onChanged: enabled ? (_) => onToggleSelected() : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Md3Spacing.s8,
                    runSpacing: Md3Spacing.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                          'JM${item.id}',
                          style: Md3Typography.tabularFigures(
                            Md3Typography.emphasized(
                              theme.textTheme.labelSmall?.copyWith(
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Md3Spacing.s8,
                          vertical: Md3Spacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(
                            Md3Shapes.extraSmall,
                          ),
                        ),
                        child: Text(
                          item.kind.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (isExisting)
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
                            '已收藏',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (item.summary != null &&
                      item.summary!.title.isNotEmpty &&
                      item.summary!.title != 'JM${item.id}') ...[
                    const SizedBox(height: Md3Spacing.s4),
                    Text(
                      item.summary!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Md3Typography.emphasized(theme.textTheme.bodyMedium),
                    ),
                  ],
                  if (statusText != null) ...[
                    const SizedBox(height: Md3Spacing.s2),
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: '查看详情',
              onPressed: onOpenDetail,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
