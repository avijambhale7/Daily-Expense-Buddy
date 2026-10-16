import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/dates/local_date.dart';
import '../core/widgets/common.dart';
import '../features/auth/cubit/auth_cubit.dart';
import '../features/auth/presentation/auth_pages.dart';
import '../features/auth/presentation/onboarding_page.dart';
import '../features/auth/presentation/setup_pages.dart';
import '../features/budgets/presentation/budgets_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/calendar/presentation/day_detail_page.dart';
import '../features/categories/presentation/categories_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/expenses/presentation/expense_form_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/loans/presentation/loans_page.dart';
import '../features/premium/presentation/premium_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/settings/presentation/account_page.dart';
import '../features/settings/presentation/privacy_page.dart';
import '../features/settings/presentation/reminder_settings_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/app_shell.dart';
import 'app_gate.dart';
import 'routes.dart';
import 'session/user_scope.dart';

/// Bridges a stream to a [Listenable] for `GoRouter.refreshListenable`.
class StreamListenable extends ChangeNotifier {
  StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

/// Central redirect logic. Protected routes are only reachable with a
/// verified Firebase session, regardless of how the URL was entered.
String? resolveRedirect({
  required AuthState auth,
  required bool firebaseReady,
  required Uri uri,
  required String matchedLocation,
  bool splashDone = true,
  bool onboardingSeen = true,
}) {
  final loc = matchedLocation;
  if (!firebaseReady) return loc == Routes.setup ? null : Routes.setup;

  final isPublic = Routes.publicRoutes.contains(loc);
  // The animated splash stays up for a moment at launch, whatever the
  // auth state; the original destination is kept in `from`.
  final status = splashDone ? auth.status : AuthStatus.unknown;
  switch (status) {
    case AuthStatus.unknown:
      if (loc == Routes.splash) return null;
      final from = Routes.safeReturnPath(uri.toString());
      return from == null
          ? Routes.splash
          : '${Routes.splash}?from=${Uri.encodeComponent(from)}';
    case AuthStatus.unauthenticated:
      // First launch on this device: show the intro slides once.
      if (!onboardingSeen) {
        return loc == Routes.onboarding ? null : Routes.onboarding;
      }
      if (loc == Routes.onboarding) return Routes.welcome;
      if (isPublic) return null;
      final from = loc == Routes.splash
          ? Routes.safeReturnPath(uri.queryParameters['from'])
          : Routes.safeReturnPath(uri.toString());
      return from == null
          ? Routes.welcome
          : '${Routes.welcome}?from=${Uri.encodeComponent(from)}';
    case AuthStatus.unverified:
      return loc == Routes.verifyEmail ? null : Routes.verifyEmail;
    case AuthStatus.authenticated:
      if (isPublic ||
          loc == Routes.splash ||
          loc == Routes.verifyEmail ||
          loc == Routes.setup) {
        return Routes.safeReturnPath(uri.queryParameters['from']) ??
            Routes.dashboard;
      }
      return null;
  }
}

Widget _protected(Widget child) => RequireSession(builder: (_) => child);

GoRouter buildRouter({
  required AuthCubit auth,
  required bool firebaseReady,
  required Listenable refresh,
  AppGate? gate,
  String? initialLocation,
}) {
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation ?? Routes.dashboard,
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      auth: auth.state,
      firebaseReady: firebaseReady,
      uri: state.uri,
      matchedLocation: state.matchedLocation,
      splashDone: gate?.splashDone ?? true,
      onboardingSeen: gate?.onboardingSeen ?? true,
    ),
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.dashboard),
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: Routes.setup, builder: (_, _) => const FirebaseSetupPage()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingPage(),
      ),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomePage()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpPage()),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: Routes.verifyEmail,
        builder: (_, _) => const VerifyEmailPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.dashboard,
                builder: (_, _) => _protected(const DashboardPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.history,
                builder: (_, state) {
                  final category = state.uri.queryParameters['category'];
                  return _protected(
                    HistoryPage(
                      key: ValueKey('history-$category'),
                      initialCategoryId: category,
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.reports,
                builder: (_, _) => _protected(const ReportsPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.calendar,
                builder: (_, _) => _protected(const CalendarPage()),
                routes: [
                  GoRoute(
                    path: 'day/:date',
                    builder: (_, state) {
                      final date = LocalDate.tryParse(
                        state.pathParameters['date'],
                      );
                      if (date == null) return const NotFoundPage();
                      return _protected(
                        DayDetailPage(key: ValueKey(date), date: date),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.budgets,
                builder: (_, _) => _protected(const BudgetsPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.categories,
                builder: (_, _) => _protected(const CategoriesPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => _protected(const SettingsPage()),
                routes: [
                  GoRoute(
                    path: 'account',
                    builder: (_, _) => _protected(const AccountPage()),
                  ),
                  GoRoute(
                    path: 'reminders',
                    builder: (_, _) => _protected(const ReminderSettingsPage()),
                  ),
                  GoRoute(
                    path: 'premium',
                    builder: (_, _) => _protected(const PremiumPage()),
                  ),
                  GoRoute(
                    path: 'privacy',
                    builder: (_, _) => _protected(const PrivacyPage()),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.loans,
                builder: (_, _) => _protected(const LoansPage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/expense/new',
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          fullscreenDialog: true,
          child: _protected(
            ExpenseFormPage(
              initialDate: LocalDate.tryParse(
                state.uri.queryParameters['date'],
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/expense/:id',
        parentNavigatorKey: rootKey,
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          fullscreenDialog: true,
          child: _protected(
            ExpenseFormPage(expenseId: state.pathParameters['id']),
          ),
        ),
      ),
    ],
  );
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.explore_off_rounded,
        title: 'Page not found',
        message: "The page you're looking for doesn't exist.",
        action: FilledButton(
          onPressed: () => GoRouter.of(context).go(Routes.dashboard),
          child: const Text('Go to dashboard'),
        ),
      ),
    );
  }
}
