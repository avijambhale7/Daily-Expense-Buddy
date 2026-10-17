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

/// Where a loan stands. Derived from the stored amounts and flags, so it can
/// never disagree with them.
enum LoanStatus {
  outstanding('Outstanding'),
  partiallyRepaid('Partially repaid'),
  fullyRepaid('Fully repaid'),
  cancelled('Cancelled');

  const LoanStatus(this.label);
  final String label;
}

/// One payment towards a loan. Stored under the loan
/// (`users/{uid}/loans/{loanId}/repayments/{id}`) and never edited, so the
/// history is a reliable record of what was paid and when.
class LoanRepayment extends Equatable {
  const LoanRepayment({
    required this.id,
    required this.amountMinor,
    required this.date,
    this.note,
    this.createdAt,
  });

  final String id;
  final int amountMinor;
  final LocalDate date;
  final String? note;

  /// Server time the repayment was recorded (null until synced).
  final DateTime? createdAt;

  @override
  List<Object?> get props => [id, amountMinor, date, note, createdAt];
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
    this.cancelled = false,
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

  /// Closed: fully paid back, or cancelled. Closed loans move to the
  /// settled list and no longer count as outstanding.
  final bool settled;

  /// Closed without being fully repaid (e.g. forgiven or recorded by
  /// mistake). Always implies [settled].
  final bool cancelled;

  /// The latest change has not reached the server yet.
  final bool hasPendingWrites;

  LoanStatus get status {
    if (cancelled) return LoanStatus.cancelled;
    if (settled || repaidMinor >= amountMinor) return LoanStatus.fullyRepaid;
    if (repaidMinor > 0) return LoanStatus.partiallyRepaid;
    return LoanStatus.outstanding;
  }

  /// The largest repayment that can still be recorded.
  int get remainingMinor {
    if (settled) return 0;
    final left = amountMinor - repaidMinor;
    return left < 0 ? 0 : left;
  }

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
  /// Throws [ArgumentError] for a non-positive amount or one larger than
  /// what is still owed, so totals can never exceed the loan.
  Loan withRepayment(int minor) {
    if (minor <= 0) {
      throw ArgumentError.value(minor, 'minor', 'must be positive');
    }
    if (minor > remainingMinor) {
      throw ArgumentError.value(minor, 'minor', 'exceeds what is still owed');
    }
    final repaid = repaidMinor + minor;
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
    bool? cancelled,
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
      cancelled: cancelled ?? this.cancelled,
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
    cancelled,
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
    this.lentMinor = 0,
    this.borrowedMinor = 0,
    this.returnedToMeMinor = 0,
    this.repaidByMeMinor = 0,
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
    var lent = 0;
    var borrowed = 0;
    var returned = 0;
    var repaidByMe = 0;
    for (final l in loans) {
      // Other currencies are never added in without a conversion.
      if (l.currencyCode != currencyCode || l.cancelled) continue;
      if (l.direction == LoanDirection.lent) {
        lent += l.amountMinor;
        returned += l.repaidMinor;
      } else {
        borrowed += l.amountMinor;
        repaidByMe += l.repaidMinor;
      }
      if (l.settled) continue;
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
      lentMinor: lent,
      borrowedMinor: borrowed,
      returnedToMeMinor: returned,
      repaidByMeMinor: repaidByMe,
    );
  }

  /// Originally lent / borrowed (not cancelled), in this currency.
  final int lentMinor;
  final int borrowedMinor;

  /// Paid back so far, to the user / by the user.
  final int returnedToMeMinor;
  final int repaidByMeMinor;

  /// Still to receive (outstanding lent money).
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
    lentMinor,
    borrowedMinor,
    returnedToMeMinor,
    repaidByMeMinor,
  ];
}
