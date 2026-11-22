import 'package:flutter/material.dart';

import '../../core/theme/md3_tokens.dart';

/// M3 Skeleton Loader grid (`01-Foundations/motion.md`: diagonal top-left to bottom-right pulse).
class Md3SkeletonGrid extends StatefulWidget {
  const Md3SkeletonGrid({
    super.key,
    this.itemCount = 12,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  State<Md3SkeletonGrid> createState() => _Md3SkeletonGridState();
}

class _Md3SkeletonGridState extends State<Md3SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disableAnim = MediaQuery.disableAnimationsOf(context);

    return GridView.builder(
      padding: widget.padding,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 196,
        mainAxisSpacing: Md3Spacing.cardVerticalGap,
        crossAxisSpacing: Md3Spacing.cardHorizontalGap,
        childAspectRatio: 0.62,
      ),
      itemCount: widget.itemCount,
      itemBuilder: (_, index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = disableAnim
                ? 0.5
                : ((_controller.value + (index % 4) * 0.14) % 1.0);
            final alpha = 0.45 + 0.35 * (1.0 - (phase - 0.5).abs() * 2.0);
            return Card(
              color: cs.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      color: cs.surfaceContainerHighest.withValues(alpha: alpha),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Md3Spacing.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh.withValues(alpha: alpha),
                            borderRadius: BorderRadius.circular(Md3Shapes.extraSmall),
                          ),
                        ),
                        const SizedBox(height: Md3Spacing.s8),
                        Container(
                          height: 10,
                          width: 90,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh.withValues(alpha: alpha),
                            borderRadius: BorderRadius.circular(Md3Shapes.extraSmall),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Material Design 3 empty/loading/error placeholder with actionable recovery CTA.
class AsyncStatePlaceholder extends StatelessWidget {
  const AsyncStatePlaceholder({
    super.key,
    required this.isLoading,
    required this.error,
    required this.isEmpty,
    required this.onRetry,
    this.emptyTitle = '暂无内容',
    this.emptySubtitle = '试试切换分类或下拉刷新',
    this.actionLabel,
    this.onAction,
    this.useSkeletonOnLoad = false,
  });

  final bool isLoading;
  final String? error;
  final bool isEmpty;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String emptySubtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool useSkeletonOnLoad;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (isLoading && isEmpty) {
      if (useSkeletonOnLoad) {
        return const Md3SkeletonGrid();
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Md3Spacing.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: Md3Spacing.s16),
              Text('正在加载漫画数据...', style: textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    if (error != null && isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Md3Spacing.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(Md3Spacing.s24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 40,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(height: Md3Spacing.s12),
                    Text(
                      '加载失败',
                      style: textTheme.titleMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Md3Spacing.s8),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: Md3Spacing.s16),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Md3Spacing.s32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 48,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: Md3Spacing.s12),
                Text(
                  emptyTitle,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium,
                ),
                if (emptySubtitle.isNotEmpty) ...[
                  const SizedBox(height: Md3Spacing.s4),
                  Text(
                    emptySubtitle,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: Md3Spacing.s16),
                  FilledButton.tonal(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Non-destructive inline error banner shown when cached items remain visible.
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      borderRadius: BorderRadius.circular(Md3Shapes.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Md3Spacing.s16,
          vertical: Md3Spacing.s8,
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: cs.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: Md3Spacing.s12),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(
                '重试',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
