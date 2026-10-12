import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/models/user_profile.dart';
import '../../../domain/repositories/repositories.dart';

enum AuthStatus {
  /// Firebase has not reported the restored session yet.
  unknown,
  unauthenticated,

  /// Signed in, but the email address is not verified yet.
  unverified,
  authenticated,
}

class AuthState extends Equatable {
  const AuthState._(this.status, this.user);

  const AuthState.unknown() : this._(AuthStatus.unknown, null);
  const AuthState.unauthenticated() : this._(AuthStatus.unauthenticated, null);

  factory AuthState.fromUser(UserProfile? user) {
    if (user == null) return const AuthState.unauthenticated();
    return AuthState._(
      user.emailVerified ? AuthStatus.authenticated : AuthStatus.unverified,
      user,
    );
  }

  final AuthStatus status;
  final UserProfile? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  @override
  List<Object?> get props => [status, user];
}

/// Application-wide authentication state, derived exclusively from Firebase
/// Authentication. Nothing here can mark a user as signed in on its own.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository) : super(const AuthState.unknown()) {
    final repo = _repository;
    if (repo == null) {
      emit(const AuthState.unauthenticated());
      return;
    }
    _sub = repo.userChanges().listen(
      (user) => emit(AuthState.fromUser(user)),
      onError: (Object e) {
        AppLogger.warn('Auth', 'Auth state stream error', e);
        emit(const AuthState.unauthenticated());
      },
    );
  }

  final AuthRepository? _repository;
  StreamSubscription<UserProfile?>? _sub;

  AuthRepository get repository {
    final repo = _repository;
    if (repo == null) {
      throw const AppFailure(
        FailureKind.unavailable,
        'Firebase is not configured for this build.',
      );
    }
    return repo;
  }

  /// Reloads the user (e.g. after clicking the verification link).
  Future<void> refreshUser() async {
    final user = await repository.reloadUser();
    emit(AuthState.fromUser(user));
  }

  Future<void> signOut() => repository.signOut();

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
