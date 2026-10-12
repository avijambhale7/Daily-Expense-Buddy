import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubits.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/dates/report_period.dart';
import '../../../core/errors/app_failure.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/report_summary.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/report_calculator.dart';

class ReportState extends Equatable {
  const ReportState({
    required this.period,
    required this.today,
    this.status = LoadStatus.loading,
    this.summary,
    this.error,
  });

  final ReportPeriod period;
  final LocalDate today;
  final LoadStatus status;
  final ReportSummary? summary;
  final String? error;

  bool get canGoNext =>
      period.type != ReportPeriodType.custom && !period.next.isFuture(today);

  ReportState copyWith({
    ReportPeriod? period,
    LoadStatus? status,
    ReportSummary? Function()? summary,
    String? Function()? error,
  }) => ReportState(
    period: period ?? this.period,
    today: today,
    status: status ?? this.status,
    summary: summary != null ? summary() : this.summary,
    error: error != null ? error() : this.error,
  );

  @override
  List<Object?> get props => [period, today, status, summary, error];
}

/// Loads the selected period plus the equivalent previous period in one live
/// query and computes the report with [ReportCalculator].
class ReportCubit extends Cubit<ReportState> {
  ReportCubit({
    required this._expenses,
    required PreferencesCubit preferences,
    required LocalDate today,
  }) : _preferences = preferences,
       super(
         ReportState(
           today: today,
           period: ReportPeriod.of(
             ReportPeriodType.month,
             today,
             weekStart: preferences.preferences.weekStart,
           ),
         ),
       ) {
    _prefsSub = _preferences.stream.listen((p) {
      final prefs = p.preferences;
      if (prefs.weekStart != state.period.weekStart &&
          state.period.type == ReportPeriodType.week) {
        _setPeriod(
          ReportPeriod.of(
            ReportPeriodType.week,
            state.period.range.start,
            weekStart: prefs.weekStart,
          ),
        );
      } else {
        _recompute();
      }
    });
    _subscribe();
  }

  final ExpenseRepository _expenses;
  final PreferencesCubit _preferences;
  StreamSubscription<List<Expense>>? _sub;
  StreamSubscription<PreferencesState>? _prefsSub;
  List<Expense>? _list;

  void setType(ReportPeriodType type) {
    if (type == state.period.type) return;
    final anchor = state.period.range.contains(state.today)
        ? state.today
        : state.period.range.start;
    if (type == ReportPeriodType.custom) {
      _setPeriod(
        ReportPeriod.custom(DateRange(state.today.addDays(-29), state.today)),
      );
    } else {
      _setPeriod(
        ReportPeriod.of(
          type,
          anchor,
          weekStart: _preferences.preferences.weekStart,
        ),
      );
    }
  }

  void previous() => _setPeriod(state.period.previous);

  void next() {
    if (state.canGoNext) _setPeriod(state.period.next);
  }

  void showToday() => _setPeriod(
    ReportPeriod.of(
      state.period.type == ReportPeriodType.custom
          ? ReportPeriodType.month
          : state.period.type,
      state.today,
      weekStart: _preferences.preferences.weekStart,
    ),
  );

  void setCustomRange(DateRange range) =>
      _setPeriod(ReportPeriod.custom(range));

  void retry() => _subscribe();

  void _setPeriod(ReportPeriod period) {
    emit(state.copyWith(period: period, status: LoadStatus.loading));
    _subscribe();
  }

  void _subscribe() {
    unawaited(_sub?.cancel());
    _list = null;
    final p = state.period;
    final range = DateRange(p.previous.range.start, p.range.end);
    _sub = _expenses
        .watchRange(range)
        .listen(
          (list) {
            _list = list;
            _recompute();
          },
          onError: (Object e) {
            if (isClosed) return;
            emit(
              state.copyWith(
                status: LoadStatus.failure,
                error: () =>
                    e is AppFailure ? e.message : AppFailure.unknown(e).message,
              ),
            );
          },
        );
  }

  void _recompute() {
    final list = _list;
    if (list == null || isClosed) return;
    emit(
      state.copyWith(
        status: LoadStatus.ready,
        error: () => null,
        summary: () => ReportCalculator.summarize(
          period: state.period,
          expenses: list,
          currencyCode: _preferences.preferences.currencyCode,
          today: state.today,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _prefsSub?.cancel();
    return super.close();
  }
}
