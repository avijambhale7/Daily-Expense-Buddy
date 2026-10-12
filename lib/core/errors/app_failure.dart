enum FailureKind {
  network,
  invalidCredentials,
  emailInUse,
  weakPassword,
  invalidEmail,
  tooManyRequests,
  sessionExpired,
  requiresRecentLogin,
  permissionDenied,
  conflict,
  notFound,
  unavailable,
  unknown,
}

/// A user-presentable failure. [message] is safe to show in the UI: it never
/// contains passwords, tokens, raw stack traces or other users' data.
class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, {this.cause});

  final FailureKind kind;
  final String message;

  /// Original error, for logging only.
  final Object? cause;

  static const network = AppFailure(
    FailureKind.network,
    'Please check your internet connection and try again.',
  );

  static AppFailure unknown([Object? cause]) => AppFailure(
    FailureKind.unknown,
    'Something went wrong. Please try again.',
    cause: cause,
  );

  @override
  String toString() => 'AppFailure($kind, $message)';
}
