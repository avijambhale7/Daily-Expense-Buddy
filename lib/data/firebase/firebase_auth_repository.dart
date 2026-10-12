import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/repositories/repositories.dart';
import 'firebase_error_mapper.dart';

/// Email/password authentication backed by Firebase Authentication.
///
/// Session persistence is handled entirely by the Firebase SDK (secure
/// platform storage on mobile, IndexedDB on web). This class never stores
/// credentials or tokens.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  static UserProfile? _toProfile(User? user) {
    if (user == null) return null;
    return UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
      displayName: user.displayName,
      createdAt: user.metadata.creationTime,
    );
  }

  @override
  Stream<UserProfile?> userChanges() => _auth.userChanges().map(_toProfile);

  @override
  UserProfile? get currentUser => _toProfile(_auth.currentUser);

  Future<T> _guard<T>(String op, Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, st) {
      AppLogger.warn('Auth', '$op failed', e);
      if (e is! FirebaseAuthException) {
        AppLogger.error('Auth', '$op unexpected error', e, st);
      }
      throw FirebaseErrorMapper.auth(e);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard('signIn', () async {
        await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      });

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) => _guard('signUp', () async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user == null) throw AppFailure.unknown();
    await user.updateDisplayName(name.trim());
    await user.sendEmailVerification();
    await user.reload();
  });

  @override
  Future<void> signOut() => _guard('signOut', _auth.signOut);

  @override
  Future<void> sendPasswordReset(String email) => _guard(
    'passwordReset',
    () => _auth.sendPasswordResetEmail(email: email.trim()),
  );

  @override
  Future<void> sendEmailVerification() => _guard('verifyEmail', () async {
    final user = _auth.currentUser;
    if (user == null) throw _signedOut;
    await user.sendEmailVerification();
  });

  @override
  Future<UserProfile?> reloadUser() => _guard('reload', () async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    final fresh = _auth.currentUser;
    if (fresh != null && fresh.emailVerified) {
      // Refresh the ID token so the `email_verified` claim reaches the
      // Firestore security rules immediately.
      await fresh.getIdToken(true);
    }
    return _toProfile(fresh);
  });

  @override
  Future<void> updateDisplayName(String name) => _guard('updateName', () async {
    final user = _auth.currentUser;
    if (user == null) throw _signedOut;
    await user.updateDisplayName(name.trim());
    await user.reload();
  });

  @override
  Future<void> reauthenticate(String password) => _guard('reauth', () async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) throw _signedOut;
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  });

  @override
  Future<void> deleteAccount() => _guard('deleteAccount', () async {
    final user = _auth.currentUser;
    if (user == null) throw _signedOut;
    await user.delete();
  });

  static const _signedOut = AppFailure(
    FailureKind.sessionExpired,
    'Your session has expired. Please log in again.',
  );
}
