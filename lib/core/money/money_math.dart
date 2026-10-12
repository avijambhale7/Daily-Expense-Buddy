/// Integer-only helpers for money arithmetic.
///
/// Money is always an `int` count of minor units (e.g. paise, cents). Doubles
/// are never used for totals or comparisons; they appear only at the very edge
/// when a value is handed to a number formatter for display.
abstract final class MoneyMath {
  /// Divides [minor] by [divisor], rounding half away from zero.
  ///
  /// Used for averages such as "average per calendar day". [divisor] must be
  /// positive.
  static int divideRounded(int minor, int divisor) {
    if (divisor <= 0) {
      throw ArgumentError.value(divisor, 'divisor', 'must be positive');
    }
    final negative = minor < 0;
    final abs = minor.abs();
    final q = abs ~/ divisor;
    final r = abs % divisor;
    final rounded = (r * 2 >= divisor) ? q + 1 : q;
    return negative ? -rounded : rounded;
  }

  /// Share of [part] in [whole] in basis points (1/100 of a percent),
  /// rounded half up. Returns null when [whole] is zero.
  static int? shareBasisPoints(int part, int whole) {
    if (whole == 0) return null;
    return divideRounded(part * 10000, whole);
  }

  /// Percentage change from [previous] to [current] in basis points.
  ///
  /// Returns null when the comparison is not meaningful (previous is zero),
  /// so callers never display infinity or NaN.
  static int? changeBasisPoints({required int current, required int previous}) {
    if (previous == 0) return null;
    final diff = current - previous;
    final negative = diff < 0;
    final value = divideRounded(diff.abs() * 10000, previous.abs());
    return negative ? -value : value;
  }

  /// Sums a list of minor-unit amounts.
  static int sum(Iterable<int> values) {
    var total = 0;
    for (final v in values) {
      total += v;
    }
    return total;
  }
}
