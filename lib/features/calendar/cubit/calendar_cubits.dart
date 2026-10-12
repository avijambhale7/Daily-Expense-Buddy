import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubits.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../domain/models/daily_status.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/report_calculator.dart';
import '../../../domain/services/tracking_status_service.dart';

class CalendarDay extends Equatable {
  const CalendarDay({
    required this.date,
    required this.totalMinor,
    required this.count,
    required this.state,
  });

  final LocalDate date;
  final int totalMinor;
  final int count;
  final DailyTrackingState state;

  @override
  List<Object?> get props => [date, totalMinor, count, state];
}

class CalendarState extends Equatable {
  const CalendarState({
    required this.month,
    this.status = LoadStatus.loading,
    this.days = const {},
    this.monthTotalMinor = 0,
    this.error,
  });

  /// First day of the displayed month.
  final LocalDate month;
  final LoadStatus status;
  final Map<LocalDate, CalendarDay> days;
  final int monthTotalMinor;
  final String? error;

  @override
  List<Object?> get props => [month, status, days, monthTotalMinor, error];
}

/// Month view combining daily totals and tracking statuses. Uses the same
/// [TrackingStatusService] as the dashboard and reminder scheduling.
class CalendarCubit extends Cubit<CalendarState> {
  CalendarCubit({
    required this._expenses,
    required this._statuses,
    required this._preferences,
    required LocalDate today,
  }) : super(CalendarState(month: today.startOfMonth)) {
    _prefsSub = _preferences.stream.listen((_) => _recompute());
    _subscribe();
  }

  final ExpenseRepository _expenses;
  final DailyStatusRepository _statuses;
  final PreferencesCubit _preferences;
  StreamSubscription<List<Expense>>? _expSub;
  StreamSubscription<Map<LocalDate, StoredDayStatus>>? _statusSub;
  StreamSubscription<PreferencesState>? _prefsSub;
  List<Expense>? _list;
  Map<LocalDate, StoredDayStatus>? _statusMap;

  void showMonth(LocalDate month) {
    emit(CalendarState(month: month.startOfMonth));
    _subscribe();
  }

  void previousMonth() => showMonth(state.month.addMonths(-1));
  void nextMonth() => showMonth(state.month.addMonths(1));
  void retry() => _subscribe();

  void _subscribe() {
    unawaited(_expSub?.cancel());
    unawaited(_statusSub?.cancel());
    _list = null;
    _statusMap = null;
    final range = DateRange(state.month, state.month.endOfMonth);
    void onError(Object e) {
      if (isClosed) return;
      emit(
        CalendarState(
          month: state.month,
          status: LoadStatus.failure,
          days: state.days,
          error: e is AppFailure ? e.message : AppFailure.unknown(e).message,
        ),
      );
    }

    _expSub = _expenses.watchRange(range).listen((l) {
      _list = l;
      _recompute();
    }, onError: onError);
    _statusSub = _statuses.watchRange(range).listen((m) {
      _statusMap = m;
      _recompute();
    }, onError: onError);
  }

  void _recompute() {
    final list = _list;
    final statusMap = _statusMap;
    if (list == null || statusMap == null || isClosed) return;
    final currency = _preferences.preferences.currencyCode;
    final range = DateRange(state.month, state.month.endOfMonth);
    final totals = ReportCalculator.dailyTotalsMap(list, currency, range);
    final counts = <LocalDate, int>{};
    for (final e in list) {
      counts[e.date] = (counts[e.date] ?? 0) + 1;
    }
    emit(
      CalendarState(
        month: state.month,
        status: LoadStatus.ready,
        monthTotalMinor: ReportCalculator.totalFor(list, currency, range),
        days: {
          for (final d in range.days)
            d: CalendarDay(
              date: d,
              totalMinor: totals[d] ?? 0,
              count: counts[d] ?? 0,
              state: TrackingStatusService.effectiveState(
                stored: statusMap[d],
                hasExpenses: (counts[d] ?? 0) > 0,
              ),
            ),
        },
      ),
    );
  }

  @override
  Future<void> close() async {
    await _expSub?.cancel();
    await _statusSub?.cancel();
    await _prefsSub?.cancel();
    return super.close();
  }
}

class DayState extends Equatable {
  const DayState({
    this.status = LoadStatus.loading,
    this.expenses = const [],
    this.stored,
    this.error,
  });

  final LoadStatus status;
  final List<Expense> expenses;
  final StoredDayStatus? stored;
  final String? error;

  DailyTrackingState get trackingState => TrackingStatusService.effectiveState(
    stored: stored,
    hasExpenses: expenses.isNotEmpty,
  );

  @override
  List<Object?> get props => [status, expenses, stored, error];
}

class DayCubit extends Cubit<DayState> {
  DayCubit({
    required ExpenseRepository expenses,
    required DailyStatusRepository statuses,
    required this.date,
  }) : super(const DayState()) {
    final range = DateRange(date, date);
    _expSub = expenses.watchRange(range).listen((l) {
      _list = [...l]..sort(Expense.newestFirst);
      _emit();
    }, onError: _onError);
    _statusSub = statuses.watchRange(range).listen((m) {
      _stored = m[date];
      _statusLoaded = true;
      _emit();
    }, onError: _onError);
  }

  final LocalDate date;
  StreamSubscription<List<Expense>>? _expSub;
  StreamSubscription<Map<LocalDate, StoredDayStatus>>? _statusSub;
  List<Expense>? _list;
  StoredDayStatus? _stored;
  bool _statusLoaded = false;

  void _emit() {
    final list = _list;
    if (list == null || !_statusLoaded || isClosed) return;
    emit(DayState(status: LoadStatus.ready, expenses: list, stored: _stored));
  }

  void _onError(Object e) {
    if (isClosed) return;
    emit(
      DayState(
        status: LoadStatus.failure,
        error: e is AppFailure ? e.message : AppFailure.unknown(e).message,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _expSub?.cancel();
    await _statusSub?.cancel();
    return super.close();
  }
}
