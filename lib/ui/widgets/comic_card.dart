import 'package:flutter/material.dart';

import '../../core/network/app_http_client.dart';
import '../../core/theme/md3_tokens.dart';
import '../../data/ehentai/eh_url.dart';
import '../../domain/models/comic_item.dart';
import '../../domain/models/comic_source.dart';
import '../../domain/models/reader_models.dart';
import '../prism/prism_motion.dart';
import 'jm_descrambled_image.dart';

/// Material Design 3 + FlClash/Prism directly-actionable card.
/// Combines smooth superellipse geometry (14dp), tactile spring elastic press,
/// and subtle pointer hover border emphasis.
class ComicCard extends StatefulWidget {
  const ComicCard({
    super.key,
    required this.comic,
    required this.httpClient,
    required this.onTap,
    this.progress,
  });

  final ComicSummary comic;
  final AppHttpClient httpClient;
  final VoidCallback onTap;
  final ReadingProgress? progress;

  @override
  State<ComicCard> createState() => _ComicCardState();
}

class _ComicCardState extends State<ComicCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final comic = widget.comic;
    final progress = widget.progress;

    final isJm = comic.source == ComicSource.jmcomic;
    final badgeBg = isJm
        ? cs.primaryContainer
        : (comic.isExHentai ? cs.tertiaryContainer : cs.secondaryContainer);
    final badgeFg = isJm
        ? cs.onPrimaryContainer
        : (comic.isExHentai ? cs.onTertiaryContainer : cs.onSecondaryContainer);
    final cardShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: _hovered
            ? cs.primary.withValues(alpha: 0.55)
            : cs.outlineVariant.withValues(alpha: 0.35),
        width: _hovered ? 1.2 : 0.8,
      ),
    );

    return Semantics(
      button: true,
      label: '${comic.badgeLabel} ${comic.title}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PrismElasticPress(
          scaleDown: 0.97,
          child: Material(
            color: cs.surfaceContainerLow,
            shape: cardShape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: cardShape,
              onTap: widget.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRSuperellipse(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ExcludeSemantics(
                            child: HedoneImage(
                              url: comic.coverUrl,
                              httpClient: widget.httpClient,
                              fit: BoxFit.cover,
                            ),
                          ),
                    // Top & bottom scrim for accessible overlay contrast (`cards.md:117-122`)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              cs.scrim.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Top-left Source Badge
                    Positioned(
                      top: Md3Spacing.s8,
                      left: Md3Spacing.s8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Md3Spacing.s8,
                          vertical: Md3Spacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(Md3Shapes.small),
                        ),
                        child: Text(
                          comic.badgeLabel,
                          style: textTheme.labelSmall?.copyWith(
                            color: badgeFg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    // Top-right Category Badge
                    if (comic.category.isNotEmpty)
                      Positioned(
                        top: Md3Spacing.s8,
                        right: Md3Spacing.s8,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 92),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Md3Spacing.s8,
                            vertical: Md3Spacing.s2,
                          ),
                          decoration: BoxDecoration(
                            color: isJm
                                ? cs.inverseSurface.withValues(alpha: 0.85)
                                : EhUrl.categoryColor(comic.category)
                                    .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(Md3Shapes.small),
                          ),
                          child: Text(
                            comic.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              color: isJm ? cs.onInverseSurface : Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    // Bottom-left rating & Bottom-right pages (tabular figures)
                    Positioned(
                      left: Md3Spacing.s8,
                      right: Md3Spacing.s8,
                      bottom: Md3Spacing.s8,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (comic.rating != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: cs.tertiaryContainer,
                                ),
                                const SizedBox(width: Md3Spacing.s2),
                                Text(
                                  comic.rating!.toStringAsFixed(1),
                                  style: Md3Typography.tabularFigures(
                                    textTheme.labelSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            const SizedBox.shrink(),
                          if (comic.pageCount != null && comic.pageCount! > 0)
                            Text(
                              '${comic.pageCount}P',
                              style: Md3Typography.tabularFigures(
                                textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Reading progress bar at the bottom of cover
                    if (progress != null && progress.totalPages > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: ((progress.pageIndex + 1) / progress.totalPages)
                              .clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: cs.scrim.withValues(alpha: 0.35),
                        ),
                      ),
                  ],
                ),
              ),
            ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Md3Spacing.s12,
                  Md3Spacing.s8,
                  Md3Spacing.s12,
                  Md3Spacing.s12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (comic.subtitle.isNotEmpty) ...[
                      const SizedBox(height: Md3Spacing.s4),
                      Text(
                        comic.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }
}
