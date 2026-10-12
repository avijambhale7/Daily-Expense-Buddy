import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/common.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_form_cubit.dart';
import 'auth_layout.dart';

String _withFrom(BuildContext context, String route) {
  final from = GoRouterState.of(context).uri.queryParameters['from'];
  return from == null ? route : '$route?from=${Uri.encodeComponent(from)}';
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.busy,
    this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

class _FormMessage extends StatelessWidget {
  const _FormMessage(this.state);

  final AuthFormState state;

  @override
  Widget build(BuildContext context) {
    final msg = state.message;
    if (msg == null) return const SizedBox.shrink();
    final failure = state.status == FormStatus.failure;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Semantics(
        liveRegion: true,
        child: InfoBanner(
          message: msg,
          tone: failure ? BannerTone.error : BannerTone.success,
          icon: failure
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: () => context.go(_withFrom(context, Routes.signUp)),
          child: const Text('Create a free account'),
        ),
        const SizedBox(height: Space.md),
        OutlinedButton(
          onPressed: () => context.go(_withFrom(context, Routes.login)),
          child: const Text('Log in'),
        ),
      ],
    );
    if (wide) {
      return AuthLayout(
        title: 'Welcome',
        subtitle: 'A simple, private way to track what you spend every day.',
        child: actions,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 140)),
                  const SizedBox(height: Space.xl),
                  const AppWordmark(fontSize: 30, textAlign: TextAlign.center),
                  const SizedBox(height: Space.sm),
                  Text(
                    'Track Today. Spend Smarter.',
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: Space.xxxl),
                  actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthCubit>().repository),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    unawaited(
      context.read<AuthFormCubit>().signIn(_email.text, _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthFormCubit>().state;
    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Log in to continue tracking your expenses.',
      showBack: true,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FormMessage(state),
              TextFormField(
                key: const Key('login-email'),
                controller: _email,
                enabled: !state.isSubmitting,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: Validators.email,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                key: const Key('login-password'),
                controller: _password,
                enabled: !state.isSubmitting,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: Validators.existingPassword,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go(Routes.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: Space.sm),
              _SubmitButton(
                label: 'Log in',
                busy: state.isSubmitting,
                onPressed: _submit,
              ),
              const SizedBox(height: Space.lg),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    "Don't have an account?",
                    style: context.text.bodyMedium,
                  ),
                  TextButton(
                    onPressed: () =>
                        context.go(_withFrom(context, Routes.signUp)),
                    child: const Text('Sign up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class SignUpPage extends StatelessWidget {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthCubit>().repository),
      child: const _SignUpView(),
    );
  }
}

class _SignUpView extends StatefulWidget {
  const _SignUpView();

  @override
  State<_SignUpView> createState() => _SignUpViewState();
}

class _SignUpViewState extends State<_SignUpView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    unawaited(
      context.read<AuthFormCubit>().signUp(
        _name.text,
        _email.text,
        _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthFormCubit>().state;
    return AuthLayout(
      title: 'Create your account',
      subtitle: "It's free. We'll send a link to verify your email.",
      showBack: true,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FormMessage(state),
              TextFormField(
                key: const Key('signup-name'),
                controller: _name,
                enabled: !state.isSubmitting,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: Validators.name,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                key: const Key('signup-email'),
                controller: _email,
                enabled: !state.isSubmitting,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: Validators.email,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                key: const Key('signup-password'),
                controller: _password,
                enabled: !state.isSubmitting,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText:
                      'At least 8 characters, with a letter and a number',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: Validators.newPassword,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                key: const Key('signup-confirm'),
                controller: _confirm,
                enabled: !state.isSubmitting,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (v) => Validators.confirmPassword(v, _password.text),
              ),
              const SizedBox(height: Space.xl),
              _SubmitButton(
                label: 'Create account',
                busy: state.isSubmitting,
                onPressed: _submit,
              ),
              const SizedBox(height: Space.lg),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: context.text.bodyMedium,
                  ),
                  TextButton(
                    onPressed: () =>
                        context.go(_withFrom(context, Routes.login)),
                    child: const Text('Log in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthCubit>().repository),
      child: const _ForgotView(),
    );
  }
}

class _ForgotView extends StatefulWidget {
  const _ForgotView();

  @override
  State<_ForgotView> createState() => _ForgotViewState();
}

class _ForgotViewState extends State<_ForgotView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    unawaited(
      context.read<AuthFormCubit>().sendPasswordReset(_email.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthFormCubit>().state;
    return AuthLayout(
      title: 'Reset your password',
      subtitle: "Enter your account's email and we'll send you a reset link.",
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FormMessage(state),
            TextFormField(
              controller: _email,
              enabled: !state.isSubmitting,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: Validators.email,
            ),
            const SizedBox(height: Space.xl),
            _SubmitButton(
              label: 'Send reset link',
              busy: state.isSubmitting,
              onPressed: _submit,
            ),
            const SizedBox(height: Space.md),
            TextButton(
              onPressed: () => context.go(Routes.login),
              child: const Text('Back to log in'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class VerifyEmailPage extends StatelessWidget {
  const VerifyEmailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthCubit>().repository),
      child: const _VerifyView(),
    );
  }
}

class _VerifyView extends StatefulWidget {
  const _VerifyView();

  @override
  State<_VerifyView> createState() => _VerifyViewState();
}

class _VerifyViewState extends State<_VerifyView> {
  static const _cooldownSeconds = 60;
  int _cooldown = 0;
  Timer? _timer;
  bool _checking = false;
  String? _checkMessage;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    final ok = await context.read<AuthFormCubit>().resendVerification();
    if (!ok || !mounted) return;
    setState(() => _cooldown = _cooldownSeconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _checkMessage = null;
    });
    try {
      await context.read<AuthCubit>().refreshUser();
      if (!mounted) return;
      if (!context.read<AuthCubit>().state.isAuthenticated) {
        setState(
          () => _checkMessage =
              "We couldn't confirm your verification yet. Open the link in "
              'the email, then try again.',
        );
      }
    } on AppFailure catch (f) {
      if (mounted) setState(() => _checkMessage = f.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthFormCubit>().state;
    final email = context.select((AuthCubit c) => c.state.user?.email) ?? '';
    return AuthLayout(
      title: 'Verify your email',
      subtitle:
          'We sent a verification link to $email. Verifying keeps your '
          'financial data protected.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormMessage(state),
          if (_checkMessage != null) ...[
            InfoBanner(message: _checkMessage!, tone: BannerTone.warning),
            const SizedBox(height: Space.lg),
          ],
          _SubmitButton(
            label: "I've verified my email",
            busy: _checking,
            onPressed: _check,
          ),
          const SizedBox(height: Space.md),
          OutlinedButton(
            onPressed: state.isSubmitting || _cooldown > 0 ? null : _resend,
            child: Text(
              _cooldown > 0
                  ? 'Resend email in ${_cooldown}s'
                  : 'Resend verification email',
            ),
          ),
          const SizedBox(height: Space.md),
          TextButton(
            onPressed: () => context.read<AuthCubit>().signOut(),
            child: const Text('Use a different account'),
          ),
          const SizedBox(height: Space.lg),
          Text(
            "Can't find it? Check your spam folder.",
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
