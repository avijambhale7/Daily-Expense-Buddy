import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/dates/local_date.dart';
import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/premium_entitlement.dart';
import '../../domain/models/recurring_expense.dart';
import '../../domain/repositories/repositories.dart';

/// Adds the expenses of recurring templates when they fall due.
///
/// Runs while premium is active: when the session starts, whenever the
/// templates change, and when the app returns to the foreground. Each
/// occurrence uses a deterministic expense id, so another device adding the
/// same occurrence can never create a duplicate.
class RecurringCoordinator {
  RecurringCoordinator({
    required this._templates,
    required this._expenses,
    required this._entitlement,
    required this._entitlementNow,
    this._now = DateTime.now,
  });

  final RecurringRepository _templates;
  final ExpenseRepository _expenses;
  final Stream<PremiumEntitlement> _entitlement;
  final PremiumEntitlement Function() _entitlementNow;
  final DateTime Function() _now;

  StreamSubscription<List<RecurringExpense>>? _sub;
  StreamSubscription<PremiumEntitlement>? _entSub;
  AppLifecycleListener? _lifecycle;
  List<RecurringExpense> _latest = const [];
  bool _running = false;
  bool _disposed = false;

  /// Completes after each run; for tests.
  final _runs = StreamController<int>.broadcast();
  Stream<int> get runs => _runs.stream;

  void start() {
    _sub = _templates.watchAll().listen((list) {
      _latest = list;
      unawaited(run());
    }, onError: (Object e) => AppLogger.warn('Recurring', 'Watch failed', e));
    _entSub = _entitlement.listen((_) => unawaited(run()));
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(run()));
  }

  bool get _premium => _entitlementNow().isPremium(_now());

  /// Adds every due occurrence; returns how many expenses were added.
  Future<int> run() async {
    if (_disposed || _running || !_premium) return 0;
    _running = true;
    var added = 0;
    try {
      final today = LocalDate.today(_now);
      for (final t in _latest) {
        final due = t.dueDates(today);
        if (due.isEmpty) continue;
        LocalDate? posted;
        for (final date in due) {
          if (_disposed) return added;
          try {
            await _expenses.create(t.expenseFor(date));
            added++;
            posted = date;
          } on AppFailure catch (f) {
            // Already added by another device: the rules reject a second
            // create of the same id. Anything else stops this template and
            // it is retried on the next run.
            if (f.kind == FailureKind.permissionDenied ||
                f.kind == FailureKind.conflict) {
              posted = date;
            } else {
              AppLogger.warn('Recurring', 'Add failed: ${f.kind}');
              break;
            }
          }
        }
        if (posted != null) await _templates.markPosted(t.id, posted);
      }
    } catch (e) {
      AppLogger.warn('Recurring', 'Run failed', e);
    } finally {
      _running = false;
      if (!_runs.isClosed) _runs.add(added);
    }
    return added;
  }

  Future<void> dispose() async {
    _disposed = true;
    _lifecycle?.dispose();
    await _sub?.cancel();
    await _entSub?.cancel();
    await _runs.close();
  }
}
