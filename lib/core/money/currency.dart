import 'package:equatable/equatable.dart';

/// Static description of an ISO 4217 currency.
///
/// [minorDigits] is the number of digits after the decimal separator used by
/// the currency (2 for USD, 0 for JPY, 3 for KWD). All money in the app is
/// stored as an integer number of minor units using this precision.
class CurrencyConfiguration extends Equatable {
  const CurrencyConfiguration({
    required this.code,
    required this.name,
    required this.minorDigits,
    required this.symbol,
  });

  final String code;
  final String name;
  final int minorDigits;
  final String symbol;

  /// 10^minorDigits, i.e. the number of minor units in one major unit.
  int get minorFactor {
    var f = 1;
    for (var i = 0; i < minorDigits; i++) {
      f *= 10;
    }
    return f;
  }

  @override
  List<Object?> get props => [code, minorDigits];
}

/// Currencies supported for the reporting currency.
abstract final class Currencies {
  static const inr = CurrencyConfiguration(
    code: 'INR',
    name: 'Indian Rupee',
    minorDigits: 2,
    symbol: '₹',
  );
  static const usd = CurrencyConfiguration(
    code: 'USD',
    name: 'US Dollar',
    minorDigits: 2,
    symbol: r'$',
  );
  static const eur = CurrencyConfiguration(
    code: 'EUR',
    name: 'Euro',
    minorDigits: 2,
    symbol: '€',
  );
  static const gbp = CurrencyConfiguration(
    code: 'GBP',
    name: 'British Pound',
    minorDigits: 2,
    symbol: '£',
  );
  static const jpy = CurrencyConfiguration(
    code: 'JPY',
    name: 'Japanese Yen',
    minorDigits: 0,
    symbol: '¥',
  );
  static const aud = CurrencyConfiguration(
    code: 'AUD',
    name: 'Australian Dollar',
    minorDigits: 2,
    symbol: r'A$',
  );
  static const cad = CurrencyConfiguration(
    code: 'CAD',
    name: 'Canadian Dollar',
    minorDigits: 2,
    symbol: r'CA$',
  );
  static const aed = CurrencyConfiguration(
    code: 'AED',
    name: 'UAE Dirham',
    minorDigits: 2,
    symbol: 'AED',
  );
  static const sgd = CurrencyConfiguration(
    code: 'SGD',
    name: 'Singapore Dollar',
    minorDigits: 2,
    symbol: r'S$',
  );
  static const chf = CurrencyConfiguration(
    code: 'CHF',
    name: 'Swiss Franc',
    minorDigits: 2,
    symbol: 'CHF',
  );
  static const kwd = CurrencyConfiguration(
    code: 'KWD',
    name: 'Kuwaiti Dinar',
    minorDigits: 3,
    symbol: 'KWD',
  );

  static const List<CurrencyConfiguration> all = [
    inr,
    usd,
    eur,
    gbp,
    jpy,
    aud,
    cad,
    aed,
    sgd,
    chf,
    kwd,
  ];

  static bool isSupported(String code) => all.any((c) => c.code == code);

  /// Returns the configuration for [code]. Unknown codes fall back to a
  /// 2-digit configuration so historical data is never dropped.
  static CurrencyConfiguration byCode(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return CurrencyConfiguration(
      code: code,
      name: code,
      minorDigits: 2,
      symbol: code,
    );
  }

  /// Best-effort default currency for a locale such as `en_IN`.
  static String defaultForLocale(String locale) {
    final region = locale.contains(RegExp('[_-]'))
        ? locale.split(RegExp('[_-]')).last.toUpperCase()
        : '';
    const byRegion = {
      'IN': 'INR',
      'US': 'USD',
      'GB': 'GBP',
      'JP': 'JPY',
      'AU': 'AUD',
      'CA': 'CAD',
      'AE': 'AED',
      'SG': 'SGD',
      'CH': 'CHF',
      'KW': 'KWD',
      'DE': 'EUR',
      'FR': 'EUR',
      'ES': 'EUR',
      'IT': 'EUR',
      'NL': 'EUR',
      'IE': 'EUR',
      'PT': 'EUR',
      'AT': 'EUR',
      'BE': 'EUR',
      'FI': 'EUR',
    };
    return byRegion[region] ?? 'USD';
  }
}
