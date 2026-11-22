import 'package:flutter/material.dart';

import '../../core/theme/hedone_theme.dart';
import '../../core/theme/md3_tokens.dart';
import 'prism_motion.dart';

/// Ported from FlClash `lib/views/theme.dart` (`_ThemeModeItem`) and
/// `lib/views/theme_preview.dart` (`MiniScreen` / `_DiagonalClipper`).
///
/// Renders interactive miniature screen previews for System (diagonal Light/Dark),
/// Light, and Dark modes.
class PrismThemeModePicker extends StatelessWidget {
  const PrismThemeModePicker({
    super.key,
    required this.value,
    required this.seedColor,
    required this.amoledBlack,
    required this.contrastLevel,
    required this.floatingNavBar,
    required this.onChanged,
  });

  final ThemeMode value;
  final Color seedColor;
  final bool amoledBlack;
  final double contrastLevel;
  final bool floatingNavBar;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final lightScheme = HedoneTheme.buildTheme(
      brightness: Brightness.light,
      seedColor: seedColor,
      contrastLevel: contrastLevel,
    ).colorScheme;
    final darkScheme = HedoneTheme.buildTheme(
      brightness: Brightness.dark,
      seedColor: seedColor,
      amoledBlack: amoledBlack,
      contrastLevel: contrastLevel,
    ).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _ThemePreviewCard(
            label: '跟随系统',
            selected: value == ThemeMode.system,
            onTap: () => onChanged(ThemeMode.system),
            preview: Stack(
              fit: StackFit.expand,
              children: [
                _MiniScreen(
                  scheme: darkScheme,
                  floatingNavBar: floatingNavBar,
                ),
                ClipPath(
                  clipper: const _DiagonalClipper(),
                  child: _MiniScreen(
                    scheme: lightScheme,
                    floatingNavBar: floatingNavBar,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Md3Spacing.s12),
        Expanded(
          child: _ThemePreviewCard(
            label: '浅色',
            selected: value == ThemeMode.light,
            onTap: () => onChanged(ThemeMode.light),
            preview: _MiniScreen(
              scheme: lightScheme,
              floatingNavBar: floatingNavBar,
            ),
          ),
        ),
        const SizedBox(width: Md3Spacing.s12),
        Expanded(
          child: _ThemePreviewCard(
            label: '深色',
            selected: value == ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.dark),
            preview: _MiniScreen(
              scheme: darkScheme,
              floatingNavBar: floatingNavBar,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7),
        width: selected ? 2.0 : 1.0,
      ),
    );

    return PrismElasticPress(
      scaleDown: 0.96,
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerLow,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: cardShape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Md3Spacing.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: AspectRatio(
                    aspectRatio: 0.86,
                    child: ClipRSuperellipse(
                      borderRadius: BorderRadius.circular(10),
                      child: preview,
                    ),
                  ),
                ),
                const SizedBox(height: Md3Spacing.s8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (selected) ...[
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                      const SizedBox(width: Md3Spacing.s4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: selected ? cs.primary : cs.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  const _DiagonalClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.72, 0)
      ..lineTo(size.width * 0.28, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalClipper oldClipper) => false;
}

class _MiniScreen extends StatelessWidget {
  const _MiniScreen({
    required this.scheme,
    required this.floatingNavBar,
  });

  final ColorScheme scheme;
  final bool floatingNavBar;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: scheme.surface,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mini Header Bar
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 24,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Mini Two-Column Comic Grid
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              flex: 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              flex: 3,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Mini Floating Capsule Dock or Docked Bar
          Positioned(
            left: floatingNavBar ? 8 : 0,
            right: floatingNavBar ? 8 : 0,
            bottom: floatingNavBar ? 5 : 0,
            child: Container(
              height: floatingNavBar ? 12 : 14,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(floatingNavBar ? 999 : 0),
                border: floatingNavBar
                    ? Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.6,
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    width: 10,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  CircleAvatar(
                    radius: 2,
                    backgroundColor: scheme.onSurfaceVariant,
                  ),
                  CircleAvatar(
                    radius: 2,
                    backgroundColor: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
