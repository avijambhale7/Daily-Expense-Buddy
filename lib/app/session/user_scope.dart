import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/theme_cubit.dart';
import '../../domain/models/premium_entitlement.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/user_preferences.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../features/budgets/budget_alert_coordinator.dart';
import '../../features/reminders/reminder_coordinator.dart';
import '../app_dependencies.dart';
import 'session_cubits.dart';
import 'user_session.dart';

/// Exposes the current [UserSession] (or null when signed out).
class SessionScope extends InheritedWidget {
  const SessionScope({super.key, required this.session, required super.child});

  final UserSession? session;

  static UserSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()?.session;

  /// Non-listening lookup, safe inside `BlocProvider.create` and
  /// callbacks. Screens are additionally guarded by [RequireSession], which
  /// does listen, so they never outlive the session.
  static UserSession of(BuildContext context) {
    final s = context.getInheritedWidgetOfExactType<SessionScope>()?.session;
    if (s == null) throw StateError('No signed-in user session');
    return s;
  }

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      oldWidget.session != session;
}

/// Renders [builder] only while a user session exists. Protected screens are
/// wrapped in this so that, during the frame in which a user signs out and
/// before navigation completes, they render nothing rather than touching
/// disposed session state.
class RequireSession extends StatelessWidget {
  const RequireSession({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (SessionScope.maybeOf(context) == null) return const SizedBox.shrink();
    return builder(context);
  }
}

/// Creates a [UserSession] and its long-lived controllers when a verified
/// user signs in, and tears everything down (including scheduled reminders
/// and the device's cached data) when they sign out.
class UserScope extends StatefulWidget {
  const UserScope({super.key, required this.child, required this.onMessage});

  final Widget child;
  final void Function(String message) onMessage;

  @override
  State<UserScope> createState() => _UserScopeState();
}

class _ActiveSession {
  _ActiveSession({
    required this.session,
    required this.preferences,
    required this.categories,
    required this.entitlement,
    required this.reminders,
    required this.budgetAlerts,
    required this.subscriptions,
  });

  final UserSession session;
  final PreferencesCubit preferences;
  final CategoriesCubit categories;
  final EntitlementCubit entitlement;
  final ReminderCoordinator reminders;
  final BudgetAlertCoordinator budgetAlerts;
  final List<StreamSubscription<Object?>> subscriptions;

  Future<void> close() async {
    // Start coordinator disposal first: their timers are cancelled
    // synchronously, before any await below.
    final remindersDone = reminders.dispose();
    final alertsDone = budgetAlerts.dispose();
    for (final s in subscriptions) {
      await s.cancel();
    }
    await remindersDone;
    await alertsDone;
    await preferences.close();
    await categories.close();
    await entitlement.close();
  }
}

class _UserScopeState extends State<UserScope> {
  _ActiveSession? _active;

  @override
  void initState() {
    super.initState();
    _apply(context.read<AuthCubit>().state);
  }

  void _apply(AuthState auth) {
    final user = auth.isAuthenticated ? auth.user : null;
    if (user?.uid == _active?.session.uid) return;
    final previous = _active;
    _active = null;
    if (previous != null) _end(previous, signedOut: user == null);
    if (user != null) _active = _start(user);
  }

  _ActiveSession _start(UserProfile user) {
    final deps = context.read<AppDependencies>();
    final themeCubit = context.read<ThemeCubit>();
    final session = deps.sessionFactory!(user);
    AppLogger.info('Session', 'Session started');

    final preferences = PreferencesCubit(
      session.preferences,
      defaults: UserPreferences.defaultsFor(deps.locale),
    );
    final categories = CategoriesCubit(session.categories, session.expenses);
    final entitlement = EntitlementCubit(session.entitlements);

    final reminders = ReminderCoordinator(
      notifications: deps.notifications,
      preferences: preferences,
      statuses: session.dailyStatus,
      loans: session.loans,
      now: deps.now,
    )..start();
    final budgetAlerts = BudgetAlertCoordinator(
      budgets: session.budgets,
      expenses: session.expenses,
      preferences: preferences,
      categories: categories,
      notifications: deps.notifications,
      onAlert: widget.onMessage,
      now: deps.now,
    )..start();

    void applyPremium(PremiumEntitlement e) =>
        themeCubit.setPremiumUnlocked(e.isPremium(deps.now()));
    applyPremium(entitlement.state);

    unawaited(session.userData.ensureProfile(session.user));

    return _ActiveSession(
      session: session,
      preferences: preferences,
      categories: categories,
      entitlement: entitlement,
      reminders: reminders,
      budgetAlerts: budgetAlerts,
      subscriptions: [
        entitlement.stream.listen(applyPremium),
        session.syncIssues.listen(
          (AppFailure f) => widget.onMessage(f.message),
        ),
      ],
    );
  }

  void _end(_ActiveSession active, {required bool signedOut}) {
    final deps = context.read<AppDependencies>();
    context.read<ThemeCubit>().setPremiumUnlocked(false);
    unawaited(() async {
      try {
        await active.close();
        if (signedOut) await deps.clearLocalData?.call();
        AppLogger.info('Session', 'Session ended');
      } catch (e, st) {
        AppLogger.error('Session', 'Error while ending session', e, st);
      }
    }());
  }

  @override
  void dispose() {
    final active = _active;
    _active = null;
    if (active != null) unawaited(active.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final content = active == null
        ? SessionScope(session: null, child: widget.child)
        : MultiRepositoryProvider(
            providers: [
              RepositoryProvider.value(value: active.session),
              RepositoryProvider.value(value: active.reminders),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: active.preferences),
                BlocProvider.value(value: active.categories),
                BlocProvider.value(value: active.entitlement),
              ],
              child: SessionScope(session: active.session, child: widget.child),
            ),
          );
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (p, c) =>
          p.isAuthenticated != c.isAuthenticated || p.user?.uid != c.user?.uid,
      listener: (context, auth) => setState(() => _apply(auth)),
      child: content,
    );
  }
}
