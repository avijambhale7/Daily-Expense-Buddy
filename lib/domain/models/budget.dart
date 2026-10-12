import 'package:equatable/equatable.dart';

/// A recurring monthly budget, either overall ([categoryId] == null) or for a
/// single category. Amounts are in minor units of [currencyCode].
class Budget extends Equatable {
  const Budget({
    required this.id,
    required this.amountMinor,
    required this.currencyCode,
    this.categoryId,
  });

  static const String overallId = 'overall';
  static String idForCategory(String categoryId) => 'cat_$categoryId';

  final String id;
  final int amountMinor;
  final String currencyCode;
  final String? categoryId;

  bool get isOverall => categoryId == null;

  @override
  List<Object?> get props => [id, amountMinor, currencyCode, categoryId];
}

enum BudgetLevel { onTrack, warning, exceeded }

/// Computed spending status of a [Budget] for one month.
class BudgetStatus extends Equatable {
  const BudgetStatus({
    required this.budget,
    required this.spentMinor,
    required this.usedBasisPoints,
    required this.level,
    required this.highestThresholdReached,
  });

  final Budget budget;
  final int spentMinor;

  /// Percentage of the budget used, in basis points (10000 = 100%).
  final int usedBasisPoints;
  final BudgetLevel level;

  /// Highest configured alert threshold (percent) reached, or null.
  final int? highestThresholdReached;

  int get remainingMinor => budget.amountMinor - spentMinor;

  @override
  List<Object?> get props => [
    budget,
    spentMinor,
    usedBasisPoints,
    level,
    highestThresholdReached,
  ];
}
