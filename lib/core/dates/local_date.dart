import 'package:flutter/foundation.dart';

/// A calendar date with no time or time zone.
///
/// Expenses belong to a calendar date chosen by the user (stored as
/// `yyyy-MM-dd`). Using a dedicated type avoids the classic bug where a
/// `DateTime` at local midnight is converted to UTC and lands on the previous
/// day. All arithmetic is performed on UTC instants, which have no DST gaps.
@immutable
class LocalDate implements Comparable<LocalDate> {
  factory LocalDate(int year, int month, int day) {
    final d = DateTime.utc(year, month, day);
    return LocalDate._(d.year, d.month, d.day);
  }

  const LocalDate._(this.year, this.month, this.day);

  /// Takes the calendar fields of [dateTime] as they are (local or UTC).
  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate._(dateTime.year, dateTime.month, dateTime.day);

  /// Today's date in the device's local time zone.
  factory LocalDate.today([DateTime Function()? clock]) =>
      LocalDate.fromDateTime((clock ?? DateTime.now)());

  /// Parses a strict `yyyy-MM-dd` string.
  static LocalDate parse(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) throw FormatException('Invalid date', iso);
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) {
      throw FormatException('Invalid date', iso);
    }
    return LocalDate._(y, mo, d);
  }

  static LocalDate? tryParse(String? iso) {
    if (iso == null) return null;
    try {
      return parse(iso);
    } on FormatException {
      return null;
    }
  }

  final int year;
  final int month;
  final int day;

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  static int daysInMonth(int year, int month) {
    const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && isLeapYear(year)) return 29;
    return days[month - 1];
  }

  DateTime get _utc => DateTime.utc(year, month, day);

  /// Local midnight of this date (for pickers and display only).
  DateTime toDateTime() => DateTime(year, month, day);

  /// Days since 1970-01-01.
  int get epochDay =>
      _utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  /// ISO weekday, 1 = Monday … 7 = Sunday.
  int get weekday => _utc.weekday;

  LocalDate addDays(int days) =>
      LocalDate.fromDateTime(DateTime.utc(year, month, day + days));

  LocalDate addMonths(int months) {
    final total = year * 12 + (month - 1) + months;
    final y = total ~/ 12;
    final m = total % 12 + 1;
    final d = day > daysInMonth(y, m) ? daysInMonth(y, m) : day;
    return LocalDate._(y, m, d);
  }

  /// Whole days from [other] to this date (positive if this is later).
  int daysSince(LocalDate other) => epochDay - other.epochDay;

  /// Start of the week containing this date, where [weekStart] is an ISO
  /// weekday (1 = Monday, 7 = Sunday).
  LocalDate startOfWeek(int weekStart) {
    final offset = (weekday - weekStart + 7) % 7;
    return addDays(-offset);
  }

  LocalDate get startOfMonth => LocalDate._(year, month, 1);
  LocalDate get endOfMonth =>
      LocalDate._(year, month, daysInMonth(year, month));
  LocalDate get startOfYear => LocalDate._(year, 1, 1);
  LocalDate get endOfYear => LocalDate._(year, 12, 31);

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  static LocalDate min(LocalDate a, LocalDate b) => a <= b ? a : b;
  static LocalDate max(LocalDate a, LocalDate b) => a >= b ? a : b;

  /// `yyyy-MM-dd`; sorts lexicographically in date order.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// `yyyy-MM` key for monthly records.
  String get monthKey =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// An inclusive range of calendar dates.
@immutable
class DateRange {
  /// [start] must not be after [end]; use [DateRange.ordered] for
  /// user-provided bounds.
  const DateRange(this.start, this.end);

  factory DateRange.ordered(LocalDate a, LocalDate b) =>
      a <= b ? DateRange(a, b) : DateRange(b, a);

  final LocalDate start;
  final LocalDate end;

  int get dayCount => end.daysSince(start) + 1;

  bool contains(LocalDate date) => date >= start && date <= end;

  Iterable<LocalDate> get days sync* {
    for (var d = start; d <= end; d = d.addDays(1)) {
      yield d;
    }
  }

  /// Intersection with [other], or null when they do not overlap.
  DateRange? intersect(DateRange other) {
    final s = LocalDate.max(start, other.start);
    final e = LocalDate.min(end, other.end);
    return s <= e ? DateRange(s, e) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start..$end';
}
