import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/session/session_cubits.dart';
import '../../core/dates/local_date.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/budget.dart';
import '../../domain/models/expense.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/budget_calculator.dart';
import '../../services/notifications/notification_service.dart';

/// Watches the current month's spending and raises a budget alert once per
/// budget, threshold and month.
///
/// Duplicate alerts are prevented across devices by atomically recording
/// each alert in Firestore (`budget_alerts`) before notifying.
class BudgetAlertCoordinator {
  BudgetAlertCoordinator({
    required this._budgets,
    required this._expenses,
    required this._preferences,
    required this._categories,
    required this._notifications,
    required this._onAlert,
    this._now = DateTime.now,
  });

  final BudgetRepository _budgets;
  final ExpenseRepository _expenses;
  final PreferencesCubit _preferences;
  final CategoriesCubit _categories;
  final NotificationService _notifications;
  final void Function(String message) _onAlert;
  final DateTime Function() _now;

  StreamSubscription<List<Budget>>? _budgetSub;
  StreamSubscription<List<Expense>>? _expenseSub;
  AppLifecycleListener? _lifecycle;
  List<Budget>? _budgetList;
  List<Expense>? _monthExpenses;
  LocalDate? _month;
  Timer? _debounce;
  final _handled = <String>{};
  bool _disposed = false;

  void start() {
    _budgetSub = _budgets.watchAll().listen((b) {
      _budgetList = b;
      _evaluateSoon();
    }, onError: (Object e) => AppLogger.warn('BudgetAlerts', 'Budgets', e));
    _watchMonth();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_month != LocalDate.today(_now).startOfMonth) _watchMonth();
      },
    );
  }

  void _watchMonth() {
    unawaited(_expenseSub?.cancel());
    final month = LocalDate.today(_now).startOfMonth;
    _month = month;
    _monthExpenses = null;
    _expenseSub = _expenses
        .watchRange(DateRange(month, month.endOfMonth))
        .listen(
          (list) {
            // Only evaluate on server-confirmed data to avoid alerting on
            // half-synced state.
            if (list.any((e) => e.hasPendingWrites)) return;
            _monthExpenses = list;
            _evaluateSoon();
          },
          onError: (Object e) => AppLogger.warn('BudgetAlerts', 'Expenses', e),
        );
  }

  void _evaluateSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _evaluate);
  }

  Future<void> _evaluate() async {
    final budgets = _budgetList;
    final expenses = _monthExpenses;
    final month = _month;
    if (_disposed || budgets == null || expenses == null || month == null) {
      return;
    }
    final thresholds = _preferences.state.preferences.budgetAlertThresholds;
    final statuses = BudgetCalculator.statuses(
      budgets: budgets,
      expenses: expenses,
      month: month,
      thresholds: thresholds,
    );
    for (final s in statuses) {
      final reached = s.highestThresholdReached;
      if (reached == null) continue;
      final key = '${month.monthKey}_${s.budget.id}_$reached';
      if (_handled.contains(key)) continue;
      _handled.add(key);
      final claimed = await _budgets.claimAlert(
        monthKey: month.monthKey,
        budgetId: s.budget.id,
        threshold: reached,
      );
      if (_disposed) return;
      if (!claimed) {
        // Either already alerted (fine) or offline (retry later).
        _handled.remove(key);
        continue;
      }
      _handled.add(key);
      final name = s.budget.categoryId == null
          ? 'overall'
          : _categories.state.resolve(s.budget.categoryId!).name;
      final monthName = DateFormat.MMMM().format(month.toDateTime());
      final message = reached >= 100
          ? "You've reached $reached% of your $name budget for $monthName."
          : "You've used $reached% of your $name budget for $monthName.";
      _onAlert(message);
      await _notifications.showNow(
        id: 900000 + (s.budget.id.hashCode & 0xFFFF),
        title: 'Budget alert',
        body: '$message Based on the expenses you recorded.',
        route: '/budgets',
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    _lifecycle?.dispose();
    await _budgetSub?.cancel();
    await _expenseSub?.cancel();
  }
}
