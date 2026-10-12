import 'package:daily/core/dates/local_date.dart';
import 'package:daily/core/dates/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalDate', () {
    test('parses strictly', () {
      expect(LocalDate.parse('2024-02-29'), LocalDate(2024, 2, 29));
      expect(() => LocalDate.parse('2023-02-29'), throwsFormatException);
      expect(() => LocalDate.parse('2024-13-01'), throwsFormatException);
      expect(() => LocalDate.parse('2024-1-01'), throwsFormatException);
      expect(LocalDate.tryParse('nonsense'), isNull);
      expect(LocalDate(2025, 3, 7).toIso(), '2025-03-07');
    });

    test('leap years and month lengths', () {
      expect(LocalDate.isLeapYear(2024), isTrue);
      expect(LocalDate.isLeapYear(2023), isFalse);
      expect(LocalDate.isLeapYear(1900), isFalse);
      expect(LocalDate.isLeapYear(2000), isTrue);
      expect(LocalDate.daysInMonth(2024, 2), 29);
      expect(LocalDate.daysInMonth(2025, 2), 28);
      expect(LocalDate.daysInMonth(2025, 4), 30);
      expect(LocalDate.daysInMonth(2025, 12), 31);
    });

    test('arithmetic crosses months, years and DST safely', () {
      expect(LocalDate(2024, 12, 31).addDays(1), LocalDate(2025, 1, 1));
      expect(LocalDate(2024, 3, 1).addDays(-1), LocalDate(2024, 2, 29));
      // Around typical DST transitions the calendar date must not shift.
      expect(LocalDate(2025, 3, 30).addDays(1), LocalDate(2025, 3, 31));
      expect(LocalDate(2025, 11, 2).addDays(1), LocalDate(2025, 11, 3));
      expect(LocalDate(2025, 1, 31).addMonths(1), LocalDate(2025, 2, 28));
      expect(LocalDate(2024, 1, 31).addMonths(1), LocalDate(2024, 2, 29));
      expect(LocalDate(2025, 1, 15).addMonths(-1), LocalDate(2024, 12, 15));
      expect(LocalDate(2025, 1, 10).daysSince(LocalDate(2024, 12, 31)), 10);
    });

    test('fromDateTime keeps the local calendar date', () {
      final lateEvening = DateTime(2025, 6, 30, 23, 59);
      expect(LocalDate.fromDateTime(lateEvening), LocalDate(2025, 6, 30));
    });

    test('startOfWeek honours the configured week start', () {
      final wed = LocalDate(2025, 10, 15); // Wednesday
      expect(wed.weekday, DateTime.wednesday);
      expect(wed.startOfWeek(DateTime.monday), LocalDate(2025, 10, 13));
      expect(wed.startOfWeek(DateTime.sunday), LocalDate(2025, 10, 12));
      expect(wed.startOfWeek(DateTime.saturday), LocalDate(2025, 10, 11));
      final sun = LocalDate(2025, 10, 12);
      expect(sun.startOfWeek(DateTime.sunday), sun);
      expect(sun.startOfWeek(DateTime.monday), LocalDate(2025, 10, 6));
    });

    test('DateRange', () {
      final r = DateRange(LocalDate(2024, 2, 1), LocalDate(2024, 2, 29));
      expect(r.dayCount, 29);
      expect(r.days.length, 29);
      expect(r.contains(LocalDate(2024, 2, 29)), isTrue);
      expect(r.contains(LocalDate(2024, 3, 1)), isFalse);
      expect(
        DateRange.ordered(LocalDate(2024, 2, 5), LocalDate(2024, 2, 1)).start,
        LocalDate(2024, 2, 1),
      );
    });
  });

  group('ReportPeriod', () {
    test('month covers the full calendar month', () {
      final p = ReportPeriod.of(ReportPeriodType.month, LocalDate(2024, 2, 10));
      expect(p.range, DateRange(LocalDate(2024, 2, 1), LocalDate(2024, 2, 29)));
      expect(
        p.previous.range,
        DateRange(LocalDate(2024, 1, 1), LocalDate(2024, 1, 31)),
      );
      expect(
        p.next.range,
        DateRange(LocalDate(2024, 3, 1), LocalDate(2024, 3, 31)),
      );
    });

    test('week respects the week start', () {
      final p = ReportPeriod.of(
        ReportPeriodType.week,
        LocalDate(2025, 10, 15),
        weekStart: DateTime.sunday,
      );
      expect(
        p.range,
        DateRange(LocalDate(2025, 10, 12), LocalDate(2025, 10, 18)),
      );
      expect(p.previous.range.start, LocalDate(2025, 10, 5));
    });

    test('year and day periods', () {
      final y = ReportPeriod.of(ReportPeriodType.year, LocalDate(2024, 6, 1));
      expect(y.range.dayCount, 366);
      expect(y.previous.range.dayCount, 365);
      final d = ReportPeriod.of(ReportPeriodType.day, LocalDate(2025, 1, 1));
      expect(d.previous.range.start, LocalDate(2024, 12, 31));
    });

    test('custom ranges compare with an equal-length previous range', () {
      final c = ReportPeriod.custom(
        DateRange(LocalDate(2025, 3, 11), LocalDate(2025, 3, 20)),
      );
      expect(
        c.previous.range,
        DateRange(LocalDate(2025, 3, 1), LocalDate(2025, 3, 10)),
      );
      expect(c.comparisonLabel, 'previous 10 days');
    });

    test('current and future detection', () {
      final today = LocalDate(2025, 10, 14);
      final p = ReportPeriod.of(ReportPeriodType.month, today);
      expect(p.isCurrent(today), isTrue);
      expect(p.next.isFuture(today), isTrue);
      expect(p.previous.isFuture(today), isFalse);
    });
  });
}
