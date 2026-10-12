import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';

enum PaymentMethod {
  cash('cash', 'Cash'),
  card('card', 'Card'),
  mobile('mobile', 'UPI / Mobile pay'),
  bankTransfer('bank_transfer', 'Bank transfer'),
  wallet('wallet', 'Digital wallet'),
  other('other', 'Other');

  const PaymentMethod(this.key, this.label);

  final String key;
  final String label;

  static PaymentMethod? fromKey(String? key) {
    if (key == null) return null;
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// A single recorded expense.
///
/// * [amountMinor] – positive integer amount in minor units of [currencyCode].
/// * [date] – the calendar date the money was spent (user-chosen, no time
///   zone). This is distinct from [createdAt], the instant it was recorded.
/// * [version] – optimistic-concurrency counter. Every update must write
///   `version + 1`; Firestore rules reject anything else, so an edit based on
///   stale data can never silently overwrite a newer change.
class Expense extends Equatable {
  const Expense({
    required this.id,
    required this.amountMinor,
    required this.currencyCode,
    required this.categoryId,
    required this.date,
    this.note,
    this.merchant,
    this.paymentMethod,
    this.createdAt,
    this.updatedAt,
    this.version = 0,
    this.hasPendingWrites = false,
  });

  static const int maxNoteLength = 200;
  static const int maxMerchantLength = 80;

  final String id;
  final int amountMinor;
  final String currencyCode;
  final String categoryId;
  final LocalDate date;
  final String? note;
  final String? merchant;
  final PaymentMethod? paymentMethod;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int version;

  /// True while a local change has not yet been acknowledged by the server.
  final bool hasPendingWrites;

  /// Text used for search and display ("merchant · note").
  String get description {
    final parts = [
      if (merchant != null && merchant!.isNotEmpty) merchant!,
      if (note != null && note!.isNotEmpty) note!,
    ];
    return parts.join(' · ');
  }

  Expense copyWith({
    String? id,
    int? amountMinor,
    String? currencyCode,
    String? categoryId,
    LocalDate? date,
    String? Function()? note,
    String? Function()? merchant,
    PaymentMethod? Function()? paymentMethod,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    bool? hasPendingWrites,
  }) {
    return Expense(
      id: id ?? this.id,
      amountMinor: amountMinor ?? this.amountMinor,
      currencyCode: currencyCode ?? this.currencyCode,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note != null ? note() : this.note,
      merchant: merchant != null ? merchant() : this.merchant,
      paymentMethod: paymentMethod != null
          ? paymentMethod()
          : this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      hasPendingWrites: hasPendingWrites ?? this.hasPendingWrites,
    );
  }

  /// Orders by expense date (newest first), then by creation time.
  static int newestFirst(Expense a, Expense b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    final ac = a.createdAt, bc = b.createdAt;
    if (ac != null && bc != null) return bc.compareTo(ac);
    if (ac == null && bc != null) return -1; // pending local writes on top
    if (ac != null && bc == null) return 1;
    return b.id.compareTo(a.id);
  }

  @override
  List<Object?> get props => [
    id,
    amountMinor,
    currencyCode,
    categoryId,
    date,
    note,
    merchant,
    paymentMethod,
    createdAt,
    updatedAt,
    version,
    hasPendingWrites,
  ];
}
