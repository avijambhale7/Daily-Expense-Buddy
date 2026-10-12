import '../../core/dates/local_date.dart';
import '../../core/money/currency.dart';
import '../../core/money/money_parser.dart';
import '../models/expense.dart';

class ExpenseInput {
  const ExpenseInput({
    required this.amountText,
    required this.currencyCode,
    required this.date,
    this.note = '',
    this.merchant = '',
  });

  final String amountText;
  final String currencyCode;
  final LocalDate? date;
  final String note;
  final String merchant;
}

class ExpenseValidationResult {
  const ExpenseValidationResult({
    this.amountMinor,
    this.amountError,
    this.dateError,
    this.noteError,
    this.merchantError,
  });

  final int? amountMinor;
  final String? amountError;
  final String? dateError;
  final String? noteError;
  final String? merchantError;

  bool get isValid =>
      amountError == null &&
      dateError == null &&
      noteError == null &&
      merchantError == null &&
      amountMinor != null;
}

abstract final class ExpenseValidator {
  /// Earliest accepted expense date.
  static final LocalDate earliestDate = LocalDate(2000, 1, 1);

  static ExpenseValidationResult validate(
    ExpenseInput input, {
    required LocalDate today,
  }) {
    final currency = Currencies.byCode(input.currencyCode);
    final parsed = MoneyParser.parse(input.amountText, currency);

    String? dateError;
    final date = input.date;
    if (date == null) {
      dateError = 'Choose a date';
    } else if (date > today) {
      dateError = 'Expenses cannot be recorded for future dates';
    } else if (date < earliestDate) {
      dateError = 'Date is too far in the past';
    }

    return ExpenseValidationResult(
      amountMinor: parsed.minorUnits,
      amountError: parsed.error == null
          ? null
          : MoneyParser.messageFor(parsed.error!, currency),
      dateError: dateError,
      noteError: input.note.trim().length > Expense.maxNoteLength
          ? 'Note must be ${Expense.maxNoteLength} characters or fewer'
          : null,
      merchantError: input.merchant.trim().length > Expense.maxMerchantLength
          ? 'Must be ${Expense.maxMerchantLength} characters or fewer'
          : null,
    );
  }
}
