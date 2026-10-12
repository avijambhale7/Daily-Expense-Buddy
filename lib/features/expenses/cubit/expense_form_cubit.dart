import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_parser.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/expense_category.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/expense_validator.dart';

enum ExpenseFormStatus {
  loading,
  ready,
  saving,
  saved,
  deleting,
  deleted,
  notFound,
}

class ExpenseFormState extends Equatable {
  const ExpenseFormState({
    required this.status,
    required this.id,
    required this.currencyCode,
    required this.date,
    this.original,
    this.amountText = '',
    this.categoryId,
    this.note = '',
    this.merchant = '',
    this.paymentMethod,
    this.validation,
    this.error,
    this.outcome,
  });

  final ExpenseFormStatus status;

  /// Pre-generated document id; stable across retries so the same expense is
  /// never written twice.
  final String id;
  final String currencyCode;
  final LocalDate date;
  final Expense? original;
  final String amountText;
  final String? categoryId;
  final String note;
  final String merchant;
  final PaymentMethod? paymentMethod;

  /// Set after a submit attempt so field errors are shown.
  final ExpenseValidationResult? validation;
  final String? error;
  final SaveOutcome? outcome;

  bool get isEditing => original != null;
  bool get isBusy =>
      status == ExpenseFormStatus.saving ||
      status == ExpenseFormStatus.deleting;
  CurrencyConfiguration get currency => Currencies.byCode(currencyCode);

  ExpenseFormState copyWith({
    ExpenseFormStatus? status,
    LocalDate? date,
    Expense? original,
    String? currencyCode,
    String? amountText,
    String? Function()? categoryId,
    String? note,
    String? merchant,
    PaymentMethod? Function()? paymentMethod,
    ExpenseValidationResult? Function()? validation,
    String? Function()? error,
    SaveOutcome? outcome,
  }) {
    return ExpenseFormState(
      status: status ?? this.status,
      id: id,
      currencyCode: currencyCode ?? this.currencyCode,
      date: date ?? this.date,
      original: original ?? this.original,
      amountText: amountText ?? this.amountText,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      note: note ?? this.note,
      merchant: merchant ?? this.merchant,
      paymentMethod: paymentMethod != null
          ? paymentMethod()
          : this.paymentMethod,
      validation: validation != null ? validation() : this.validation,
      error: error != null ? error() : this.error,
      outcome: outcome ?? this.outcome,
    );
  }

  @override
  List<Object?> get props => [
    status,
    id,
    currencyCode,
    date,
    original,
    amountText,
    categoryId,
    note,
    merchant,
    paymentMethod,
    validation?.amountError,
    validation?.dateError,
    validation?.noteError,
    validation?.merchantError,
    error,
    outcome,
  ];
}

class ExpenseFormCubit extends Cubit<ExpenseFormState> {
  ExpenseFormCubit({
    required ExpenseRepository repository,
    required String currencyCode,
    required LocalDate today,
    LocalDate? initialDate,
    String? expenseId,
  }) : _repository = repository,
       _today = today,
       super(
         ExpenseFormState(
           status: expenseId == null
               ? ExpenseFormStatus.ready
               : ExpenseFormStatus.loading,
           id: expenseId ?? repository.newId(),
           currencyCode: currencyCode,
           date: initialDate != null && initialDate <= today
               ? initialDate
               : today,
         ),
       ) {
    if (expenseId != null) _load(expenseId);
  }

  final ExpenseRepository _repository;
  final LocalDate _today;

  Future<void> _load(String id) async {
    try {
      final e = await _repository.watchExpense(id).first;
      if (isClosed) return;
      if (e == null) {
        emit(state.copyWith(status: ExpenseFormStatus.notFound));
        return;
      }
      emit(
        state.copyWith(
          status: ExpenseFormStatus.ready,
          original: e,
          // Editing keeps the expense's own currency; amounts are never
          // reinterpreted in another currency.
          currencyCode: e.currencyCode,
          amountText: MoneyParser.toInputText(
            e.amountMinor,
            Currencies.byCode(e.currencyCode),
          ),
          categoryId: () => e.categoryId,
          date: e.date,
          note: e.note ?? '',
          merchant: e.merchant ?? '',
          paymentMethod: () => e.paymentMethod,
        ),
      );
    } on AppFailure catch (f) {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ExpenseFormStatus.ready,
            error: () => f.message,
          ),
        );
      }
    }
  }

  void amountChanged(String v) => emit(
    state.copyWith(
      amountText: v,
      error: () => null,
      validation: state.validation == null ? null : () => _validate(amount: v),
    ),
  );
  void categoryChanged(String? id) =>
      emit(state.copyWith(categoryId: () => id));
  void dateChanged(LocalDate d) => emit(
    state.copyWith(
      date: d,
      validation: state.validation == null ? null : () => _validate(date: d),
    ),
  );
  void noteChanged(String v) => emit(state.copyWith(note: v));
  void merchantChanged(String v) => emit(state.copyWith(merchant: v));
  void paymentChanged(PaymentMethod? m) =>
      emit(state.copyWith(paymentMethod: () => m));

  ExpenseValidationResult _validate({String? amount, LocalDate? date}) =>
      ExpenseValidator.validate(
        ExpenseInput(
          amountText: amount ?? state.amountText,
          currencyCode: state.currencyCode,
          date: date ?? state.date,
          note: state.note,
          merchant: state.merchant,
        ),
        today: _today,
      );

  /// Validates and saves. Ignored while a save is in progress, which
  /// prevents duplicate submissions from double taps.
  Future<void> submit() async {
    if (state.isBusy || state.status == ExpenseFormStatus.loading) return;
    final v = _validate();
    if (!v.isValid) {
      emit(state.copyWith(validation: () => v, error: () => null));
      return;
    }
    emit(
      state.copyWith(
        status: ExpenseFormStatus.saving,
        validation: () => v,
        error: () => null,
      ),
    );
    final expense = Expense(
      id: state.id,
      amountMinor: v.amountMinor!,
      currencyCode: state.currencyCode,
      categoryId: state.categoryId ?? ExpenseCategory.fallbackId,
      date: state.date,
      note: state.note.trim().isEmpty ? null : state.note.trim(),
      merchant: state.merchant.trim().isEmpty ? null : state.merchant.trim(),
      paymentMethod: state.paymentMethod,
      version: state.original?.version ?? 0,
      createdAt: state.original?.createdAt,
    );
    try {
      final outcome = state.isEditing
          ? await _repository.update(expense)
          : await _repository.create(expense);
      if (!isClosed) {
        emit(state.copyWith(status: ExpenseFormStatus.saved, outcome: outcome));
      }
    } on AppFailure catch (f) {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ExpenseFormStatus.ready,
            error: () => f.message,
          ),
        );
      }
    }
  }

  Future<void> delete() async {
    if (state.isBusy || !state.isEditing) return;
    emit(state.copyWith(status: ExpenseFormStatus.deleting, error: () => null));
    try {
      final outcome = await _repository.delete(state.id);
      if (!isClosed) {
        emit(
          state.copyWith(status: ExpenseFormStatus.deleted, outcome: outcome),
        );
      }
    } on AppFailure catch (f) {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: ExpenseFormStatus.ready,
            error: () => f.message,
          ),
        );
      }
    }
  }
}
