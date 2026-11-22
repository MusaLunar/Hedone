import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

const double _compactWidth = 68.0;
const double _expandedWidth = 220.0;
const double _itemHeight = 44.0;
const double _itemGap = 4.0;
const double _sideInset = 10.0;
const double _iconBoxWidth = 48.0;
const double _indicatorWidth = 3.0;
const double _indicatorHeight = 18.0;
const Duration _expandDuration = Duration(milliseconds: 250);
const Duration _indicatorDuration = Duration(milliseconds: 320);

class PrismSidebarDestination {
  const PrismSidebarDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
}

/// Ported from FlClash / `prism_ui/lib/sidebar.dart`.
///
/// Animated desktop/tablet sidebar with smooth `68dp <-> 220dp` collapse,
/// `OverflowBox`-clipped labels so text never reflows during transition,
/// stretching active indicator pill (`_SelectionIndicator`), and bottom footer slot.
class PrismSidebar extends StatelessWidget {
  const PrismSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.expanded,
    required this.onSelected,
    required this.onToggle,
    this.footer,
    this.footerBuilder,
  });

  final List<PrismSidebarDestination> destinations;
  final int selectedIndex;
  final bool expanded;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggle;
  final Widget? footer;
  final Widget Function(BuildContext context, double expandProgress)?
      footerBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion ? Duration.zero : _expandDuration;

    return SafeArea(
      right: false,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: expanded ? 1.0 : 0.0),
        duration: duration,
        curve: Easing.standard,
        builder: (context, progress, _) {
          final width = lerpDouble(_compactWidth, _expandedWidth, progress)!;
          final labelOpacity = ((progress - 0.35) / 0.65).clamp(0.0, 1.0);
          final rowWidth = _expandedWidth - _sideInset * 2;

          return Material(
            color: cs.surfaceContainerLow,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Header: Toggle Button & Brand Mark
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sideInset,
                      10,
                      _sideInset,
                      8,
                    ),
                    child: SizedBox(
                      height: _itemHeight,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: AlignmentDirectional.centerStart,
                          minWidth: rowWidth,
                          maxWidth: rowWidth,
                          minHeight: _itemHeight,
                          maxHeight: _itemHeight,
                          child: Row(
                            children: [
                              SizedBox(
                                width: _iconBoxWidth,
                                height: _itemHeight,
                                child: IconButton(
                                  tooltip: expanded ? '收起侧边栏' : '展开侧边栏',
                                  onPressed: onToggle,
                                  icon: Icon(
                                    expanded
                                        ? Icons.menu_open_rounded
                                        : Icons.menu_rounded,
                                  ),
                                ),
                              ),
                              if (labelOpacity > 0.01) ...[
                                const SizedBox(width: 8),
                                Opacity(
                                  opacity: labelOpacity,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ExcludeSemantics(
                                        child: ClipRSuperellipse(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.asset(
                                            'assets/images/logo.png',
                                            width: 24,
                                            height: 24,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Hedone',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Destinations Stack with Stretching Indicator Pill
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _sideInset,
                        vertical: 4,
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < destinations.length; i++) ...[
                                if (i > 0) const SizedBox(height: _itemGap),
                                _SidebarTile(
                                  destination: destinations[i],
                                  selected: i == selectedIndex,
                                  expandedWidth: rowWidth,
                                  labelOpacity: labelOpacity,
                                  showTooltip: progress < 0.7,
                                  onTap: () => onSelected(i),
                                ),
                              ],
                            ],
                          ),
                          if (selectedIndex >= 0 &&
                              selectedIndex < destinations.length)
                            _StretchingSelectionIndicator(
                              color: cs.primary,
                              index: selectedIndex,
                              stride: _itemHeight + _itemGap,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Footer Slot (single quick Dark/Light toggle)
                  if (footerBuilder != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _sideInset,
                        8,
                        _sideInset,
                        14,
                      ),
                      child: footerBuilder!(context, progress),
                    )
                  else if (footer != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _sideInset,
                        8,
                        _sideInset,
                        14,
                      ),
                      child: footer!,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.destination,
    required this.selected,
    required this.expandedWidth,
    required this.labelOpacity,
    required this.showTooltip,
    required this.onTap,
  });

  final PrismSidebarDestination destination;
  final bool selected;
  final double expandedWidth;
  final double labelOpacity;
  final bool showTooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = selected ? cs.primary : cs.onSurfaceVariant;
    final itemShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(10),
    );

    Widget iconWidget = Icon(
      selected ? destination.selectedIcon : destination.icon,
      size: 22,
      color: fg,
    );
    if (destination.badgeCount > 0) {
      iconWidget = Badge.count(
        count: destination.badgeCount,
        child: iconWidget,
      );
    }

    final tile = Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
        shape: itemShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: itemShape,
          onTap: onTap,
          child: SizedBox(
            height: _itemHeight,
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: expandedWidth,
                maxWidth: expandedWidth,
                minHeight: _itemHeight,
                maxHeight: _itemHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _iconBoxWidth,
                      child: Center(child: iconWidget),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Opacity(
                        opacity: labelOpacity,
                        alwaysIncludeSemantics: true,
                        child: Text(
                          destination.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: selected ? cs.onSurface : cs.onSurfaceVariant,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!showTooltip) return tile;
    return Tooltip(
      message: destination.label,
      excludeFromSemantics: true,
      child: tile,
    );
  }
}

/// Stretches the leading edge toward the new row before the trailing edge catches up
/// (`prism_ui/lib/sidebar.dart` `_SelectionIndicator`).
class _StretchingSelectionIndicator extends StatefulWidget {
  const _StretchingSelectionIndicator({
    required this.color,
    required this.index,
    required this.stride,
  });

  final Color color;
  final int index;
  final double stride;

  @override
  State<_StretchingSelectionIndicator> createState() =>
      _StretchingSelectionIndicatorState();
}

class _StretchingSelectionIndicatorState
    extends State<_StretchingSelectionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _indicatorDuration,
    value: 1,
  );
  late int _from = widget.index;

  @override
  void didUpdateWidget(covariant _StretchingSelectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _from = oldWidget.index;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _topOf(int index) =>
      index * widget.stride + (_itemHeight - _indicatorHeight) / 2;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final from = _topOf(_from);
        final to = _topOf(widget.index);
        final lead = Curves.easeOutCubic.transform(math.min(1.0, t / 0.6));
        final trail = Curves.easeInOutCubic.transform(
          math.max(0.0, (t - 0.35) / 0.65),
        );
        final (top, bottom) = to >= from
            ? (lerpDouble(from, to, trail)!, lerpDouble(from, to, lead)!)
            : (lerpDouble(from, to, lead)!, lerpDouble(from, to, trail)!);
        return PositionedDirectional(
          start: 2,
          top: top,
          width: _indicatorWidth,
          height: bottom - top + _indicatorHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      },
    );
  }
}
