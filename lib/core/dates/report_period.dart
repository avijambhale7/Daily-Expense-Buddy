import 'package:flutter/foundation.dart';

import 'local_date.dart';

enum ReportPeriodType { day, week, month, year, custom }

/// A reporting period with well-defined calendar boundaries.
///
/// * day   – a single calendar date
/// * week  – 7 days starting on the user's configured week-start day
/// * month – the full calendar month (28–31 days)
/// * year  – the full calendar year (365/366 days)
/// * custom – any inclusive date range
@immutable
class ReportPeriod {
  const ReportPeriod._(this.type, this.range, this.weekStart);

  factory ReportPeriod.of(
    ReportPeriodType type,
    LocalDate anchor, {
    int weekStart = DateTime.monday,
  }) {
    switch (type) {
      case ReportPeriodType.day:
        return ReportPeriod._(type, DateRange(anchor, anchor), weekStart);
      case ReportPeriodType.week:
        final s = anchor.startOfWeek(weekStart);
        return ReportPeriod._(type, DateRange(s, s.addDays(6)), weekStart);
      case ReportPeriodType.month:
        return ReportPeriod._(
          type,
          DateRange(anchor.startOfMonth, anchor.endOfMonth),
          weekStart,
        );
      case ReportPeriodType.year:
        return ReportPeriod._(
          type,
          DateRange(anchor.startOfYear, anchor.endOfYear),
          weekStart,
        );
      case ReportPeriodType.custom:
        return ReportPeriod._(type, DateRange(anchor, anchor), weekStart);
    }
  }

  factory ReportPeriod.custom(DateRange range) =>
      ReportPeriod._(ReportPeriodType.custom, range, DateTime.monday);

  final ReportPeriodType type;
  final DateRange range;
  final int weekStart;

  /// The equivalent period immediately before this one: previous day, week,
  /// calendar month, calendar year, or a custom range of identical length.
  ReportPeriod get previous => shift(-1);

  ReportPeriod get next => shift(1);

  ReportPeriod shift(int steps) {
    switch (type) {
      case ReportPeriodType.day:
        return ReportPeriod.of(
          type,
          range.start.addDays(steps),
          weekStart: weekStart,
        );
      case ReportPeriodType.week:
        return ReportPeriod.of(
          type,
          range.start.addDays(7 * steps),
          weekStart: weekStart,
        );
      case ReportPeriodType.month:
        return ReportPeriod.of(
          type,
          range.start.addMonths(steps),
          weekStart: weekStart,
        );
      case ReportPeriodType.year:
        return ReportPeriod.of(
          type,
          LocalDate(range.start.year + steps, 1, 1),
          weekStart: weekStart,
        );
      case ReportPeriodType.custom:
        final len = range.dayCount;
        return ReportPeriod.custom(
          DateRange(
            range.start.addDays(len * steps),
            range.end.addDays(len * steps),
          ),
        );
    }
  }

  /// Whether this period contains [today] (i.e. is still in progress).
  bool isCurrent(LocalDate today) => range.contains(today);

  /// True when the whole period lies after [today].
  bool isFuture(LocalDate today) => range.start > today;

  String get comparisonLabel {
    switch (type) {
      case ReportPeriodType.day:
        return 'previous day';
      case ReportPeriodType.week:
        return 'previous week';
      case ReportPeriodType.month:
        return 'previous month';
      case ReportPeriodType.year:
        return 'previous year';
      case ReportPeriodType.custom:
        return 'previous ${range.dayCount} days';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod &&
      other.type == type &&
      other.range == range &&
      other.weekStart == weekStart;

  @override
  int get hashCode => Object.hash(type, range, weekStart);
}
