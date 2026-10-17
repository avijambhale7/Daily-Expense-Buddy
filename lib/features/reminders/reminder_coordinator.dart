import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/session/session_cubits.dart';
import '../../core/dates/local_date.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/daily_status.dart';
import '../../domain/models/loan.dart';
import '../../domain/models/user_preferences.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/reminder_planner.dart';
import '../../services/notifications/notification_service.dart';

/// Keeps scheduled reminder notifications in sync with the user's reminder
/// settings and daily completion statuses.
///
/// Whenever a day is marked complete (on any device – statuses sync through
/// Firestore) its remaining reminders and follow-ups are removed. The plan is
/// also refreshed when the app returns to the foreground.
class ReminderCoordinator {
  ReminderCoordinator({
    required this._notifications,
    required this._preferences,
    required this._statuses,
    this._loans,
    this._now = DateTime.now,
  });

  final NotificationService _notifications;
  final PreferencesCubit _preferences;
  final DailyStatusRepository _statuses;

  /// Optional: open loans with a due date get one reminder on that day.
  final LoanRepository? _loans;
  final DateTime Function() _now;

  StreamSubscription<PreferencesState>? _prefsSub;
  StreamSubscription<Map<LocalDate, StoredDayStatus>>? _statusSub;
  StreamSubscription<List<Loan>>? _loanSub;
  List<Loan> _openLoans = const [];
  AppLifecycleListener? _lifecycle;
  Timer? _debounce;
  LocalDate? _windowStart;
  Set<LocalDate> _completed = {};
  ReminderSettings? _settings;
  bool _disposed = false;

  void start() {
    _settings = _preferences.state.preferences.reminders;
    _prefsSub = _preferences.stream.listen((s) {
      if (s.preferences.reminders != _settings) {
        _settings = s.preferences.reminders;
        _schedule();
      }
    });
    _watchStatuses();
    _loanSub = _loans?.watchAll().listen((all) {
      final next = [
        for (final l in all)
          if (!l.settled && l.dueDate != null) l,
      ];
      if (!_sameDueDates(next, _openLoans)) {
        _openLoans = next;
        _schedule();
      }
    }, onError: (Object e) => AppLogger.warn('Reminders', 'Loans error', e));
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_windowStart != LocalDate.today(_now)) _watchStatuses();
        _schedule();
      },
    );
    _schedule();
  }

  void _watchStatuses() {
    unawaited(_statusSub?.cancel());
    final today = LocalDate.today(_now);
    _windowStart = today;
    _statusSub = _statuses
        .watchRange(
          DateRange(today, today.addDays(ReminderPlanner.horizonDays - 1)),
        )
        .listen(
          (map) {
            _completed = map.keys.toSet();
            _schedule();
          },
          onError: (Object e) => AppLogger.warn('Reminders', 'Status error', e),
        );
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _apply);
  }

  /// Forces an immediate refresh (e.g. after permission was granted).
  Future<void> refresh() => _apply();

  Future<void> _apply() async {
    if (_disposed) return;
    final settings = _settings ?? const ReminderSettings();
    if (!settings.enabled ||
        _notifications.capability == ReminderCapability.unsupported ||
        !await _notifications.hasPermission()) {
      await _notifications.cancelAllReminders();
      return;
    }
    if (_disposed) return;
    final plan = [
      ...ReminderPlanner.plan(
        now: _now(),
        settings: settings,
        completedDays: _completed,
      ),
      ...ReminderPlanner.planLoanDue(
        now: _now(),
        settings: settings,
        loans: _openLoans,
      ),
    ];
    await _notifications.syncReminders(plan);
  }

  /// Stops listening and removes this user's pending reminders.
  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    _lifecycle?.dispose();
    await _prefsSub?.cancel();
    await _statusSub?.cancel();
    await _loanSub?.cancel();
    await _notifications.cancelAllReminders();
  }

  /// Only due dates, names and directions affect the plan; ignore other
  /// edits (e.g. a partial repayment) to avoid needless rescheduling.
  static bool _sameDueDates(List<Loan> a, List<Loan> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].dueDate != b[i].dueDate ||
          a[i].personName != b[i].personName ||
          a[i].direction != b[i].direction) {
        return false;
      }
    }
    return true;
  }
}
