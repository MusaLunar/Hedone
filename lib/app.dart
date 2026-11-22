import 'package:flutter/material.dart';

import 'core/app_dependencies.dart';
import 'core/theme/hedone_theme.dart';
import 'ui/prism/prism_theme_cross_fade.dart';
import 'ui/shell/adaptive_shell.dart';

class HedoneApp extends StatefulWidget {
  const HedoneApp({
    super.key,
    required this.deps,
  });

  final AppDependencies deps;

  @override
  State<HedoneApp> createState() => _HedoneAppState();
}

class _HedoneAppState extends State<HedoneApp> {
  String? _cachedSeedId;
  bool? _cachedAmoledBlack;
  double? _cachedContrastLevel;
  late ThemeData _lightTheme;
  late ThemeData _darkTheme;

  void _ensureThemes() {
    final store = widget.deps.store;
    if (_cachedSeedId == store.themeSeedId &&
        _cachedAmoledBlack == store.amoledBlack &&
        _cachedContrastLevel == store.contrastLevel) {
      return;
    }
    _cachedSeedId = store.themeSeedId;
    _cachedAmoledBlack = store.amoledBlack;
    _cachedContrastLevel = store.contrastLevel;
    final seed = HedoneTheme.seedColorFromId(store.themeSeedId);
    _lightTheme = HedoneTheme.buildTheme(
      brightness: Brightness.light,
      seedColor: seed,
      contrastLevel: store.contrastLevel,
    );
    _darkTheme = HedoneTheme.buildTheme(
      brightness: Brightness.dark,
      seedColor: seed,
      amoledBlack: store.amoledBlack,
      contrastLevel: store.contrastLevel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.deps.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        _ensureThemes();
        final themeKey = (
          store.themeMode,
          store.themeSeedId,
          store.amoledBlack,
          store.contrastLevel,
        );
        return MaterialApp(
          title: 'Hedone',
          debugShowCheckedModeBanner: false,
          themeMode: store.themeMode,
          themeAnimationDuration: Duration.zero,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          builder: (context, child) {
            return PrismThemeCrossFade(
              themeKey: themeKey,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: AdaptiveShell(deps: widget.deps),
        );
      },
    );
  }
}
