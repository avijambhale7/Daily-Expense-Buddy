import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubits.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../domain/models/budget.dart';
import '../../../domain/models/daily_status.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/report_summary.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/report_calculator.dart';

class DashboardState extends Equatable {
  const DashboardState({
    this.status = LoadStatus.loading,
    this.summary,
    this.error,
  });

  final LoadStatus status;
  final DashboardSummary? summary;
  final String? error;

  @override
  List<Object?> get props => [status, summary, error];
}

/// Live dashboard figures. Listens to the expenses of the current year (plus
/// the current week and last six months) and recomputes the summary through
/// [ReportCalculator] on every change, so edits from any device appear
/// immediately.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required this._expenses,
    required this._statuses,
    required this._preferences,
    this._accountStart,
    BudgetRepository? budgets,
    this._now = DateTime.now,
  }) : super(const DashboardState()) {
    _budgetSub = budgets?.watchAll().listen((list) {
      _overallBudget = list.where((b) => b.isOverall).firstOrNull;
      _recompute();
    }, onError: (Object _) {});
    _prefsSub = _preferences.stream.listen((p) {
      final prefs = p.preferences;
      if (prefs.weekStart != _weekStart || prefs.currencyCode != _currency) {
        _subscribe();
      }
    });
    _subscribe();
  }

  final ExpenseRepository _expenses;
  final DailyStatusRepository _statuses;
  final PreferencesCubit _preferences;
  final LocalDate? _accountStart;
  final DateTime Function() _now;

  StreamSubscription<PreferencesState>? _prefsSub;
  StreamSubscription<List<Expense>>? _expenseSub;
  StreamSubscription<Map<LocalDate, StoredDayStatus>>? _statusSub;
  StreamSubscription<List<Budget>>? _budgetSub;
  Budget? _overallBudget;
  Timer? _midnight;

  List<Expense>? _list;
  Map<LocalDate, StoredDayStatus> _statusMap = const {};
  int _weekStart = DateTime.monday;
  String _currency = '';
  LocalDate? _today;

  /// Re-subscribes (used by "Try again" and when the date changes).
  void retry() => _subscribe();

  /// Called when the app resumes; refreshes if the calendar day changed.
  void refreshIfDayChanged() {
    if (_today != LocalDate.today(_now)) _subscribe();
  }

  void _subscribe() {
    unawaited(_expenseSub?.cancel());
    unawaited(_statusSub?.cancel());
    _midnight?.cancel();
    final prefs = _preferences.state.preferences;
    _weekStart = prefs.weekStart;
    _currency = prefs.currencyCode;
    final today = LocalDate.today(_now);
    _today = today;
    _list = null;
    if (state.summary == null) emit(const DashboardState());

    _expenseSub = _expenses
        .watchRange(ReportCalculator.dashboardRange(today, _weekStart))
        .listen((list) {
          _list = list;
          _recompute();
        }, onError: _onError);
    _statusSub = _statuses
        .watchRange(DateRange(today.addDays(-7), today))
        .listen((map) {
          _statusMap = map;
          _recompute();
        }, onError: _onError);

    final now = _now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 1),
      _subscribe,
    );
  }

  void _onError(Object e) {
    if (isClosed) return;
    emit(
      DashboardState(
        status: LoadStatus.failure,
        summary: state.summary,
        error: e is AppFailure ? e.message : AppFailure.unknown(e).message,
      ),
    );
  }

  void _recompute() {
    final list = _list;
    final today = _today;
    if (list == null || today == null || isClosed) return;
    emit(
      DashboardState(
        status: LoadStatus.ready,
        summary: ReportCalculator.dashboard(
          expenses: list,
          currencyCode: _currency,
          today: today,
          weekStart: _weekStart,
          statuses: _statusMap,
          accountStart: _accountStart,
          overallBudget: _overallBudget,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    _midnight?.cancel();
    await _prefsSub?.cancel();
    await _expenseSub?.cancel();
    await _statusSub?.cancel();
    await _budgetSub?.cancel();
    return super.close();
  }
}
