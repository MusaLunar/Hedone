import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_dependencies.dart';
import '../../../core/theme/md3_tokens.dart';
import '../../../domain/models/comic_item.dart';
import '../../../domain/models/comic_source.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/models/reader_models.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/jm_descrambled_image.dart';
import 'reader_view_model.dart';

class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.deps,
    required this.summary,
    this.detail,
    this.initialChapter,
    this.initialPageIndex = 0,
    this.offlineTask,
  });

  final AppDependencies deps;
  final ComicSummary summary;
  final ComicDetail? detail;
  final ComicChapter? initialChapter;
  final int initialPageIndex;
  final DownloadTask? offlineTask;

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late final ReaderViewModel _vm;
  late PageController _pageController;
  late ScrollController _webtoonScrollController;
  final FocusNode _focusNode = FocusNode();

  bool _showHud = true;
  bool _isAnimatingPage = false;

  @override
  void initState() {
    super.initState();
    _vm = ReaderViewModel(
      deps: widget.deps,
      summary: widget.summary,
      detail: widget.detail,
      initialChapter: widget.initialChapter,
      initialPageIndex: widget.initialPageIndex,
      offlineTask: widget.offlineTask,
    );
    _pageController = PageController(initialPage: _initialControllerPage());
    _webtoonScrollController = ScrollController();
    _webtoonScrollController.addListener(_onWebtoonScroll);
    _vm.addListener(_onVmUpdated);
    _vm.init().then((_) {
      if (mounted && _vm.mode == ReaderMode.webtoon && widget.initialPageIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToPage(widget.initialPageIndex);
        });
      }
    });
    widget.deps.store.addListener(_onStoreChanged);
  }

  int _initialControllerPage() {
    if (_vm.mode == ReaderMode.doublePage) {
      return widget.initialPageIndex ~/ 2;
    }
    return widget.initialPageIndex;
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onStoreChanged);
    _vm.removeListener(_onVmUpdated);
    _pageController.dispose();
    _webtoonScrollController.dispose();
    _focusNode.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onVmUpdated() {
    if (!mounted) return;
    if (_vm.mode != ReaderMode.webtoon && _pageController.hasClients) {
      final target = _vm.mode == ReaderMode.doublePage
          ? _vm.currentPageIndex ~/ 2
          : _vm.currentPageIndex;
      if ((_pageController.page?.round() ?? 0) != target && !_isAnimatingPage) {
        _pageController.jumpToPage(target);
      }
    }
  }

  void _onWebtoonScroll() {
    if (!_webtoonScrollController.hasClients || _vm.pages.isEmpty) return;
    final pos = _webtoonScrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    final ratio = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
    final estimated = (ratio * (_vm.pages.length - 1)).round();
    if (estimated != _vm.currentPageIndex) {
      _vm.onPageChanged(estimated);
    }
  }

  void _jumpToPage(int pageIndex) {
    if (_vm.pages.isEmpty) return;
    final clamped = pageIndex.clamp(0, _vm.pages.length - 1);
    _vm.onPageChanged(clamped);

    if (_vm.mode == ReaderMode.webtoon) {
      if (_webtoonScrollController.hasClients) {
        final max = _webtoonScrollController.position.maxScrollExtent;
        final ratio = _vm.pages.length <= 1 ? 0.0 : clamped / (_vm.pages.length - 1);
        _webtoonScrollController.jumpTo(max * ratio);
      }
    } else if (_pageController.hasClients) {
      final target = _vm.mode == ReaderMode.doublePage ? clamped ~/ 2 : clamped;
      _pageController.jumpToPage(target);
    }
  }

  void _turnPage(int delta) {
    if (_vm.pages.isEmpty) return;
    if (_vm.mode == ReaderMode.webtoon) {
      if (_webtoonScrollController.hasClients) {
        final vh = MediaQuery.sizeOf(context).height * 0.78;
        final next = (_webtoonScrollController.offset + delta * vh).clamp(
          0.0,
          _webtoonScrollController.position.maxScrollExtent,
        );
        _webtoonScrollController.animateTo(
          next,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    final step = _vm.mode == ReaderMode.doublePage ? delta * 2 : delta;
    final nextIdx = (_vm.currentPageIndex + step).clamp(0, _vm.pages.length - 1);
    final controllerTarget =
        _vm.mode == ReaderMode.doublePage ? nextIdx ~/ 2 : nextIdx;
    _isAnimatingPage = true;
    _pageController
        .animateToPage(
          controllerTarget,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _isAnimatingPage = false);
  }

  void _handleTapPosition(TapUpDetails details) {
    final size = MediaQuery.sizeOf(context);
    final dxRatio = details.localPosition.dx / size.width;
    if (dxRatio >= 0.3 && dxRatio <= 0.7) {
      setState(() => _showHud = !_showHud);
      return;
    }
    final isRtl = _vm.mode == ReaderMode.rtlPaged;
    if (dxRatio < 0.3) {
      _turnPage(isRtl ? 1 : -1);
    } else {
      _turnPage(isRtl ? -1 : 1);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isRtl = _vm.mode == ReaderMode.rtlPaged;

    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _turnPage(isRtl ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _turnPage(isRtl ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      _turnPage(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _turnPage(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showReaderSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '阅读设置',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '阅读模式',
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ReaderMode.values.map((m) {
                        return ChoiceChip(
                          selected: _vm.mode == m,
                          label: Text(m.label),
                          onSelected: (_) async {
                            final curPage = _vm.currentPageIndex;
                            await _vm.setMode(m);
                            _pageController.dispose();
                            _pageController = PageController(
                              initialPage: m == ReaderMode.doublePage
                                  ? curPage ~/ 2
                                  : curPage,
                            );
                            setModalState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.brightness_6_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Text('夜间调光'),
                        const Spacer(),
                        Text(
                          '${(widget.deps.store.readerBrightness * 100).round()}%',
                        ),
                      ],
                    ),
                    Slider(
                      value: widget.deps.store.readerBrightness,
                      min: 0.2,
                      max: 1.0,
                      onChanged: (v) async {
                        await widget.deps.store.setReaderBrightness(v);
                        setModalState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showChapterPicker() async {
    if (_vm.chapters.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _vm.chapters.length,
            itemBuilder: (_, idx) {
              final ch = _vm.chapters[idx];
              final isCurrent = ch.id == _vm.currentChapter?.id;
              return ListTile(
                title: Text(ch.title),
                selected: isCurrent,
                trailing: isCurrent ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _vm.switchChapter(ch);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSinglePageWidget(int index) {
    final page = _vm.pages[index];
    if (widget.summary.source == ComicSource.ehentai &&
        page.localFilePath == null &&
        (page.imageUrl == null || page.imageUrl!.isEmpty) &&
        !page.isLoading &&
        page.errorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _vm.ensureEhPageResolved(index);
      });
    }

    if (widget.summary.source == ComicSource.jmcomic) {
      return JmDescrambledImage(
        chapterId: page.chapterId,
        imageUrl: page.imageUrl ?? '',
        scrambleId: page.scrambleId,
        localFilePath: page.localFilePath,
        httpClient: widget.deps.httpClient,
        fit: _vm.mode == ReaderMode.webtoon ? BoxFit.fitWidth : BoxFit.contain,
      );
    }

    // E-Hentai page
    if (page.isLoading) {
      return const SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 10),
              Text('正在解析 E-Hentai 图片地址...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (page.errorMessage != null) {
      return SizedBox(
        height: 280,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, color: Colors.redAccent, size: 42),
                const SizedBox(height: 8),
                Text(
                  page.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _vm.ensureEhPageResolved(index, forceNlReload: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('使用 nl 节点重新加载'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return HedoneImage(
      url: page.imageUrl ?? '',
      localFilePath: page.localFilePath,
      httpClient: widget.deps.httpClient,
      headers: widget.deps.ehApi.buildHeaders(useExHentai: widget.deps.ehRepo.isExHentai),
      fit: _vm.mode == ReaderMode.webtoon ? BoxFit.fitWidth : BoxFit.contain,
      errorBuilder: (_, err, retry) {
        return SizedBox(
          height: 280,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, color: Colors.redAccent, size: 40),
                const SizedBox(height: 8),
                Text(
                  '加载失败: $err',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(onPressed: retry, child: const Text('重试')),
                    if (page.skipHathKey != null)
                      OutlinedButton(
                        onPressed: () =>
                            _vm.ensureEhPageResolved(index, forceNlReload: true),
                        child: const Text('切换 nl 节点'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReaderBody() {
    if (_vm.isLoadingChapter) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_vm.error != null && _vm.pages.isEmpty) {
      return AsyncStatePlaceholder(
        isLoading: false,
        error: _vm.error,
        isEmpty: true,
        onRetry: _vm.init,
      );
    }
    if (_vm.pages.isEmpty) {
      return const Center(
        child: Text('本章节暂无图片', style: TextStyle(color: Colors.white70)),
      );
    }

    switch (_vm.mode) {
      case ReaderMode.webtoon:
        return InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: ListView.builder(
            controller: _webtoonScrollController,
            padding: const EdgeInsets.symmetric(vertical: 48),
            itemCount: _vm.pages.length,
            itemBuilder: (_, index) => _buildSinglePageWidget(index),
          ),
        );

      case ReaderMode.rtlPaged:
      case ReaderMode.ltrPaged:
        return PageView.builder(
          controller: _pageController,
          reverse: _vm.mode == ReaderMode.rtlPaged,
          itemCount: _vm.pages.length,
          onPageChanged: _vm.onPageChanged,
          itemBuilder: (_, index) {
            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(child: _buildSinglePageWidget(index)),
            );
          },
        );

      case ReaderMode.doublePage:
        final spreadCount = (_vm.pages.length / 2).ceil();
        return PageView.builder(
          controller: _pageController,
          itemCount: spreadCount,
          onPageChanged: (spreadIndex) => _vm.onPageChanged(spreadIndex * 2),
          itemBuilder: (_, spreadIndex) {
            final first = spreadIndex * 2;
            final second = first + 1;
            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Row(
                children: [
                  Expanded(
                    child: Center(child: _buildSinglePageWidget(first)),
                  ),
                  if (second < _vm.pages.length)
                    Expanded(
                      child: Center(child: _buildSinglePageWidget(second)),
                    )
                  else
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            );
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brightness = widget.deps.store.readerBrightness;
    final hudDuration = Md3Motion.duration(
      context,
      Md3Motion.fastEffectsDuration,
    );
    final hudCurve = Md3Motion.curve(context, Md3Motion.fastEffectsCurve);
    final isWide =
        !Md3Breakpoints.ofWidth(MediaQuery.sizeOf(context).width).isCompact;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final total = _vm.pages.length;
          final current = total == 0 ? 0 : (_vm.currentPageIndex + 1).clamp(1, total);
          final bottomHudContent = SafeArea(
            top: false,
            bottom: !isWide,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isWide ? Md3Spacing.s16 : Md3Spacing.s12,
                Md3Spacing.s8,
                isWide ? Md3Spacing.s16 : Md3Spacing.s12,
                Md3Spacing.s8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (total > 1)
                    Row(
                      children: [
                        Text(
                          '$current',
                          style: Md3Typography.tabularFigures(
                            theme.textTheme.labelMedium,
                          ),
                        ),
                        Expanded(
                          child: Directionality(
                            textDirection: _vm.mode == ReaderMode.rtlPaged
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Slider(
                              value: current.toDouble(),
                              min: 1,
                              max: total.toDouble(),
                              divisions: total > 1 ? total - 1 : 1,
                              label: '$current / $total',
                              onChanged: (v) => _jumpToPage(v.round() - 1),
                            ),
                          ),
                        ),
                        Text(
                          '$total',
                          style: Md3Typography.tabularFigures(
                            theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed:
                            _vm.hasPrevChapter ? _vm.goToPrevChapter : null,
                        icon: const Icon(Icons.skip_previous_rounded),
                        label: const Text('上一话'),
                      ),
                      if (_vm.chapters.length > 1)
                        TextButton.icon(
                          onPressed: _showChapterPicker,
                          icon: const Icon(Icons.list_rounded),
                          label: const Text('章节'),
                        ),
                      TextButton.icon(
                        onPressed:
                            _vm.hasNextChapter ? _vm.goToNextChapter : null,
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('下一话'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: _handleTapPosition,
                  child: _buildReaderBody(),
                ),

                // Software brightness dimmer overlay
                if (brightness < 0.99)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 1.0 - brightness),
                    ),
                  ),

                // Top HUD bar
                AnimatedPositioned(
                  duration: hudDuration,
                  curve: hudCurve,
                  top: _showHud ? 0 : -110,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: cs.surfaceContainer.withValues(alpha: 0.92),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _vm.currentChapter?.title ??
                                        widget.summary.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Md3Typography.emphasized(
                                      theme.textTheme.titleSmall,
                                    ),
                                  ),
                                  Text(
                                    '${_vm.mode.label} · $current / $total',
                                    style: Md3Typography.tabularFigures(
                                      theme.textTheme.labelSmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '阅读设置',
                              onPressed: _showReaderSettingsSheet,
                              icon: const Icon(Icons.tune_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom HUD bar (floating pill on wide screens, docked on compact)
                AnimatedPositioned(
                  duration: hudDuration,
                  curve: hudCurve,
                  bottom: _showHud ? 0 : -160,
                  left: 0,
                  right: 0,
                  child: isWide
                      ? SafeArea(
                          top: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Md3Spacing.s16,
                                ),
                                child: Material(
                                  color: cs.surfaceContainerHigh
                                      .withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(
                                    Md3Shapes.extraLarge,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: bottomHudContent,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Material(
                          color: cs.surfaceContainer.withValues(alpha: 0.92),
                          child: bottomHudContent,
                        ),
                ),

                // Subtle always-on corner page badge when HUD is hidden
                if (!_showHud && total > 0)
                  Positioned(
                    right: Md3Spacing.s12,
                    bottom: Md3Spacing.s12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Md3Spacing.s12,
                          vertical: Md3Spacing.s4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(Md3Shapes.medium),
                        ),
                        child: Text(
                          '$current / $total',
                          style: Md3Typography.tabularFigures(
                            Md3Typography.emphasized(
                              theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
