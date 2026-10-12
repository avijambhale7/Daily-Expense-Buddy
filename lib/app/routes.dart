import '../core/dates/local_date.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const setup = '/setup';
  static const welcome = '/welcome';
  static const login = '/login';
  static const signUp = '/signup';
  static const forgotPassword = '/forgot-password';
  static const verifyEmail = '/verify-email';

  static const dashboard = '/dashboard';
  static const history = '/history';
  static const reports = '/reports';
  static const calendar = '/calendar';
  static const budgets = '/budgets';
  static const categories = '/categories';
  static const settings = '/settings';
  static const account = '/settings/account';
  static const reminders = '/settings/reminders';
  static const premium = '/settings/premium';
  static const privacy = '/settings/privacy';

  static const publicRoutes = {welcome, login, signUp, forgotPassword};

  static String historyForCategory(String categoryId) =>
      '$history?category=${Uri.encodeComponent(categoryId)}';

  static String day(LocalDate date) => '/calendar/day/${date.toIso()}';

  static String newExpense({LocalDate? date}) =>
      date == null ? '/expense/new' : '/expense/new?date=${date.toIso()}';

  static String editExpense(String id) => '/expense/${Uri.encodeComponent(id)}';

  /// Accepts only in-app paths for post-login redirects (prevents open
  /// redirects to other sites).
  static String? safeReturnPath(String? from) {
    if (from == null || from.isEmpty) return null;
    if (!from.startsWith('/') || from.startsWith('//')) return null;
    if (from.contains('://') || from.contains(r'\')) return null;
    final path = Uri.tryParse(from)?.path;
    if (path == null ||
        publicRoutes.contains(path) ||
        path == splash ||
        path == verifyEmail ||
        path == setup) {
      return null;
    }
    return from;
  }
}
