import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../../data/firebase/firestore_expense_repository.dart';
import '../../data/firebase/firestore_repositories.dart';
import '../../data/firebase/firestore_user_store.dart';
import '../../data/firebase/write_tracker.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/repositories/repositories.dart';

/// Everything that belongs to one signed-in user.
///
/// A new session (with new repositories bound to the new uid) is created on
/// every sign-in and disposed on sign-out, so state from one account can
/// never leak into another.
class UserSession {
  UserSession({
    required this.user,
    required this.expenses,
    required this.categories,
    required this.budgets,
    required this.dailyStatus,
    required this.preferences,
    required this.entitlements,
    required this.userData,
    required this.syncIssues,
  });

  final UserProfile user;
  final ExpenseRepository expenses;
  final CategoryRepository categories;
  final BudgetRepository budgets;
  final DailyStatusRepository dailyStatus;
  final PreferencesRepository preferences;
  final EntitlementRepository entitlements;
  final UserDataRepository userData;
  final Stream<AppFailure> syncIssues;

  String get uid => user.uid;
}

typedef UserSessionFactory = UserSession Function(UserProfile user);

UserSessionFactory firestoreSessionFactory({
  required FirebaseFirestore db,
  required String locale,
}) {
  return (user) {
    final store = FirestoreUserStore(db, user.uid);
    final reporter = SyncIssueReporter();
    final tracker = WriteTracker(reporter);
    return UserSession(
      user: user,
      expenses: FirestoreExpenseRepository(store, tracker),
      categories: FirestoreCategoryRepository(store, tracker),
      budgets: FirestoreBudgetRepository(store, tracker),
      dailyStatus: FirestoreDailyStatusRepository(store, tracker),
      preferences: FirestorePreferencesRepository(store, tracker, locale),
      entitlements: FirestoreEntitlementRepository(store),
      userData: FirestoreUserDataRepository(store),
      syncIssues: reporter.issues,
    );
  };
}
