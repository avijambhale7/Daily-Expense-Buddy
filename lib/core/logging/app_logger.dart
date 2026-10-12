import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Minimal structured logger.
///
/// Rules: never log passwords, tokens, email addresses, amounts, notes or
/// any other personal/financial data. Log error *codes* and component names.
abstract final class AppLogger {
  static void info(String component, String message) {
    if (kReleaseMode) return;
    developer.log(message, name: 'DEB/$component');
  }

  static void warn(String component, String message, [Object? error]) {
    developer.log(
      message,
      name: 'DEB/$component',
      level: 900,
      error: error == null ? null : _describe(error),
    );
  }

  static void error(
    String component,
    String message,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    developer.log(
      message,
      name: 'DEB/$component',
      level: 1000,
      error: _describe(error),
      stackTrace: kReleaseMode ? null : stackTrace,
    );
  }

  /// Reduces an error to its type (and code where available) so that
  /// messages that might embed user data are not written to logs.
  static String _describe(Object error) {
    final type = error.runtimeType.toString();
    try {
      final dynamic e = error;
      final Object? code = e.code;
      if (code != null) return '$type(code: $code)';
    } catch (_) {
      // Not all errors expose a code.
    }
    return type;
  }
}
