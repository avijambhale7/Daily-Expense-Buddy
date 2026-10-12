import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/app_failure.dart';
import '../../../domain/repositories/repositories.dart';

enum FormStatus { idle, submitting, success, failure }

class AuthFormState extends Equatable {
  const AuthFormState({this.status = FormStatus.idle, this.message});

  final FormStatus status;

  /// Error message (failure) or confirmation (success).
  final String? message;

  bool get isSubmitting => status == FormStatus.submitting;

  @override
  List<Object?> get props => [status, message];
}

/// Submission state for the login, sign-up, password-reset and
/// verification screens. Rejects re-entrant submissions.
class AuthFormCubit extends Cubit<AuthFormState> {
  AuthFormCubit(this._repository) : super(const AuthFormState());

  final AuthRepository _repository;

  Future<bool> _run(Future<void> Function() action, {String? success}) async {
    if (state.isSubmitting) return false;
    emit(const AuthFormState(status: FormStatus.submitting));
    try {
      await action();
      if (isClosed) return true;
      emit(AuthFormState(status: FormStatus.success, message: success));
      return true;
    } on AppFailure catch (f) {
      if (!isClosed) {
        emit(AuthFormState(status: FormStatus.failure, message: f.message));
      }
    } catch (e) {
      if (!isClosed) {
        emit(
          AuthFormState(
            status: FormStatus.failure,
            message: AppFailure.unknown(e).message,
          ),
        );
      }
    }
    return false;
  }

  Future<bool> signIn(String email, String password) =>
      _run(() => _repository.signIn(email: email, password: password));

  Future<bool> signUp(String name, String email, String password) => _run(
    () => _repository.signUp(name: name, email: email, password: password),
  );

  /// Shows the same confirmation whether or not an account exists, so the
  /// form cannot be used to discover registered emails.
  Future<bool> sendPasswordReset(String email) => _run(
    () async {
      try {
        await _repository.sendPasswordReset(email);
      } on AppFailure catch (f) {
        if (f.kind != FailureKind.invalidCredentials) rethrow;
      }
    },
    success:
        'If an account exists for $email, a password reset email has been sent.',
  );

  Future<bool> resendVerification() => _run(
    _repository.sendEmailVerification,
    success: 'Verification email sent. Please check your inbox.',
  );

  void clearMessage() => emit(const AuthFormState());
}
