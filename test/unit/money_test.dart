import 'package:daily/core/money/currency.dart';
import 'package:daily/core/money/money_formatter.dart';
import 'package:daily/core/money/money_math.dart';
import 'package:daily/core/money/money_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  group('MoneyParser', () {
    const inr = Currencies.inr;

    test('parses whole and decimal amounts into minor units', () {
      expect(MoneyParser.parse('120', inr).minorUnits, 12000);
      expect(MoneyParser.parse('120.5', inr).minorUnits, 12050);
      expect(MoneyParser.parse('120.50', inr).minorUnits, 12050);
      expect(MoneyParser.parse('0.01', inr).minorUnits, 1);
      expect(MoneyParser.parse('.5', inr).minorUnits, 50);
      expect(MoneyParser.parse(' 7 ', inr).minorUnits, 700);
    });

    test('accepts a comma as decimal separator', () {
      expect(MoneyParser.parse('12,75', Currencies.eur).minorUnits, 1275);
    });

    test('avoids binary floating point errors', () {
      // 0.1 + 0.2 style inputs stay exact.
      expect(MoneyParser.parse('0.29', inr).minorUnits, 29);
      expect(MoneyParser.parse('1.15', inr).minorUnits, 115);
      expect(MoneyParser.parse('19999999.99', inr).minorUnits, 1999999999);
    });

    test('rejects empty, zero, negative and malformed input', () {
      expect(MoneyParser.parse('', inr).error, AmountError.empty);
      expect(MoneyParser.parse('   ', inr).error, AmountError.empty);
      expect(MoneyParser.parse('0', inr).error, AmountError.notPositive);
      expect(MoneyParser.parse('0.00', inr).error, AmountError.notPositive);
      expect(MoneyParser.parse('-5', inr).error, AmountError.notPositive);
      for (final bad in [
        'abc',
        'NaN',
        'Infinity',
        '1e5',
        '1.2.3',
        '1,000.50',
        '.',
        '12a',
      ]) {
        expect(MoneyParser.parse(bad, inr).isValid, isFalse, reason: bad);
      }
    });

    test('respects currency precision', () {
      expect(
        MoneyParser.parse('1.234', inr).error,
        AmountError.tooManyDecimals,
      );
      // JPY has no minor unit.
      expect(MoneyParser.parse('500', Currencies.jpy).minorUnits, 500);
      expect(
        MoneyParser.parse('500.5', Currencies.jpy).error,
        AmountError.tooManyDecimals,
      );
      // KWD has three decimals.
      expect(MoneyParser.parse('1.234', Currencies.kwd).minorUnits, 1234);
      expect(MoneyParser.parse('1.5', Currencies.kwd).minorUnits, 1500);
    });

    test('rejects absurdly large amounts', () {
      expect(
        MoneyParser.parse('99999999999999', inr).error,
        AmountError.tooLarge,
      );
      expect(MoneyParser.parse('1000000000000', inr).isValid, isTrue);
    });

    test('round-trips to input text', () {
      expect(MoneyParser.toInputText(12050, inr), '120.50');
      expect(MoneyParser.toInputText(5, inr), '0.05');
      expect(MoneyParser.toInputText(500, Currencies.jpy), '500');
      expect(MoneyParser.toInputText(1005, Currencies.kwd), '1.005');
    });
  });

  group('MoneyMath', () {
    test('divideRounded rounds half away from zero', () {
      expect(MoneyMath.divideRounded(10, 4), 3); // 2.5 -> 3
      expect(MoneyMath.divideRounded(10, 3), 3); // 3.33 -> 3
      expect(MoneyMath.divideRounded(11, 3), 4); // 3.67 -> 4
      expect(MoneyMath.divideRounded(-10, 4), -3);
      expect(MoneyMath.divideRounded(0, 7), 0);
      expect(() => MoneyMath.divideRounded(1, 0), throwsArgumentError);
    });

    test('share and change return null instead of dividing by zero', () {
      expect(MoneyMath.shareBasisPoints(5, 0), isNull);
      expect(MoneyMath.shareBasisPoints(1, 3), 3333);
      expect(MoneyMath.changeBasisPoints(current: 100, previous: 0), isNull);
      expect(MoneyMath.changeBasisPoints(current: 150, previous: 100), 5000);
      expect(MoneyMath.changeBasisPoints(current: 50, previous: 100), -5000);
      expect(MoneyMath.changeBasisPoints(current: 0, previous: 100), -10000);
    });
  });

  group('MoneyFormatter', () {
    test('formats with currency precision and locale', () {
      expect(
        MoneyFormatter(locale: 'en_US', currencyCode: 'USD').format(123456),
        r'$1,234.56',
      );
      expect(
        MoneyFormatter(locale: 'en_US', currencyCode: 'JPY').format(1500),
        '¥1,500',
      );
      expect(
        MoneyFormatter(locale: 'en_IN', currencyCode: 'INR').format(12345678),
        '₹1,23,456.78',
      );
      expect(
        MoneyFormatter(locale: 'en_US', currencyCode: 'KWD').format(1005),
        contains('1.005'),
      );
    });

    test('percent from basis points', () {
      expect(
        MoneyFormatter.percentFromBasisPoints(1250, locale: 'en_US'),
        '12.5%',
      );
      expect(
        MoneyFormatter.percentFromBasisPoints(5000, locale: 'en_US'),
        '50%',
      );
    });
  });

  group('Currencies', () {
    test('lookup and locale defaults', () {
      expect(Currencies.byCode('JPY').minorDigits, 0);
      expect(Currencies.byCode('XYZ').minorDigits, 2);
      expect(Currencies.defaultForLocale('en_IN'), 'INR');
      expect(Currencies.defaultForLocale('de_DE'), 'EUR');
      expect(Currencies.defaultForLocale('xx'), 'USD');
    });
  });
}
