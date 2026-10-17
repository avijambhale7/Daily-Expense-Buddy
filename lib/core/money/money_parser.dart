import 'currency.dart';

enum AmountError { empty, invalid, notPositive, tooManyDecimals, tooLarge }

class AmountParseResult {
  const AmountParseResult.success(int this.minorUnits) : error = null;
  const AmountParseResult.failure(AmountError this.error) : minorUnits = null;

  final int? minorUnits;
  final AmountError? error;

  bool get isValid => minorUnits != null;
}

/// Parses user-entered amounts into integer minor units without ever passing
/// through a floating-point value.
abstract final class MoneyParser {
  /// Largest accepted amount: 1 trillion major units. Prevents absurd values
  /// and keeps every amount well inside the exact-integer range of doubles
  /// used by number formatters for display.
  static const int maxMajorUnits = 1000000000000;

  /// Accepts plain digits with an optional single `.` or `,` decimal
  /// separator (e.g. `12`, `12.5`, `12,50`). Grouping separators, signs,
  /// exponents and other characters are rejected.
  static AmountParseResult parse(String input, CurrencyConfiguration currency) {
    final text = input.trim().replaceAll(' ', '').replaceAll(' ', '');
    if (text.isEmpty) return const AmountParseResult.failure(AmountError.empty);
    if (text.startsWith('-')) {
      return const AmountParseResult.failure(AmountError.notPositive);
    }
    final match = RegExp(r'^(\d*)(?:[.,](\d*))?$').firstMatch(text);
    if (match == null) {
      return const AmountParseResult.failure(AmountError.invalid);
    }
    final whole = match.group(1) ?? '';
    final fraction = match.group(2) ?? '';
    if (whole.isEmpty && fraction.isEmpty) {
      return const AmountParseResult.failure(AmountError.invalid);
    }
    if (fraction.length > currency.minorDigits) {
      return const AmountParseResult.failure(AmountError.tooManyDecimals);
    }
    final wholeDigits = whole.replaceFirst(RegExp('^0+'), '');
    if (wholeDigits.length > maxMajorUnits.toString().length) {
      return const AmountParseResult.failure(AmountError.tooLarge);
    }
    final major = wholeDigits.isEmpty ? 0 : int.parse(wholeDigits);
    if (major > maxMajorUnits) {
      return const AmountParseResult.failure(AmountError.tooLarge);
    }
    final paddedFraction = fraction.padRight(currency.minorDigits, '0');
    final minorPart = paddedFraction.isEmpty ? 0 : int.parse(paddedFraction);
    final total = major * currency.minorFactor + minorPart;
    if (total <= 0) {
      return const AmountParseResult.failure(AmountError.notPositive);
    }
    if (total > maxMajorUnits * currency.minorFactor) {
      return const AmountParseResult.failure(AmountError.tooLarge);
    }
    return AmountParseResult.success(total);
  }

  /// Converts minor units back into an editable string such as `12.50`.
  static String toInputText(int minorUnits, CurrencyConfiguration currency) {
    if (currency.minorDigits == 0) return minorUnits.toString();
    final factor = currency.minorFactor;
    final major = minorUnits ~/ factor;
    final minor = (minorUnits % factor).toString().padLeft(
      currency.minorDigits,
      '0',
    );
    return '$major.$minor';
  }

  static String messageFor(AmountError error, CurrencyConfiguration currency) {
    switch (error) {
      case AmountError.empty:
        return 'Enter an amount';
      case AmountError.invalid:
        return 'Enter a valid number, for example 120.50';
      case AmountError.notPositive:
        return 'Amount must be greater than zero';
      case AmountError.tooManyDecimals:
        return currency.minorDigits == 0
            ? '${currency.code} does not use decimal places'
            : '${currency.code} allows up to ${currency.minorDigits} decimal places';
      case AmountError.tooLarge:
        return 'Amount is too large';
    }
  }
}

/// [minor] as typed digits ("1500.00"), which [MoneyParser] reads back.
String plainAmount(int minor, int digits) {
  if (digits == 0) return '$minor';
  var factor = 1;
  for (var i = 0; i < digits; i++) {
    factor *= 10;
  }
  final frac = (minor % factor).toString().padLeft(digits, '0');
  return '${minor ~/ factor}.$frac';
}
