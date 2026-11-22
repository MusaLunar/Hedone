import 'package:flutter/material.dart';

/// Official Material Design 3 width breakpoints (left-closed, right-open).
/// Ref: `01-Foundations/layout.md`
enum Md3WindowSizeClass {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  bool get isCompact => this == Md3WindowSizeClass.compact;
  bool get isTwoPaneEligible => index >= Md3WindowSizeClass.expanded.index;
  bool get isLargeOrWider => index >= Md3WindowSizeClass.large.index;
}

class Md3Breakpoints {
  static const double medium = 600.0;
  static const double expanded = 840.0;
  static const double large = 1200.0;
  static const double extraLarge = 1600.0;

  static Md3WindowSizeClass ofWidth(double width) {
    if (width < medium) return Md3WindowSizeClass.compact;
    if (width < expanded) return Md3WindowSizeClass.medium;
    if (width < large) return Md3WindowSizeClass.expanded;
    if (width < extraLarge) return Md3WindowSizeClass.large;
    return Md3WindowSizeClass.extraLarge;
  }

  /// Compact uses 16dp leading/trailing margins; Medium+ use 24dp.
  static double pageMargin(double width) {
    return width < medium ? 16.0 : 24.0;
  }

  static const double paneSpacer = 24.0;

  /// Fixed pane width in multi-pane layouts: 360dp on Expanded, 412dp on Large/XL.
  static double fixedPaneWidth(double width) {
    return width < large ? 360.0 : 412.0;
  }
}

/// 4dp spacing scale (`01-Foundations/spacing.md`, `07-Development-Rules/android-ui-rules.md`).
class Md3Spacing {
  static const double s2 = 2.0;
  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;

  /// M3 Cards spec horizontal/vertical collection gap (`02-Components/cards.md`).
  static const double cardHorizontalGap = 8.0;
  static const double cardVerticalGap = 12.0;
}

/// 10-step Material Design 3 Shape Scale (`01-Foundations/shape-system.md`).
class Md3Shapes {
  static const double none = 0.0;
  static const double extraSmall = 4.0;
  static const double small = 8.0;
  static const double medium = 12.0;
  static const double large = 16.0;
  static const double largeIncreased = 20.0;
  static const double extraLarge = 28.0;
  static const double extraLargeIncreased = 32.0;
  static const double extraExtraLarge = 48.0;
  static const double full = 9999.0;

  static BorderRadius rounded(double radius) => BorderRadius.circular(radius);

  static BorderRadius topRounded(double radius) => BorderRadius.vertical(
    top: Radius.circular(radius),
  );

  /// Concentric inner radius keeping optical alignment inside an outer container.
  static double concentricInner(double outerRadius, double inset) {
    return (outerRadius - inset).clamp(extraSmall, outerRadius);
  }

  /// Segmented list item shape (`02-Components/lists.md`: 16dp outer, 4dp inner).
  static BorderRadius segmentedItem(int index, int count) {
    if (count <= 1) return BorderRadius.circular(large);
    if (index == 0) {
      return const BorderRadius.vertical(
        top: Radius.circular(large),
        bottom: Radius.circular(extraSmall),
      );
    }
    if (index == count - 1) {
      return const BorderRadius.vertical(
        top: Radius.circular(extraSmall),
        bottom: Radius.circular(large),
      );
    }
    return BorderRadius.circular(extraSmall);
  }
}

/// Motion physics & reduced-motion helpers (`01-Foundations/motion.md`).
class Md3Motion {
  static const Duration fastSpatialDuration = Duration(milliseconds: 350);
  static const Duration defaultSpatialDuration = Duration(milliseconds: 500);
  static const Duration fastEffectsDuration = Duration(milliseconds: 150);
  static const Duration defaultEffectsDuration = Duration(milliseconds: 200);

  static const Curve fastSpatialCurve = Cubic(0.42, 1.67, 0.21, 0.90);
  static const Curve defaultSpatialCurve = Cubic(0.38, 1.21, 0.22, 1.00);
  static const Curve fastEffectsCurve = Cubic(0.31, 0.94, 0.34, 1.00);
  static const Curve defaultEffectsCurve = Cubic(0.34, 0.80, 0.34, 1.00);

  static Duration duration(BuildContext context, Duration base) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : base;
  }

  static Curve curve(BuildContext context, Curve base) {
    return MediaQuery.disableAnimationsOf(context) ? Curves.linear : base;
  }
}

/// CJK language height (+7%) & tabular figures helpers (`01-Foundations/typography.md`).
class Md3Typography {
  static const double cjkLanguageHeightScale = 1.07;

  static TextTheme applyCjkLanguageHeight(TextTheme base) {
    TextStyle? scale(TextStyle? style, double fallbackRatio, {FontWeight? weight}) {
      if (style == null) return null;
      final baseRatio = style.height ?? fallbackRatio;
      return style.copyWith(
        height: baseRatio * cjkLanguageHeightScale,
        fontWeight: weight ?? style.fontWeight,
      );
    }

    return base.copyWith(
      displayLarge: scale(base.displayLarge, 1.12),
      displayMedium: scale(base.displayMedium, 1.15),
      displaySmall: scale(base.displaySmall, 1.22),
      headlineLarge: scale(base.headlineLarge, 1.25),
      headlineMedium: scale(base.headlineMedium, 1.28),
      headlineSmall: scale(base.headlineSmall, 1.33, weight: FontWeight.w500),
      titleLarge: scale(base.titleLarge, 1.27, weight: FontWeight.w500),
      titleMedium: scale(base.titleMedium, 1.45, weight: FontWeight.w500),
      titleSmall: scale(base.titleSmall, 1.42, weight: FontWeight.w500),
      bodyLarge: scale(base.bodyLarge, 1.50),
      bodyMedium: scale(base.bodyMedium, 1.45),
      bodySmall: scale(base.bodySmall, 1.40),
      labelLarge: scale(base.labelLarge, 1.40, weight: FontWeight.w500),
      labelMedium: scale(base.labelMedium, 1.33, weight: FontWeight.w500),
      labelSmall: scale(base.labelSmall, 1.33, weight: FontWeight.w500),
    );
  }

  /// Applies emphasized weight (`w600` instead of blurry CJK `w800`) without altering size.
  static TextStyle? emphasized(TextStyle? style) {
    return style?.copyWith(fontWeight: FontWeight.w600);
  }

  /// Enables proportional-width avoidance for dynamic counters/ratings/latencies.
  static TextStyle? tabularFigures(TextStyle? style) {
    return style?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
