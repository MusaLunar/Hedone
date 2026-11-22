import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'prism_motion.dart';

/// Propagates the extra bottom padding needed by scrollable views to clear the
/// floating capsule navigation dock (`FlClash` `BottomInsetScope` pattern).
class PrismBottomInsetScope extends InheritedWidget {
  const PrismBottomInsetScope({
    super.key,
    required this.inset,
    required super.child,
  });

  final double inset;

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PrismBottomInsetScope>()
            ?.inset ??
        0.0;
  }

  @override
  bool updateShouldNotify(PrismBottomInsetScope oldWidget) =>
      inset != oldWidget.inset;
}

class PrismDockDestination {
  const PrismDockDestination({
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

/// FlClash / `prism_ui`-style Liquid-Glass Floating Capsule Navigation Bar.
///
/// Features:
/// - 62dp frosted stadium capsule with adaptive light/dark specular glass rim.
/// - Spring-driven sliding selection lens (`dropletSpring`) with horizontal
///   velocity jelly stretch & squash.
/// - Interactive drag-to-scrub across tabs with press magnification and haptics.
class PrismNavigationDock extends StatefulWidget {
  const PrismNavigationDock({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.maxWidth = 420,
  });

  static const double barHeight = 62;
  static const double barPadding = 4;
  static const double bottomMargin = 14;
  static const double _lensMagnify = 0.12;
  static const double _jellyMaxStretch = 0.18;
  static const double _jellyMaxSquash = 0.12;

  final List<PrismDockDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double maxWidth;

  /// Recommended extra bottom scroll inset so content clears the floating dock.
  static double insetOf(BuildContext context) {
    return barHeight + bottomMargin + 16 + MediaQuery.paddingOf(context).bottom;
  }

  @override
  State<PrismNavigationDock> createState() => _PrismNavigationDockState();
}

class _PrismNavigationDockState extends State<PrismNavigationDock>
    with TickerProviderStateMixin {
  late final AnimationController _lensController = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final AnimationController _liftController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  bool _dragging = false;
  int _lastHapticIndex = -1;

  @override
  void initState() {
    super.initState();
    _lastHapticIndex = widget.selectedIndex;
  }

  @override
  void didUpdateWidget(covariant PrismNavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex && !_dragging) {
      _animateLensTo(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _lensController.dispose();
    _liftController.dispose();
    super.dispose();
  }

  void _animateLensTo(double target, {double? velocity}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _lensController.value = target;
      return;
    }
    _lensController.animateWith(
      SpringSimulation(
        dropletSpring,
        _lensController.value,
        target,
        velocity ?? _lensController.velocity,
      ),
    );
  }

  void _setLift(bool lifted) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _liftController.value = lifted ? 1.0 : 0.0;
      return;
    }
    if (lifted) {
      _liftController.forward();
    } else {
      _liftController.reverse();
    }
  }

  void _handleDragStart(DragStartDetails details, double trackWidth) {
    _dragging = true;
    _setLift(true);
    _updateDragPosition(details.localPosition.dx, trackWidth);
  }

  void _handleDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (!_dragging) return;
    _updateDragPosition(details.localPosition.dx, trackWidth);
  }

  void _updateDragPosition(double localX, double trackWidth) {
    final count = widget.destinations.length;
    if (count <= 1 || trackWidth <= 0) return;
    final pitch = trackWidth / count;
    final raw = (localX / pitch) - 0.5;
    final maxIdx = (count - 1).toDouble();
    // Subtle rubber-band overdrag past edges (`prism_ui` overdrag feel).
    final clamped = raw < 0
        ? raw * 0.25
        : (raw > maxIdx ? maxIdx + (raw - maxIdx) * 0.25 : raw);
    _lensController.value = clamped;

    final nearest = raw.round().clamp(0, count - 1);
    if (nearest != _lastHapticIndex) {
      _lastHapticIndex = nearest;
      HapticFeedback.selectionClick();
    }
  }

  void _handleDragEnd(DragEndDetails details, double trackWidth) {
    if (!_dragging) return;
    _dragging = false;
    _setLift(false);
    final count = widget.destinations.length;
    final target = _lensController.value.round().clamp(0, count - 1);
    final pitch = trackWidth / count;
    final velocityInItems =
        pitch > 0 ? (details.primaryVelocity ?? 0) / pitch : 0.0;
    _animateLensTo(
      target.toDouble(),
      velocity: velocityInItems.clamp(-12, 12),
    );
    if (target != widget.selectedIndex) {
      widget.onSelected(target);
    }
  }

  void _handleDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _setLift(false);
    _animateLensTo(widget.selectedIndex.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final count = widget.destinations.length;

    // Adaptive Liquid Glass surface calibrated after prism_ui LiquidGlassStyle.regular
    final glassFill = isDark
        ? Color.alphaBlend(
            cs.surfaceContainerHigh.withValues(alpha: 0.72),
            cs.surface.withValues(alpha: 0.68),
          )
        : const Color(0xCCFCFDFE);
    final borderTop = isDark
        ? Colors.white.withValues(alpha: 0.20)
        : Colors.white.withValues(alpha: 0.90);
    final borderBottom = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : cs.outlineVariant.withValues(alpha: 0.50);
    final lensFill = isDark
        ? cs.primary.withValues(alpha: 0.24)
        : cs.primary.withValues(alpha: 0.13);
    final lensRim = isDark
        ? cs.primary.withValues(alpha: 0.36)
        : Colors.white.withValues(alpha: 0.85);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        minHeight: PrismNavigationDock.barHeight,
        maxHeight: PrismNavigationDock.barHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: glassFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isDark ? borderTop : borderBottom,
                  width: 0.9,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    borderTop.withValues(alpha: isDark ? 0.14 : 0.55),
                    Colors.transparent,
                    borderBottom.withValues(alpha: isDark ? 0.08 : 0.12),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(PrismNavigationDock.barPadding),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth <= 0 ||
                        constraints.maxHeight <= 0 ||
                        count == 0) {
                      return const SizedBox.shrink();
                    }
                    final trackWidth = constraints.maxWidth;
                    final trackHeight = constraints.maxHeight;
                    final itemWidth = trackWidth / count;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) =>
                          _handleDragStart(d, trackWidth),
                      onHorizontalDragUpdate: (d) =>
                          _handleDragUpdate(d, trackWidth),
                      onHorizontalDragEnd: (d) => _handleDragEnd(d, trackWidth),
                      onHorizontalDragCancel: _handleDragCancel,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _lensController,
                          _liftController,
                        ]),
                        builder: (context, _) {
                          final lensPos = _lensController.value;
                          final lift = _liftController.value;
                          final velocity = _lensController.velocity.abs();
                          final stretch = (velocity / 20.0)
                              .clamp(0.0, PrismNavigationDock._jellyMaxStretch);
                          final squash = stretch *
                              (PrismNavigationDock._jellyMaxSquash /
                                  PrismNavigationDock._jellyMaxStretch);

                          final lensWidth =
                              (itemWidth * (1.0 + stretch + 0.06 * lift))
                                  .clamp(itemWidth * 0.85, trackWidth);
                          final lensHeight =
                              (trackHeight * (1.0 - squash + 0.04 * lift))
                                  .clamp(trackHeight * 0.80, trackHeight);

                          final centerX = (lensPos + 0.5) * itemWidth;
                          final lensLeft = (centerX - lensWidth / 2).clamp(
                            0.0,
                            (trackWidth - lensWidth).clamp(0.0, trackWidth),
                          );
                          final lensTop = (trackHeight - lensHeight) / 2;

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Sliding Liquid-Glass Selection Lens
                              Positioned(
                                left: lensLeft,
                                top: lensTop,
                                width: lensWidth,
                                height: lensHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: lensFill,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: lensRim,
                                      width: 0.9,
                                    ),
                                    boxShadow: lift > 0.02
                                        ? [
                                            BoxShadow(
                                              color: cs.primary.withValues(
                                                alpha: 0.18 * lift,
                                              ),
                                              blurRadius: 12 * lift,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                              // Destinations Row (no duplicated Icons/Text for a11y & test clarity)
                              Row(
                                children: [
                                  for (var i = 0; i < count; i++)
                                    _DockItem(
                                      destination: widget.destinations[i],
                                      focus: (1.0 - (lensPos - i).abs())
                                          .clamp(0.0, 1.0),
                                      lift: lift,
                                      magnify: PrismNavigationDock._lensMagnify,
                                      selected: i == widget.selectedIndex,
                                      onTapDown: () => _setLift(true),
                                      onTapCancel: () => _setLift(false),
                                      onTap: () {
                                        _setLift(false);
                                        if (i != widget.selectedIndex) {
                                          HapticFeedback.selectionClick();
                                          widget.onSelected(i);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.destination,
    required this.focus,
    required this.lift,
    required this.magnify,
    required this.selected,
    required this.onTapDown,
    required this.onTapCancel,
    required this.onTap,
  });

  final PrismDockDestination destination;
  final double focus;
  final double lift;
  final double magnify;
  final bool selected;
  final VoidCallback onTapDown;
  final VoidCallback onTapCancel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = Color.lerp(cs.onSurfaceVariant, cs.primary, focus)!;
    final scale = 1.0 + magnify * lift * focus;

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

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconWidget,
        const SizedBox(height: 2),
        Text(
          destination.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            height: 1.2,
            color: fg,
            fontWeight: focus > 0.5 ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onTapDown(),
          onTapCancel: onTapCancel,
          onTap: onTap,
          child: Center(
            child: (scale - 1.0).abs() < 0.0005
                ? content
                : Transform.scale(scale: scale, child: content),
          ),
        ),
      ),
    );
  }
}

/// Detached circular Liquid-Glass action orb matching [PrismNavigationDock] height,
/// used for the single quick Dark/Light theme toggle beside the dock on wide screens.
class PrismGlassActionOrb extends StatelessWidget {
  const PrismGlassActionOrb({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = PrismNavigationDock.barHeight,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassFill = isDark
        ? Color.alphaBlend(
            cs.surfaceContainerHigh.withValues(alpha: 0.72),
            cs.surface.withValues(alpha: 0.68),
          )
        : const Color(0xCCFCFDFE);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.20)
        : cs.outlineVariant.withValues(alpha: 0.50);

    return PrismElasticPress(
      scaleDown: 0.92,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.12),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color: glassFill,
                  shape: CircleBorder(
                    side: BorderSide(color: borderColor, width: 0.9),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPressed,
                    child: Center(child: icon),
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
