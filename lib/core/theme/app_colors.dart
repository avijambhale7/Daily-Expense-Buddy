import 'package:material_ui/material_ui.dart';

/// Semantic colours that Material's [ColorScheme] does not cover.
/// Resolved per theme by `AppTheme.build`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.categoryPalette,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.spendingUp,
    required this.spendingDown,
    required this.chartBar,
    required this.chartBarMuted,
    required this.chartGrid,
    required this.statusComplete,
    required this.statusNoExpenses,
    required this.statusIncomplete,
  });

  /// 12 categorical colours used for categories and chart series. Tuned per
  /// brightness so each hue stays recognisable and readable.
  final List<Color> categoryPalette;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;

  /// Spending more than the previous period.
  final Color spendingUp;

  /// Spending less than the previous period.
  final Color spendingDown;
  final Color chartBar;
  final Color chartBarMuted;
  final Color chartGrid;
  final Color statusComplete;
  final Color statusNoExpenses;
  final Color statusIncomplete;

  Color category(int index) =>
      categoryPalette[index.clamp(0, categoryPalette.length - 1)];

  // Slots 0–7: validated categorical palette (fixed order: blue, orange,
  // aqua, yellow, magenta, green, violet, red). Slots 8–11 are extra hues for
  // custom categories; categories always render with icon + name, so identity
  // never relies on colour alone, and charts fold small slices into "Other".
  static const _lightCategories = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
    Color(0xFFE87BA4),
    Color(0xFF008300),
    Color(0xFF6250D6),
    Color(0xFFE34948),
    Color(0xFF1C5CAB),
    Color(0xFF9A6B4F),
    Color(0xFFA640C0),
    Color(0xFF78786F),
  ];

  static const _darkCategories = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
    Color(0xFF6DA7EC),
    Color(0xFFC4977B),
    Color(0xFFC77EE0),
    Color(0xFFA3A29A),
  ];

  factory AppColors.resolve(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return AppColors(
      categoryPalette: dark ? _darkCategories : _lightCategories,
      success: dark ? const Color(0xFF69DB7C) : const Color(0xFF1E8E4E),
      onSuccess: dark ? const Color(0xFF00391A) : Colors.white,
      successContainer: dark
          ? const Color(0xFF1B4D2E)
          : const Color(0xFFD3F5DF),
      warning: dark ? const Color(0xFFFFD43B) : const Color(0xFFB25E00),
      onWarning: dark ? const Color(0xFF3D2E00) : Colors.white,
      warningContainer: dark
          ? const Color(0xFF4D3B00)
          : const Color(0xFFFFEDC2),
      spendingUp: scheme.error,
      spendingDown: dark ? const Color(0xFF69DB7C) : const Color(0xFF1E8E4E),
      chartBar: scheme.primary,
      chartBarMuted: scheme.primary.withValues(alpha: 0.35),
      chartGrid: scheme.outlineVariant.withValues(alpha: 0.6),
      statusComplete: dark ? const Color(0xFF69DB7C) : const Color(0xFF1E8E4E),
      statusNoExpenses: scheme.tertiary,
      statusIncomplete: dark
          ? const Color(0xFFFFD43B)
          : const Color(0xFFB25E00),
    );
  }

  @override
  AppColors copyWith({List<Color>? categoryPalette}) => AppColors(
    categoryPalette: categoryPalette ?? this.categoryPalette,
    success: success,
    onSuccess: onSuccess,
    successContainer: successContainer,
    warning: warning,
    onWarning: onWarning,
    warningContainer: warningContainer,
    spendingUp: spendingUp,
    spendingDown: spendingDown,
    chartBar: chartBar,
    chartBarMuted: chartBarMuted,
    chartGrid: chartGrid,
    statusComplete: statusComplete,
    statusNoExpenses: statusNoExpenses,
    statusIncomplete: statusIncomplete,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      categoryPalette: [
        for (var i = 0; i < categoryPalette.length; i++)
          l(categoryPalette[i], other.categoryPalette[i]),
      ],
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      spendingUp: l(spendingUp, other.spendingUp),
      spendingDown: l(spendingDown, other.spendingDown),
      chartBar: l(chartBar, other.chartBar),
      chartBarMuted: l(chartBarMuted, other.chartBarMuted),
      chartGrid: l(chartGrid, other.chartGrid),
      statusComplete: l(statusComplete, other.statusComplete),
      statusNoExpenses: l(statusNoExpenses, other.statusNoExpenses),
      statusIncomplete: l(statusIncomplete, other.statusIncomplete),
    );
  }
}

extension AppThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
