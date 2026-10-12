import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'design_tokens.dart';

/// Builds the complete [ThemeData] for a palette and brightness.
///
/// This is the only place colours, typography and component styles are
/// defined. Screens use `Theme.of(context)` / [AppColors] tokens and never
/// hard-code their own colours.
abstract final class AppTheme {
  static const fontFamily = 'Inter';

  static ThemeData build(AppPalette palette, Brightness requested) {
    final brightness = palette.forcedBrightness ?? requested;
    var scheme = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    // Keep the exact brand colour as primary in light mode when it has
    // enough contrast with white text (WCAG AA, 4.5:1); containers stay soft.
    if (brightness == Brightness.light &&
        _contrast(palette.seed, Colors.white) >= 4.5) {
      scheme = scheme.copyWith(primary: palette.seed, onPrimary: Colors.white);
    }
    if (brightness == Brightness.dark && palette.darkSurface != null) {
      final s = palette.darkSurface!;
      scheme = scheme.copyWith(
        surface: s,
        surfaceContainerLowest: Color.lerp(s, Colors.black, 0.4),
        surfaceContainerLow: Color.lerp(s, Colors.white, 0.03),
        surfaceContainer: Color.lerp(s, Colors.white, 0.05),
        surfaceContainerHigh: Color.lerp(s, Colors.white, 0.08),
        surfaceContainerHighest: Color.lerp(s, Colors.white, 0.11),
      );
    }

    final isDark = brightness == Brightness.dark;
    final text = _textTheme(scheme);
    final appColors = AppColors.resolve(scheme);
    final cardColor = isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;
    final background = isDark ? scheme.surface : scheme.surfaceContainerLow;
    final radiusMd = BorderRadius.circular(Radii.md);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [appColors],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        // Light mode: soft shadow on a tinted background. Dark mode: shadows
        // are invisible, so a hairline outline separates cards instead.
        elevation: isDark ? 0 : 1.5,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0 : 0.08),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl - 4),
          side: isDark
              ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))
              : BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        extendedTextStyle: text.labelLarge,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        border: OutlineInputBorder(borderRadius: radiusMd),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        errorMaxLines: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelLarge?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        width: null,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        backgroundColor: cardColor,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          textStyle: text.labelLarge,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        textStyle: text.bodyMedium,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
      ),
    );
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static TextTheme _textTheme(ColorScheme s) {
    TextStyle t(
      double size,
      FontWeight weight,
      double height, [
      double ls = 0,
    ]) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: ls,
    );
    final base = TextTheme(
      displayLarge: t(48, FontWeight.w700, 1.1, -0.5),
      displayMedium: t(40, FontWeight.w700, 1.12, -0.4),
      displaySmall: t(34, FontWeight.w700, 1.15, -0.3),
      headlineLarge: t(30, FontWeight.w700, 1.2, -0.2),
      headlineMedium: t(26, FontWeight.w700, 1.22, -0.1),
      headlineSmall: t(22, FontWeight.w600, 1.27),
      titleLarge: t(20, FontWeight.w600, 1.3),
      titleMedium: t(16, FontWeight.w600, 1.4),
      titleSmall: t(14, FontWeight.w600, 1.4),
      bodyLarge: t(16, FontWeight.w400, 1.5),
      bodyMedium: t(14, FontWeight.w400, 1.45),
      bodySmall: t(12, FontWeight.w400, 1.4),
      labelLarge: t(14, FontWeight.w600, 1.3),
      labelMedium: t(12, FontWeight.w500, 1.3),
      labelSmall: t(11, FontWeight.w500, 1.3, 0.2),
    ).apply(bodyColor: s.onSurface, displayColor: s.onSurface);
    return base.copyWith(
      bodySmall: base.bodySmall?.copyWith(color: s.onSurfaceVariant),
      labelSmall: base.labelSmall?.copyWith(color: s.onSurfaceVariant),
    );
  }
}

/// Typography helpers for financial figures.
extension AmountTextStyle on TextStyle {
  /// Tabular (fixed-width) digits so amounts align in lists and tables.
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
