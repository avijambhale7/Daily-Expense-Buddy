import '../../core/errors/app_failure.dart';
import '../../domain/repositories/repositories.dart';
import '../../services/notifications/notification_service.dart';

enum DeletionResult {
  /// All data and the login account were deleted.
  completed,

  /// Some data could not be deleted; the account was NOT deleted.
  dataIncomplete,

  /// Data was deleted but the login account could not be removed.
  accountNotDeleted,
}

class DeletionOutcome {
  const DeletionOutcome(this.result, {this.detail});
  final DeletionResult result;
  final String? detail;
}

/// Deletes the user's account in a safe order:
///
/// 1. Check the server is reachable (deletion must not be queued offline).
/// 2. Re-authenticate with the password (Firebase requires a recent login).
/// 3. Delete every document under `users/{uid}`.
/// 4. Only if step 3 fully succeeded, delete the Firebase Auth account.
///
/// Every partial failure is reported honestly; nothing is claimed deleted
/// unless it was.
class AccountDeletionService {
  AccountDeletionService({
    required this.auth,
    required this.userData,
    required this.notifications,
  });

  final AuthRepository auth;
  final UserDataRepository userData;
  final NotificationService notifications;

  Future<DeletionOutcome> delete(
    String password, {
    void Function(String step)? onProgress,
  }) async {
    onProgress?.call('Checking connection');
    await userData.checkServerReachable();
    onProgress?.call('Confirming your password');
    await auth.reauthenticate(password);

    final report = await userData.deleteAllUserData(onProgress: onProgress);
    if (!report.isComplete) {
      return DeletionOutcome(
        DeletionResult.dataIncomplete,
        detail:
            'Some data could not be deleted (${report.failed.join(', ')}). '
            'Your account was not deleted. Please try again.',
      );
    }

    await notifications.cancelAllReminders();
    onProgress?.call('Deleting your login');
    try {
      await auth.deleteAccount();
    } on AppFailure catch (f) {
      return DeletionOutcome(
        DeletionResult.accountNotDeleted,
        detail:
            'Your expense data was deleted, but the login account could not '
            'be removed: ${f.message}',
      );
    }
    return const DeletionOutcome(DeletionResult.completed);
  }
}
