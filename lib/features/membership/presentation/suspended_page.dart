import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../membership_cubit.dart';

/// Shown instead of the app while an admin has banned this account. The
/// security rules block the account's data at the same time.
class SuspendedPage extends StatelessWidget {
  const SuspendedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ban = context.watch<MembershipCubit>().state.ban;
    final reason = ban?.reason;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: context.colors.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.block_rounded,
                        size: 44,
                        color: context.colors.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  Text(
                    'Account suspended',
                    textAlign: TextAlign.center,
                    style: context.text.headlineSmall,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    'Your Daily Expense Buddy account has been suspended by an '
                    'administrator, so your data cannot be opened right now.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium,
                  ),
                  if (reason != null && reason.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    InfoBanner(
                      tone: BannerTone.warning,
                      message: 'Reason: $reason',
                    ),
                  ],
                  const SizedBox(height: Space.lg),
                  Text(
                    'If you think this is a mistake, contact support.',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: Space.xl),
                  FilledButton.tonalIcon(
                    onPressed: () => context.read<AuthCubit>().signOut(),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
