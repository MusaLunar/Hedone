import 'package:flutter/material.dart';

import '../../core/theme/md3_tokens.dart';

/// M3 Section header aligned to the 4dp spacing grid (`07-Development-Rules/android-ui-rules.md`).
class Md3SectionHeader extends StatelessWidget {
  const Md3SectionHeader(
    this.title, {
    super.key,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Md3Spacing.s4,
        Md3Spacing.s16,
        Md3Spacing.s4,
        Md3Spacing.s8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// M3 Expressive segmented list group (`02-Components/lists.md`).
/// Uses 16dp outer / 4dp inner corners with 2dp vertical gaps instead of repetitive dividers.
class Md3SegmentedListGroup extends StatelessWidget {
  const Md3SegmentedListGroup({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: Md3Spacing.s2),
          Material(
            color: cs.surfaceContainerLow,
            shape: RoundedSuperellipseBorder(
              borderRadius: Md3Shapes.segmentedItem(i, children.length),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: children[i],
            ),
          ),
        ],
      ],
    );
  }
}

/// Standard M3 list tile adhering to 16dp leading / 24dp trailing padding (`02-Components/lists.md:82-94`).
class Md3ListTile extends StatelessWidget {
  const Md3ListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      selectedTileColor: cs.primaryContainer,
      selectedColor: cs.onPrimaryContainer,
      contentPadding: const EdgeInsets.only(
        left: Md3Spacing.s16,
        right: Md3Spacing.s24,
        top: Md3Spacing.s4,
        bottom: Md3Spacing.s4,
      ),
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
    );
  }
}
