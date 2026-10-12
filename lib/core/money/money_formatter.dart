import 'package:intl/intl.dart';

import 'currency.dart';

/// Locale-aware currency formatting for minor-unit amounts.
///
/// Conversion to `double` happens only here, for display. Amounts are capped
/// by [MoneyParser.maxMajorUnits], which keeps them exactly representable.
class MoneyFormatter {
  MoneyFormatter({required this.locale, required this.currencyCode})
    : currency = Currencies.byCode(currencyCode);

  final String locale;
  final String currencyCode;
  final CurrencyConfiguration currency;

  late final NumberFormat _full = NumberFormat.currency(
    locale: locale,
    name: currency.code,
    symbol: currency.symbol,
    decimalDigits: currency.minorDigits,
  );

  late final NumberFormat _compact = NumberFormat.compactCurrency(
    locale: locale,
    name: currency.code,
    symbol: currency.symbol,
    decimalDigits: currency.minorDigits == 0 ? 0 : null,
  );

  late final NumberFormat _plain = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: currency.minorDigits,
  );

  double _major(int minor) => minor / currency.minorFactor;

  /// e.g. `₹1,23,456.50`
  String format(int minorUnits) => _full.format(_major(minorUnits));

  /// e.g. `₹1.2L` / `$12K`, for chart axes and calendar cells.
  String compact(int minorUnits) {
    if (minorUnits.abs() < 1000 * currency.minorFactor) {
      return NumberFormat.currency(
        locale: locale,
        name: currency.code,
        symbol: currency.symbol,
        decimalDigits: 0,
      ).format(_major(minorUnits).round());
    }
    return _compact.format(_major(minorUnits));
  }

  /// Number without currency symbol, e.g. `1,234.50` (used in CSV export).
  String plain(int minorUnits) => _plain.format(_major(minorUnits));

  /// Percent from basis points, e.g. `12.5%`.
  static String percentFromBasisPoints(int basisPoints, {String? locale}) {
    final f = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: basisPoints.abs() % 100 == 0 ? 0 : 1,
    );
    return '${f.format(basisPoints / 100)}%';
  }
}
