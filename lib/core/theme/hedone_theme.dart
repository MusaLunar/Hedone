import 'package:flutter/material.dart';

import '../../ui/prism/prism_motion.dart';
import 'md3_tokens.dart';

class ThemeSeedPreset {
  const ThemeSeedPreset({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;
}

class HedoneTheme {
  static const String fontFamily = 'SourceHanSansCN';

  static const List<ThemeSeedPreset> presets = [
    ThemeSeedPreset(
      id: 'celestial_lavender',
      name: '星夜紫 (Hedone)',
      color: Color(0xFF8B6FD4),
    ),
    ThemeSeedPreset(
      id: 'starlight_rose',
      name: '星光粉',
      color: Color(0xFFD97BB6),
    ),
    ThemeSeedPreset(
      id: 'abyssal_violet',
      name: '深渊堇',
      color: Color(0xFF6750A4),
    ),
    ThemeSeedPreset(
      id: 'emerald',
      name: '翡冷翠',
      color: Color(0xFF2E7D6B),
    ),
    ThemeSeedPreset(
      id: 'ocean',
      name: '深海蓝',
      color: Color(0xFF3B82F6),
    ),
  ];

  static Color seedColorFromId(String id) {
    return presets
        .firstWhere(
          (e) => e.id == id,
          orElse: () => presets.first,
        )
        .color;
  }

  static ThemeData buildTheme({
    required Brightness brightness,
    required Color seedColor,
    bool amoledBlack = false,
    double contrastLevel = 0.0,
  }) {
    var scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      contrastLevel: contrastLevel,
    );

    if (brightness == Brightness.dark && amoledBlack) {
      scheme = scheme.copyWith(
        surface: const Color(0xFF000000),
        surfaceContainerLowest: const Color(0xFF000000),
        surfaceContainerLow: const Color(0xFF0F0C16),
        surfaceContainer: const Color(0xFF15121F),
        surfaceContainerHigh: const Color(0xFF1D1929),
        surfaceContainerHighest: const Color(0xFF262135),
      );
    }

    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
    );

    final textTheme = Md3Typography.applyCjkLanguageHeight(baseTheme.textTheme);

    return baseTheme.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      // `surfaceTint` is deprecated in M3 (`elevation.md`); separation uses surfaceContainer roles.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 3,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Md3Shapes.medium),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 6,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Md3Shapes.extraLarge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainerLow,
        modalBarrierColor: scheme.scrim.withValues(alpha: 0.32),
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Md3Shapes.extraLarge),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PrismPageTransitionsBuilder(),
          TargetPlatform.iOS: PrismPageTransitionsBuilder(),
          TargetPlatform.windows: PrismPageTransitionsBuilder(),
          TargetPlatform.macOS: PrismPageTransitionsBuilder(),
          TargetPlatform.linux: PrismPageTransitionsBuilder(),
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.secondary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Md3Shapes.small),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        constraints: const BoxConstraints(minHeight: 56, maxWidth: 720),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Md3Shapes.medium),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Md3Spacing.s16,
          vertical: Md3Spacing.s12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
      ),
    );
  }
}
