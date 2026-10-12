import 'package:daily/core/dates/local_date.dart';
import 'package:daily/domain/models/budget.dart';
import 'package:daily/domain/models/daily_status.dart';
import 'package:daily/domain/models/expense.dart';
import 'package:daily/domain/models/expense_category.dart';
import 'package:daily/domain/models/user_preferences.dart';
import 'package:daily/domain/services/budget_calculator.dart';
import 'package:daily/domain/services/csv_exporter.dart';
import 'package:daily/domain/services/expense_validator.dart';
import 'package:daily/domain/services/reminder_planner.dart';
import 'package:daily/domain/services/tracking_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _e(
  String date,
  int amount, {
  String cat = 'food',
  String cur = 'INR',
  String? note,
}) => Expense(
  id: '$date-$amount-$cat',
  amountMinor: amount,
  currencyCode: cur,
  categoryId: cat,
  date: LocalDate.parse(date),
  note: note,
);

List<Expense> _monthExpenses() => [
  _e('2025-10-01', 40000),
  _e('2025-10-05', 45000, cat: 'transport'),
  _e('2025-10-06', 5000, cur: 'USD'),
];

void main() {
  group('BudgetCalculator', () {
    final month = LocalDate(2025, 10, 1);
    final expenses = [
      _e('2025-10-01', 40000),
      _e('2025-10-05', 45000, cat: 'transport'),
      _e('2025-10-06', 5000, cur: 'USD'),
      _e('2025-09-30', 99999),
    ];

    test('overall budget counts all categories in the month and currency', () {
      final s = BudgetCalculator.status(
        budget: const Budget(
          id: 'overall',
          amountMinor: 100000,
          currencyCode: 'INR',
        ),
        expenses: expenses,
        month: month,
        thresholds: const [80, 100],
      );
      expect(s.spentMinor, 85000);
      expect(s.remainingMinor, 15000);
      expect(s.usedBasisPoints, 8500);
      expect(s.level, BudgetLevel.warning);
      expect(s.highestThresholdReached, 80);
    });

    test('category budget and exceeded level', () {
      final s = BudgetCalculator.status(
        budget: const Budget(
          id: 'cat_food',
          amountMinor: 30000,
          currencyCode: 'INR',
          categoryId: 'food',
        ),
        expenses: expenses,
        month: month,
        thresholds: const [80, 100],
      );
      expect(s.spentMinor, 40000);
      expect(s.level, BudgetLevel.exceeded);
      expect(s.highestThresholdReached, 100);
      expect(s.remainingMinor, -10000);
    });

    test('below thresholds is on track', () {
      final s = BudgetCalculator.status(
        budget: const Budget(
          id: 'cat_transport',
          amountMinor: 1000000,
          currencyCode: 'INR',
          categoryId: 'transport',
        ),
        expenses: expenses,
        month: month,
        thresholds: const [80, 100],
      );
      expect(s.level, BudgetLevel.onTrack);
      expect(s.highestThresholdReached, isNull);
    });

    test('budgets in another currency only count that currency', () {
      final s = BudgetCalculator.status(
        budget: const Budget(
          id: 'overall',
          amountMinor: 10000,
          currencyCode: 'USD',
        ),
        expenses: expenses,
        month: month,
        thresholds: const [80],
      );
      expect(s.spentMinor, 5000);
    });

    test('daily allowance spreads the remaining budget over the days left', () {
      const budget = Budget(
        id: 'overall',
        amountMinor: 310000,
        currencyCode: 'INR',
      );
      // 1 Oct: nothing spent yet, 31 days left -> 10000 per day.
      expect(
        BudgetCalculator.dailyAllowanceMinor(
          budget: budget,
          expenses: const [],
          today: LocalDate(2025, 10, 1),
        ),
        10000,
      );
      // 14 Oct: 85000 spent before today (today's spending is not deducted),
      // 225000 left over 18 days -> 12500 per day.
      expect(
        BudgetCalculator.dailyAllowanceMinor(
          budget: budget,
          expenses: [..._monthExpenses(), _e('2025-10-14', 99999)],
          today: LocalDate(2025, 10, 14),
        ),
        12500,
      );
      // Overspent budget never goes negative.
      expect(
        BudgetCalculator.dailyAllowanceMinor(
          budget: const Budget(
            id: 'overall',
            amountMinor: 1000,
            currencyCode: 'INR',
          ),
          expenses: _monthExpenses(),
          today: LocalDate(2025, 10, 14),
        ),
        0,
      );
    });

    test('statuses list puts overall first', () {
      final list = BudgetCalculator.statuses(
        budgets: const [
          Budget(
            id: 'cat_food',
            amountMinor: 1,
            currencyCode: 'INR',
            categoryId: 'food',
          ),
          Budget(id: 'overall', amountMinor: 1, currencyCode: 'INR'),
        ],
        expenses: expenses,
        month: month,
        thresholds: const [100],
      );
      expect(list.first.budget.isOverall, isTrue);
    });
  });

  group('TrackingStatusService', () {
    test('absence of expenses is not a confirmed zero day', () {
      expect(
        TrackingStatusService.effectiveState(stored: null, hasExpenses: false),
        DailyTrackingState.notReviewed,
      );
      expect(
        TrackingStatusService.effectiveState(stored: null, hasExpenses: true),
        DailyTrackingState.notReviewed,
      );
    });

    test('stored statuses resolve consistently', () {
      expect(
        TrackingStatusService.effectiveState(
          stored: StoredDayStatus.noExpenses,
          hasExpenses: false,
        ),
        DailyTrackingState.confirmedNoExpenses,
      );
      expect(
        TrackingStatusService.effectiveState(
          stored: StoredDayStatus.noExpenses,
          hasExpenses: true,
        ),
        DailyTrackingState.completedWithExpenses,
      );
      expect(
        TrackingStatusService.effectiveState(
          stored: StoredDayStatus.completed,
          hasExpenses: true,
        ),
        DailyTrackingState.completedWithExpenses,
      );
      expect(
        TrackingStatusService.statusForCompletion(hasExpenses: false),
        StoredDayStatus.noExpenses,
      );
    });

    test('incomplete days ignore days before the account existed', () {
      final today = LocalDate(2025, 10, 14);
      final result = TrackingStatusService.incompleteDays(
        today: today,
        stored: {LocalDate(2025, 10, 13): StoredDayStatus.completed},
        accountStart: LocalDate(2025, 10, 11),
      );
      expect(result, [LocalDate(2025, 10, 12), LocalDate(2025, 10, 11)]);
    });
  });

  group('ReminderPlanner', () {
    final now = DateTime(2025, 10, 14, 18, 0);
    const settings = ReminderSettings(enabled: true);

    test('disabled reminders plan nothing', () {
      expect(
        ReminderPlanner.plan(
          now: now,
          settings: const ReminderSettings(),
          completedDays: {},
        ),
        isEmpty,
      );
    });

    test('default schedule is 22:00 with follow-ups at 22:45 and 23:30', () {
      final plan = ReminderPlanner.plan(
        now: now,
        settings: settings,
        completedDays: {},
        days: 1,
      );
      expect(plan.map((r) => r.at), [
        DateTime(2025, 10, 14, 22, 0),
        DateTime(2025, 10, 14, 22, 45),
        DateTime(2025, 10, 14, 23, 30),
      ]);
      expect(plan.first.isFollowUp, isFalse);
      expect(plan.first.payload, '/calendar/day/2025-10-14');
    });

    test('completed days get no reminders or follow-ups', () {
      final plan = ReminderPlanner.plan(
        now: now,
        settings: settings,
        completedDays: {LocalDate(2025, 10, 14)},
        days: 2,
      );
      expect(plan.every((r) => r.day == LocalDate(2025, 10, 15)), isTrue);
      expect(plan.length, 3);
    });

    test('past times are skipped', () {
      final late = DateTime(2025, 10, 14, 22, 50);
      final plan = ReminderPlanner.plan(
        now: late,
        settings: settings,
        completedDays: {},
        days: 1,
      );
      expect(plan.map((r) => r.at), [DateTime(2025, 10, 14, 23, 30)]);
    });

    test('quiet hours and follow-up toggle are respected', () {
      final quiet = settings.copyWith(
        quietHoursEnabled: true,
        quietStartMinutes: 23 * 60,
        quietEndMinutes: 7 * 60,
      );
      final plan = ReminderPlanner.plan(
        now: now,
        settings: quiet,
        completedDays: {},
        days: 1,
      );
      expect(plan.length, 2);
      final noFollow = ReminderPlanner.plan(
        now: now,
        settings: settings.copyWith(followUpsEnabled: false),
        completedDays: {},
        days: 1,
      );
      expect(noFollow.length, 1);
    });

    test('follow-ups before the main reminder are ignored; ids are unique', () {
      final s = settings.copyWith(
        timeMinutes: 21 * 60,
        followUpMinutes: [20 * 60, 21 * 60 + 30],
      );
      final plan = ReminderPlanner.plan(
        now: now,
        settings: s,
        completedDays: {},
      );
      expect(plan.where((r) => r.day == LocalDate(2025, 10, 14)).length, 2);
      expect(plan.length, 2 * ReminderPlanner.horizonDays);
      expect(plan.map((r) => r.id).toSet().length, plan.length);
    });

    test('quiet hours window wraps midnight', () {
      const r = ReminderSettings(
        quietHoursEnabled: true,
        quietStartMinutes: 23 * 60,
        quietEndMinutes: 7 * 60,
      );
      expect(r.isQuiet(23 * 60 + 30), isTrue);
      expect(r.isQuiet(6 * 60), isTrue);
      expect(r.isQuiet(12 * 60), isFalse);
    });
  });

  group('CsvExporter', () {
    final cats = {for (final c in DefaultCategories.all) c.id: c};

    test('writes header and rows oldest first with plain decimals', () {
      final csv = CsvExporter.build([
        _e('2025-10-02', 12050, note: 'Lunch'),
        _e('2025-10-01', 500, cat: 'transport', cur: 'JPY'),
      ], cats);
      final lines = csv.trim().split('\r\n');
      expect(lines.first, CsvExporter.headers.join(','));
      expect(lines[1], startsWith('2025-10-01,500,JPY,Transportation'));
      expect(
        lines[2],
        startsWith('2025-10-02,120.50,INR,Food and Drinks,,Lunch'),
      );
    });

    test('escapes quotes, commas and neutralises formulas', () {
      expect(CsvExporter.escape('a,b'), '"a,b"');
      expect(CsvExporter.escape('say "hi"'), '"say ""hi"""');
      expect(CsvExporter.escape('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
      expect(CsvExporter.escape('+1'), "'+1");
      expect(CsvExporter.escape('plain'), 'plain');
    });

    test('safe file name', () {
      expect(
        CsvExporter.fileName(
          DateRange(LocalDate(2025, 1, 1), LocalDate(2025, 1, 31)),
        ),
        'daily-expense-buddy_2025-01-01_to_2025-01-31.csv',
      );
    });
  });

  group('ExpenseValidator', () {
    final today = LocalDate(2025, 10, 14);

    test('valid input', () {
      final r = ExpenseValidator.validate(
        ExpenseInput(amountText: '12.5', currencyCode: 'INR', date: today),
        today: today,
      );
      expect(r.isValid, isTrue);
      expect(r.amountMinor, 1250);
    });

    test('rejects future dates, missing dates and long notes', () {
      expect(
        ExpenseValidator.validate(
          ExpenseInput(
            amountText: '1',
            currencyCode: 'INR',
            date: today.addDays(1),
          ),
          today: today,
        ).dateError,
        isNotNull,
      );
      expect(
        ExpenseValidator.validate(
          const ExpenseInput(amountText: '1', currencyCode: 'INR', date: null),
          today: today,
        ).isValid,
        isFalse,
      );
      expect(
        ExpenseValidator.validate(
          ExpenseInput(
            amountText: '1',
            currencyCode: 'INR',
            date: today,
            note: 'x' * 201,
          ),
          today: today,
        ).noteError,
        isNotNull,
      );
    });

    test('previous dates are allowed', () {
      final r = ExpenseValidator.validate(
        ExpenseInput(
          amountText: '5',
          currencyCode: 'INR',
          date: LocalDate(2024, 2, 29),
        ),
        today: today,
      );
      expect(r.isValid, isTrue);
    });
  });

  group('ReminderSettings serialization', () {
    test('round trip and defensive parsing', () {
      const s = ReminderSettings(
        enabled: true,
        timeMinutes: 1200,
        followUpMinutes: [1260],
      );
      expect(ReminderSettings.fromMap(s.toMap()), s);
      final bad = ReminderSettings.fromMap({
        'timeMinutes': 99999,
        'enabled': 'yes',
        'followUpMinutes': ['x', 1300, 5000],
      });
      expect(bad.timeMinutes, 22 * 60);
      expect(bad.enabled, isFalse);
      expect(bad.followUpMinutes, [1300]);
    });
  });

  group('DefaultCategories.merge', () {
    test('applies overrides and appends custom categories', () {
      final merged = DefaultCategories.merge(const [
        ExpenseCategory(
          id: 'food',
          name: 'Eating out',
          iconKey: 'coffee',
          colorIndex: 1,
          isArchived: true,
          sortOrder: 0,
        ),
        ExpenseCategory(
          id: 'custom1',
          name: 'Pets',
          iconKey: 'pets',
          colorIndex: 3,
          sortOrder: 200,
        ),
      ]);
      final food = merged.firstWhere((c) => c.id == 'food');
      expect(food.name, 'Eating out');
      expect(food.isBuiltIn, isTrue);
      expect(food.isArchived, isTrue);
      expect(merged.last.id, 'custom1');
      expect(merged.length, DefaultCategories.all.length + 1);
    });
  });
}
