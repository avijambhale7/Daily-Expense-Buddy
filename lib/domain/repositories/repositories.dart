import '../../core/dates/local_date.dart';
import '../models/budget.dart';
import '../models/daily_status.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/expense_filter.dart';
import '../models/loan.dart';
import '../models/premium_entitlement.dart';
import '../models/user_preferences.dart';
import '../models/user_profile.dart';

/// Firebase Authentication facade. Implementations must never persist
/// passwords or tokens themselves.
abstract interface class AuthRepository {
  /// Emits on sign-in, sign-out and profile changes (including email
  /// verification after [reloadUser]).
  Stream<UserProfile?> userChanges();
  UserProfile? get currentUser;

  Future<void> signIn({required String email, required String password});
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  });
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> sendEmailVerification();

  /// Reloads the user and refreshes the ID token so new claims (e.g.
  /// `email_verified`) reach the security rules.
  Future<UserProfile?> reloadUser();
  Future<void> updateDisplayName(String name);
  Future<void> reauthenticate(String password);

  /// Deletes the Firebase Authentication account (requires recent login).
  Future<void> deleteAccount();
}

/// Result of a write. Firestore applies writes locally first; when the
/// server has not acknowledged within a short time the change is reported as
/// pending and will sync automatically once online.
enum SaveOutcome { synced, pendingSync }

class ExpensePage {
  const ExpensePage(this.items, {required this.hasMore});
  final List<Expense> items;
  final bool hasMore;
}

abstract interface class ExpenseRepository {
  /// Generates a new stable id. The form keeps this id across retries so a
  /// repeated submission writes the same document instead of a duplicate.
  String newId();

  /// Live expenses with `date` inside [range] (inclusive).
  Stream<List<Expense>> watchRange(DateRange range);

  /// Live, filtered history limited to [limit] newest (or oldest) items.
  Stream<ExpensePage> watchHistory(ExpenseFilter filter, {required int limit});

  Stream<Expense?> watchExpense(String id);

  /// One-off fetch for exports (bounded by [filter.range]).
  Future<List<Expense>> fetch(ExpenseFilter filter);

  Future<SaveOutcome> create(Expense expense);

  /// [expense.version] must be the version that was loaded; the stored
  /// version becomes `version + 1`.
  Future<SaveOutcome> update(Expense expense);
  Future<SaveOutcome> delete(String id);

  Future<bool> isCategoryUsed(String categoryId);
}

abstract interface class CategoryRepository {
  /// Built-in categories merged with overrides and custom categories.
  Stream<List<ExpenseCategory>> watchAll();
  String newId();
  Future<SaveOutcome> save(ExpenseCategory category);

  /// Deletes a custom category. Callers must check it is unused.
  Future<SaveOutcome> delete(String id);
}

abstract interface class BudgetRepository {
  Stream<List<Budget>> watchAll();
  Future<SaveOutcome> save(Budget budget);
  Future<SaveOutcome> delete(String id);

  /// Atomically records that [threshold] was notified for [budgetId] in
  /// [monthKey]. Returns true only for the caller that recorded it first, so
  /// an alert is not repeated across devices. Requires connectivity.
  Future<bool> claimAlert({
    required String monthKey,
    required String budgetId,
    required int threshold,
  });
}

abstract interface class LoanRepository {
  String newId();

  /// All loans, newest first.
  Stream<List<Loan>> watchAll();
  Future<SaveOutcome> create(Loan loan);
  Future<SaveOutcome> update(Loan loan);
  Future<SaveOutcome> delete(String id);
}

abstract interface class DailyStatusRepository {
  Stream<Map<LocalDate, StoredDayStatus>> watchRange(DateRange range);
  Future<SaveOutcome> setStatus(LocalDate date, StoredDayStatus status);
  Future<SaveOutcome> clearStatus(LocalDate date);
}

abstract interface class PreferencesRepository {
  Stream<UserPreferences> watch();
  Future<SaveOutcome> save(UserPreferences preferences);

  /// Writes default preferences if none exist yet.
  Future<void> ensureInitialized();
}

abstract interface class EntitlementRepository {
  Stream<PremiumEntitlement> watch();

  /// Re-reads the entitlement from the server ("restore purchases").
  Future<PremiumEntitlement> refresh();
}

class DeletionReport {
  const DeletionReport({required this.deletedDocuments, required this.failed});
  final int deletedDocuments;
  final List<String> failed;
  bool get isComplete => failed.isEmpty;
}

/// Deletes all of the user's Firestore data.
abstract interface class UserDataRepository {
  Future<void> ensureProfile(UserProfile profile);
  Future<DeletionReport> deleteAllUserData({
    void Function(String step)? onProgress,
  });

  /// Throws [AppFailure] with [FailureKind.network] when the server cannot
  /// be reached.
  Future<void> checkServerReachable();
}
