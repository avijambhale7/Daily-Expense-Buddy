import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/app_failure.dart';

abstract final class FirebaseErrorMapper {
  static AppFailure auth(Object error) {
    if (error is AppFailure) return error;
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
        case 'INVALID_LOGIN_CREDENTIALS':
          return AppFailure(
            FailureKind.invalidCredentials,
            'Invalid email or password.',
            cause: error,
          );
        case 'email-already-in-use':
          return AppFailure(
            FailureKind.emailInUse,
            'This email is already registered. Try logging in instead.',
            cause: error,
          );
        case 'weak-password':
          return AppFailure(
            FailureKind.weakPassword,
            'Please choose a stronger password.',
            cause: error,
          );
        case 'invalid-email':
          return AppFailure(
            FailureKind.invalidEmail,
            'Please enter a valid email address.',
            cause: error,
          );
        case 'network-request-failed':
          return AppFailure(
            FailureKind.network,
            AppFailure.network.message,
            cause: error,
          );
        case 'too-many-requests':
          return AppFailure(
            FailureKind.tooManyRequests,
            'Too many attempts. Please wait a moment and try again.',
            cause: error,
          );
        case 'user-disabled':
          return AppFailure(
            FailureKind.permissionDenied,
            'This account has been disabled.',
            cause: error,
          );
        case 'user-token-expired':
        case 'invalid-user-token':
          return AppFailure(
            FailureKind.sessionExpired,
            'Your session has expired. Please log in again.',
            cause: error,
          );
        case 'requires-recent-login':
          return AppFailure(
            FailureKind.requiresRecentLogin,
            'For your security, please confirm your password and try again.',
            cause: error,
          );
        case 'operation-not-allowed':
          return AppFailure(
            FailureKind.unavailable,
            'Email/password sign-in is not enabled for this app yet.',
            cause: error,
          );
      }
    }
    return firestore(error);
  }

  static AppFailure firestore(Object error, {bool isUpdate = false}) {
    if (error is AppFailure) return error;
    if (error is TimeoutException) return AppFailure.network;
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return isUpdate
              ? AppFailure(
                  FailureKind.conflict,
                  'This item was changed or deleted on another device. '
                  'Your edit was not saved – please review the latest version.',
                  cause: error,
                )
              : AppFailure(
                  FailureKind.permissionDenied,
                  "You don't have permission to do that. "
                  'Please verify your email or log in again.',
                  cause: error,
                );
        case 'unavailable':
        case 'deadline-exceeded':
          return AppFailure(
            FailureKind.network,
            AppFailure.network.message,
            cause: error,
          );
        case 'not-found':
          return AppFailure(
            FailureKind.notFound,
            'This item no longer exists.',
            cause: error,
          );
        case 'unauthenticated':
          return AppFailure(
            FailureKind.sessionExpired,
            'Your session has expired. Please log in again.',
            cause: error,
          );
        case 'resource-exhausted':
          return AppFailure(
            FailureKind.unavailable,
            'The service is busy. Please try again shortly.',
            cause: error,
          );
        case 'failed-precondition':
          return AppFailure(
            FailureKind.unavailable,
            'This view needs a database index that has not been deployed yet.',
            cause: error,
          );
      }
    }
    return AppFailure.unknown(error);
  }
}
