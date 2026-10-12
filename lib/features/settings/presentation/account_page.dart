import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/common.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../account_deletion.dart';
import 'settings_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final _name = TextEditingController(
    text: context.read<AuthCubit>().state.user?.displayName ?? '',
  );
  bool _savingName = false;
  bool _sendingReset = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final error = Validators.name(_name.text);
    if (error != null) return showMessage(context, error);
    setState(() => _savingName = true);
    final auth = context.read<AuthCubit>();
    final session = SessionScope.of(context);
    try {
      await auth.repository.updateDisplayName(_name.text);
      await auth.refreshUser();
      final user = auth.state.user;
      if (user != null) await session.userData.ensureProfile(user);
      if (mounted) showMessage(context, 'Name updated');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _sendReset(String email) async {
    setState(() => _sendingReset = true);
    try {
      await context.read<AuthCubit>().repository.sendPasswordReset(email);
      if (mounted) showMessage(context, 'Password reset email sent to $email');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthCubit c) => c.state.user);
    return Scaffold(
      appBar: AppBar(title: const Text('Account & security')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  title: 'Profile',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        enabled: !_savingName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: Space.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: _savingName ? null : _saveName,
                          child: const Text('Save name'),
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mail_outline_rounded),
                        title: Text(user?.email ?? ''),
                        subtitle: Text(
                          user?.emailVerified == true
                              ? 'Verified email'
                              : 'Not verified',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                SectionCard(
                  title: 'Security',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "We'll email you a secure link to set a new password.",
                        style: context.text.bodyMedium,
                      ),
                      const SizedBox(height: Space.md),
                      OutlinedButton.icon(
                        onPressed: _sendingReset || user == null
                            ? null
                            : () => _sendReset(user.email),
                        icon: const Icon(Icons.lock_reset_rounded),
                        label: const Text('Send password reset email'),
                      ),
                      const SizedBox(height: Space.sm),
                      OutlinedButton.icon(
                        onPressed: () => confirmAndSignOut(context),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Log out'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.lg),
                    side: BorderSide(
                      color: context.colors.error.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Delete account',
                          style: context.text.titleMedium?.copyWith(
                            color: context.colors.error,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          'Permanently deletes your login and all of your expenses, '
                          'categories, budgets, reminders settings and daily statuses '
                          'from our servers. Export your data first if you want a copy.',
                          style: context.text.bodyMedium,
                        ),
                        const SizedBox(height: Space.md),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.error,
                            foregroundColor: context.colors.onError,
                          ),
                          onPressed: () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const _DeleteAccountDialog(),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Delete my account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _progress;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      _password.text.isNotEmpty &&
      _confirm.text.trim().toUpperCase() == 'DELETE';

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final service = AccountDeletionService(
      auth: context.read<AuthCubit>().repository,
      userData: SessionScope.of(context).userData,
      notifications: context.read<AppDependencies>().notifications,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await service.delete(
        _password.text,
        onProgress: (step) {
          if (mounted) setState(() => _progress = step);
        },
      );
      switch (outcome.result) {
        case DeletionResult.completed:
          navigator.pop();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Your account and all of your data were deleted.'),
            ),
          );
        case DeletionResult.dataIncomplete:
        case DeletionResult.accountNotDeleted:
          if (mounted) {
            setState(() {
              _busy = false;
              _progress = null;
              _error = outcome.detail;
            });
          }
      }
    } on AppFailure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _error = f.kind == FailureKind.invalidCredentials
              ? 'Incorrect password.'
              : f.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: context.colors.error),
      title: const Text('Delete your account?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This cannot be undone. Your data will be removed from every device. '
              'An internet connection is required.',
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
              ),
            ),
            if (_progress != null) ...[
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text(_progress!)),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.md),
              InfoBanner(message: _error!, tone: BannerTone.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.error,
            foregroundColor: context.colors.onError,
          ),
          onPressed: _canSubmit ? _delete : null,
          child: const Text('Delete permanently'),
        ),
      ],
    );
  }
}
