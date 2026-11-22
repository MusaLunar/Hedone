import 'package:flutter/material.dart';

import 'prism_motion.dart';

/// Ported from FlClash / `prism_ui/lib/segmented_control.dart`.
///
/// Full-capsule sliding pill segmented control (`AnimatedAlign` thumb +
/// `AnimatedDefaultTextStyle` label transition).
class PrismSegmentedControl<T> extends StatelessWidget {
  const PrismSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  static const double _height = 42;
  static const double _inset = 4;

  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = segments.length;
    final index = segments.indexWhere((s) => s.$1 == value);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final thumbDuration =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 250);
    final textDuration =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 200);

    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: cs.surfaceContainerHigh,
        shape: const StadiumBorder(),
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: thumbDuration,
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional(
                count <= 1 ? 0 : index * 2 / (count - 1) - 1,
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: count > 0 ? 1 / count : 1,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: cs.primary,
                    shape: const StadiumBorder(),
                    shadows: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.20),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final (option, label) in segments)
                Expanded(
                  child: PrismElasticPress(
                    scaleDown: 0.96,
                    enabled: option != value,
                    child: Semantics(
                      button: true,
                      selected: option == value,
                      label: label,
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: option == value ? null : () => onChanged(option),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: textDuration,
                            curve: Curves.easeOutCubic,
                            style: (theme.textTheme.labelLarge ??
                                    const TextStyle())
                                .copyWith(
                              color: option == value
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                              fontWeight: option == value
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
