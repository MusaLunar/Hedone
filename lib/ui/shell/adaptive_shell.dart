import 'package:flutter/material.dart';

import '../../core/app_dependencies.dart';
import '../../core/theme/md3_tokens.dart';
import '../../domain/models/comic_source.dart';
import '../../domain/models/download_task.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../prism/prism_motion.dart';
import '../prism/prism_navigation_dock.dart';
import '../prism/prism_sidebar.dart';

/// Responsive shell combining FlClash's liquid-glass floating capsule dock and
/// collapsible animated sidebar (`lib/ui/prism/`).
/// - Default (`floatingNavBar == true`) or Compact (`< 600dp`): Floating [PrismNavigationDock].
///   - On `>= 600dp` widths, pairs a single detached [PrismGlassActionOrb] beside
///     the dock for instant Dark/Light switching without duplicating AppBar buttons.
/// - Wide (`>= 600dp`) with `floatingNavBar == false`: Animated [PrismSidebar]
///   (`68dp <-> 220dp`) with the single Dark/Light toggle pinned to the footer.
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({
    super.key,
    required this.deps,
  });

  final AppDependencies deps;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _selectedIndex = 0;
  int _tabTransitionCount = 0;
  SearchRequest? _searchRequest;
  int _searchTokenCounter = 0;
  bool? _railExpandedOverride;

  static const List<({IconData icon, IconData selectedIcon, String label})>
      _destinationSpecs = [
    (
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
      label: '探索',
    ),
    (
      icon: Icons.search_outlined,
      selectedIcon: Icons.search_rounded,
      label: '搜索',
    ),
    (
      icon: Icons.bookmarks_outlined,
      selectedIcon: Icons.bookmarks_rounded,
      label: '书架',
    ),
    (
      icon: Icons.download_outlined,
      selectedIcon: Icons.download_rounded,
      label: '下载',
    ),
    (
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: '设置',
    ),
  ];

  @override
  void initState() {
    super.initState();
    widget.deps.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.deps.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _selectTab(int idx) {
    if (idx == _selectedIndex) return;
    setState(() {
      _selectedIndex = idx;
      _tabTransitionCount++;
    });
  }

  void _navigateToTagSearch(ComicSource source, String tagQuery) {
    setState(() {
      _searchTokenCounter++;
      _searchRequest = SearchRequest(
        source: source,
        query: tagQuery,
        token: _searchTokenCounter,
      );
      if (_selectedIndex != 1) {
        _selectedIndex = 1;
        _tabTransitionCount++;
      }
    });
  }

  void _openSettings() => _selectTab(4);

  void _openExplore() => _selectTab(0);

  int _activeDownloadCount() {
    return widget.deps.store.downloads
        .where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.queued)
        .length;
  }

  Widget _buildTabContent(List<Widget> pages, BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final stack = IndexedStack(
      index: _selectedIndex,
      children: pages,
    );
    if (reducedMotion || _tabTransitionCount == 0) return stack;

    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(_tabTransitionCount),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: fadeTabDuration,
      curve: fadeTabCurve,
      builder: (context, t, child) {
        if (t >= 0.999) return child!;
        return Opacity(
          opacity: 0.88 + 0.12 * t,
          child: Transform.scale(
            scale: 0.992 + 0.008 * t,
            child: child,
          ),
        );
      },
      child: stack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeDownloads = _activeDownloadCount();
    final toggleTooltip = isDark ? '切换浅色模式' : '切换深色模式';

    final pages = [
      ExploreScreen(
        deps: widget.deps,
        onSearchTag: _navigateToTagSearch,
        onOpenSettings: _openSettings,
      ),
      SearchScreen(
        deps: widget.deps,
        externalRequest: _searchRequest,
        onSearchTag: _navigateToTagSearch,
      ),
      LibraryScreen(
        deps: widget.deps,
        onSearchTag: _navigateToTagSearch,
        onOpenSettings: _openSettings,
        onExplore: _openExplore,
      ),
      DownloadsScreen(
        deps: widget.deps,
        onSearchTag: _navigateToTagSearch,
        onExplore: _openExplore,
      ),
      SettingsScreen(deps: widget.deps),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final sizeClass = Md3Breakpoints.ofWidth(constraints.maxWidth);
        final useSidebar =
            !sizeClass.isCompact && !widget.deps.store.floatingNavBar;
        final isExpanded = _railExpandedOverride ?? sizeClass.isLargeOrWider;

        final dock = PrismNavigationDock(
          destinations: [
            for (var i = 0; i < _destinationSpecs.length; i++)
              PrismDockDestination(
                icon: _destinationSpecs[i].icon,
                selectedIcon: _destinationSpecs[i].selectedIcon,
                label: _destinationSpecs[i].label,
                badgeCount: i == 3 ? activeDownloads : 0,
              ),
          ],
          selectedIndex: _selectedIndex,
          onSelected: _selectTab,
        );

        final bottomOffset = PrismNavigationDock.bottomMargin +
            MediaQuery.paddingOf(context).bottom;

        return Scaffold(
          body: Row(
            children: [
              if (useSidebar) ...[
                PrismSidebar(
                  destinations: [
                    for (var i = 0; i < _destinationSpecs.length; i++)
                      PrismSidebarDestination(
                        icon: _destinationSpecs[i].icon,
                        selectedIcon: _destinationSpecs[i].selectedIcon,
                        label: _destinationSpecs[i].label,
                        badgeCount: i == 3 ? activeDownloads : 0,
                      ),
                  ],
                  selectedIndex: _selectedIndex,
                  expanded: isExpanded,
                  onSelected: _selectTab,
                  onToggle: () {
                    setState(() {
                      _railExpandedOverride = !isExpanded;
                    });
                  },
                  footerBuilder: (ctx, progress) {
                    final showFull = progress > 0.72;
                    final iconWidget = Icon(
                      isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                    );
                    if (showFull) {
                      return Opacity(
                        opacity: ((progress - 0.72) / 0.28).clamp(0.0, 1.0),
                        child: OutlinedButton.icon(
                          key: const Key('theme_mode_toggle_button'),
                          onPressed: () =>
                              widget.deps.store.toggleDarkLightMode(
                            theme.brightness,
                          ),
                          icon: iconWidget,
                          label: Text(isDark ? '切换浅色' : '切换深色'),
                        ),
                      );
                    }
                    return Center(
                      child: IconButton(
                        key: const Key('theme_mode_toggle_button'),
                        tooltip: toggleTooltip,
                        onPressed: () =>
                            widget.deps.store.toggleDarkLightMode(
                          theme.brightness,
                        ),
                        icon: iconWidget,
                      ),
                    );
                  },
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: PrismBottomInsetScope(
                        inset: useSidebar
                            ? 0
                            : PrismNavigationDock.insetOf(context),
                        child: _buildTabContent(pages, context),
                      ),
                    ),
                    if (!useSidebar)
                      Positioned(
                        left: Md3Spacing.s16,
                        right: Md3Spacing.s16,
                        bottom: bottomOffset,
                        child: sizeClass.isCompact
                            ? Center(child: dock)
                            : Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(child: dock),
                                    const SizedBox(width: Md3Spacing.s12),
                                    PrismGlassActionOrb(
                                      key: const Key('theme_mode_toggle_button'),
                                      tooltip: toggleTooltip,
                                      onPressed: () => widget.deps.store
                                          .toggleDarkLightMode(
                                        theme.brightness,
                                      ),
                                      icon: AnimatedSwitcher(
                                        duration: Md3Motion.duration(
                                          context,
                                          Md3Motion.fastEffectsDuration,
                                        ),
                                        child: Icon(
                                          isDark
                                              ? Icons.light_mode_rounded
                                              : Icons.dark_mode_rounded,
                                          key: ValueKey<bool>(isDark),
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
  }
}
