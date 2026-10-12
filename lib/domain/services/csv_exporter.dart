import '../../core/dates/local_date.dart';
import '../../core/money/currency.dart';
import '../../core/money/money_parser.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';

/// Builds RFC 4180 CSV for expense exports.
///
/// Amounts are written as plain decimals with a `.` separator (e.g. `120.50`)
/// so spreadsheets can parse them regardless of locale. Cells that could be
/// interpreted as spreadsheet formulas are prefixed with `'` (CSV injection
/// protection).
abstract final class CsvExporter {
  static const headers = [
    'Date',
    'Amount',
    'Currency',
    'Category',
    'Merchant',
    'Note',
    'Payment method',
    'Created at (UTC)',
  ];

  static String build(
    List<Expense> expenses,
    Map<String, ExpenseCategory> categories,
  ) {
    final buffer = StringBuffer()..write(_row(headers));
    final sorted = [...expenses]..sort((a, b) => -Expense.newestFirst(a, b));
    for (final e in sorted) {
      final currency = Currencies.byCode(e.currencyCode);
      buffer.write(
        _row([
          e.date.toIso(),
          MoneyParser.toInputText(e.amountMinor, currency),
          e.currencyCode,
          (categories[e.categoryId] ?? ExpenseCategory.unknown(e.categoryId))
              .name,
          e.merchant ?? '',
          e.note ?? '',
          e.paymentMethod?.label ?? '',
          e.createdAt?.toUtc().toIso8601String() ?? '',
        ]),
      );
    }
    return buffer.toString();
  }

  static String fileName(DateRange range) =>
      'daily-expense-buddy_${range.start.toIso()}_to_${range.end.toIso()}.csv';

  static String _row(List<String> cells) =>
      '${cells.map(escape).join(',')}\r\n';

  static String escape(String value) {
    var v = value;
    if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) {
      v = "'$v";
    }
    final needsQuotes =
        v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r');
    if (needsQuotes) {
      v = '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
