import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';

/// Whether the user gave the money or received it.
enum LoanDirection {
  /// The user gave money to someone and should get it back.
  lent('lent'),

  /// The user received money from someone and should pay it back.
  borrowed('borrowed');

  const LoanDirection(this.key);
  final String key;

  static LoanDirection? fromKey(Object? key) {
    for (final d in values) {
      if (d.key == key) return d;
    }
    return null;
  }
}

/// Money lent to or borrowed from a person. Amounts are in minor units of
/// [currencyCode]; [repaidMinor] is how much of it has been returned so far.
class Loan extends Equatable {
  const Loan({
    required this.id,
    required this.direction,
    required this.personName,
    required this.amountMinor,
    required this.currencyCode,
    required this.date,
    this.repaidMinor = 0,
    this.dueDate,
    this.note,
    this.settled = false,
    this.hasPendingWrites = false,
  });

  final String id;
  final LoanDirection direction;
  final String personName;
  final int amountMinor;
  final int repaidMinor;
  final String currencyCode;
  final LocalDate date;
  final LocalDate? dueDate;
  final String? note;

  /// Fully paid back (or written off) and moved to the settled list.
  final bool settled;

  /// The latest change has not reached the server yet.
  final bool hasPendingWrites;

  /// What is still owed; zero once settled.
  int get outstandingMinor {
    if (settled) return 0;
    final left = amountMinor - repaidMinor;
    return left < 0 ? 0 : left;
  }

  /// Fraction of the amount paid back, 0–1.
  double get progress =>
      amountMinor == 0 ? 0 : (repaidMinor / amountMinor).clamp(0, 1).toDouble();

  bool isOverdue(LocalDate today) =>
      !settled && dueDate != null && dueDate! < today;

  /// Adds a repayment; the loan settles itself once fully repaid.
  Loan withRepayment(int minor) {
    final repaid = (repaidMinor + minor).clamp(0, amountMinor);
    return copyWith(repaidMinor: repaid, settled: repaid >= amountMinor);
  }

  Loan copyWith({
    LoanDirection? direction,
    String? personName,
    int? amountMinor,
    int? repaidMinor,
    String? currencyCode,
    LocalDate? date,
    LocalDate? Function()? dueDate,
    String? Function()? note,
    bool? settled,
  }) {
    return Loan(
      id: id,
      direction: direction ?? this.direction,
      personName: personName ?? this.personName,
      amountMinor: amountMinor ?? this.amountMinor,
      repaidMinor: repaidMinor ?? this.repaidMinor,
      currencyCode: currencyCode ?? this.currencyCode,
      date: date ?? this.date,
      dueDate: dueDate != null ? dueDate() : this.dueDate,
      note: note != null ? note() : this.note,
      settled: settled ?? this.settled,
    );
  }

  @override
  List<Object?> get props => [
    id,
    direction,
    personName,
    amountMinor,
    repaidMinor,
    currencyCode,
    date,
    dueDate,
    note,
    settled,
    hasPendingWrites,
  ];
}

/// Totals of open loans in one currency.
class LoanTotals extends Equatable {
  const LoanTotals({
    required this.toReceiveMinor,
    required this.toPayMinor,
    required this.openCount,
    required this.overdueCount,
  });

  factory LoanTotals.of(
    Iterable<Loan> loans,
    String currencyCode,
    LocalDate today,
  ) {
    var receive = 0;
    var pay = 0;
    var open = 0;
    var overdue = 0;
    for (final l in loans) {
      if (l.settled || l.currencyCode != currencyCode) continue;
      open++;
      if (l.isOverdue(today)) overdue++;
      if (l.direction == LoanDirection.lent) {
        receive += l.outstandingMinor;
      } else {
        pay += l.outstandingMinor;
      }
    }
    return LoanTotals(
      toReceiveMinor: receive,
      toPayMinor: pay,
      openCount: open,
      overdueCount: overdue,
    );
  }

  final int toReceiveMinor;
  final int toPayMinor;
  final int openCount;
  final int overdueCount;

  bool get isEmpty => openCount == 0;

  @override
  List<Object?> get props => [
    toReceiveMinor,
    toPayMinor,
    openCount,
    overdueCount,
  ];
}
