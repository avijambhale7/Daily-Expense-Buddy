import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/common.dart';
import '../cubit/auth_cubit.dart';
import 'auth_layout.dart';

/// Phases of handling a link from a Firebase email.
enum EmailActionPhase {
  working,
  verified,
  emailRestored,
  resetForm,
  resetDone,
  expired,
  invalid,
  failed,
  unsupported,
}

/// Opened from the link in a verification or password-reset email, inside
/// the installed Android app (App Link) or in the browser on the web.
///
/// The result shown here always comes from Firebase: the one-time code is
/// applied with Firebase Authentication and, for verification, the signed-in
/// user is reloaded before success is displayed.
class EmailActionPage extends StatefulWidget {
  const EmailActionPage({super.key, required this.mode, required this.code});

  /// `mode` query parameter: verifyEmail, resetPassword or recoverEmail.
  final String? mode;

  /// `oobCode` query parameter: the one-time code.
  final String? code;

  @override
  State<EmailActionPage> createState() => _EmailActionPageState();
}

class _EmailActionPageState extends State<EmailActionPage> {
  EmailActionPhase _phase = EmailActionPhase.working;
  String? _message;
  String? _resetEmail;
  bool _busy = false;
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final code = widget.code;
    if (code == null || code.isEmpty) {
      return _set(EmailActionPhase.invalid);
    }
    setState(() {
      _phase = EmailActionPhase.working;
      _message = null;
    });
    final auth = context.read<AuthCubit>();
    try {
      switch (widget.mode) {
        case 'verifyEmail':
          await auth.repository.applyEmailActionCode(code);
          // Confirm with Firebase (and refresh the ID token) before saying
          // it worked; this also moves the app past the verify screen.
          if (auth.state.user != null) await auth.refreshUser();
          _set(EmailActionPhase.verified);
        case 'recoverEmail':
          await auth.repository.applyEmailActionCode(code);
          _set(EmailActionPhase.emailRestored);
        case 'resetPassword':
          _resetEmail = await auth.repository.verifyPasswordResetCode(code);
          _set(EmailActionPhase.resetForm);
        default:
          _set(EmailActionPhase.unsupported);
      }
    } on AppFailure catch (f) {
      _fail(f);
    }
  }

  void _fail(AppFailure f) => _set(switch (f.kind) {
    FailureKind.expiredLink => EmailActionPhase.expired,
    FailureKind.invalidLink => EmailActionPhase.invalid,
    _ => EmailActionPhase.failed,
  }, message: f.message);

  void _set(EmailActionPhase phase, {String? message}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
      _busy = false;
    });
  }

  Future<void> _submitNewPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthCubit>().repository.confirmPasswordReset(
        code: widget.code!,
        newPassword: _password.text,
      );
      _set(EmailActionPhase.resetDone);
    } on AppFailure catch (f) {
      if (f.kind == FailureKind.weakPassword) {
        _set(EmailActionPhase.resetForm, message: f.message);
      } else {
        _fail(f);
      }
    }
  }

  void _continue() {
    final auth = context.read<AuthCubit>().state;
    context.go(switch (auth.status) {
      AuthStatus.authenticated => Routes.dashboard,
      AuthStatus.unverified => Routes.verifyEmail,
      _ => Routes.login,
    });
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_phase) {
      EmailActionPhase.working => (
        'Just a moment',
        widget.mode == 'resetPassword'
            ? 'Checking your reset link…'
            : 'Verifying your email address…',
      ),
      EmailActionPhase.verified => (
        'Email verified',
        'Thanks! Your Daily Expense Buddy account is ready.',
      ),
      EmailActionPhase.emailRestored => (
        'Email restored',
        'Your account email was changed back. Consider resetting your '
            'password too.',
      ),
      EmailActionPhase.resetForm => (
        'Choose a new password',
        _resetEmail == null ? null : 'For $_resetEmail',
      ),
      EmailActionPhase.resetDone => (
        'Password changed',
        'You can now log in with your new password.',
      ),
      EmailActionPhase.expired => (
        'This link has expired',
        widget.mode == 'resetPassword'
            ? 'Reset links are valid for a short time. Request a new one.'
            : "We couldn't verify your email because the link has expired. "
                  'Send yourself a new one from the app.',
      ),
      EmailActionPhase.invalid => (
        "This link can't be used",
        "We couldn't verify your email. The link may have expired or "
            'already been used.',
      ),
      EmailActionPhase.failed => (
        "We couldn't finish that",
        _message ?? AppFailure.network.message,
      ),
      EmailActionPhase.unsupported => (
        "This link can't be opened here",
        'Open the most recent email from Daily Expense Buddy and try again.',
      ),
    };

    return AuthLayout(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _StatusBadge(phase: _phase)),
          const SizedBox(height: Space.xl),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (_phase) {
      case EmailActionPhase.working:
        return const [];
      case EmailActionPhase.verified:
      case EmailActionPhase.emailRestored:
        return [
          FilledButton(onPressed: _continue, child: const Text('Continue')),
        ];
      case EmailActionPhase.resetDone:
        return [
          FilledButton(
            onPressed: () => context.go(Routes.login),
            child: const Text('Log in'),
          ),
        ];
      case EmailActionPhase.resetForm:
        return [
          if (_message != null) ...[
            InfoBanner(message: _message!, tone: BannerTone.error),
            const SizedBox(height: Space.lg),
          ],
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _submitNewPassword(),
              decoration: const InputDecoration(
                labelText: 'New password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              validator: Validators.newPassword,
            ),
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: _busy ? null : _submitNewPassword,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save new password'),
          ),
        ];
      case EmailActionPhase.failed:
        return [
          FilledButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
          const SizedBox(height: Space.md),
          TextButton(onPressed: _continue, child: const Text('Back to app')),
        ];
      case EmailActionPhase.expired:
      case EmailActionPhase.invalid:
      case EmailActionPhase.unsupported:
        return [
          FilledButton(
            onPressed: widget.mode == 'resetPassword'
                ? () => context.go(Routes.forgotPassword)
                : _continue,
            child: Text(
              widget.mode == 'resetPassword'
                  ? 'Request a new link'
                  : 'Back to app',
            ),
          ),
        ];
    }
  }
}

/// Envelope while working, then a check (success) or a warning (problem),
/// cross-fading between states. Finite: no endless spinner once Firebase
/// has answered.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.phase});

  final EmailActionPhase phase;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, fg, bg, label) = switch (phase) {
      EmailActionPhase.working => (
        Icons.mark_email_read_rounded,
        c.primary,
        c.primaryContainer,
        'Working',
      ),
      EmailActionPhase.verified ||
      EmailActionPhase.emailRestored ||
      EmailActionPhase.resetDone => (
        Icons.check_rounded,
        c.onPrimary,
        c.primary,
        'Success',
      ),
      EmailActionPhase.resetForm => (
        Icons.lock_reset_rounded,
        c.primary,
        c.primaryContainer,
        'Reset password',
      ),
      _ => (
        Icons.link_off_rounded,
        c.onErrorContainer,
        c.errorContainer,
        'Problem',
      ),
    };
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: label,
      liveRegion: true,
      child: SizedBox.square(
        dimension: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (phase == EmailActionPhase.working)
              const SizedBox.square(
                dimension: 112,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              transitionBuilder: (child, a) => ScaleTransition(
                scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: Container(
                key: ValueKey(icon),
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, size: 44, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
