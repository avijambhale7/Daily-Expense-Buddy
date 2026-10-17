import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../app/routes.dart';
import '../../app/session/session_cubits.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/design_tokens.dart';

/// Whether the signed-in user has premium right now.
bool hasPremium(BuildContext context) => context
    .watch<EntitlementCubit>()
    .state
    .isPremium(context.read<AppDependencies>().now());

/// Shows [child] to premium users and an upgrade prompt to everyone else.
class PremiumGate extends StatelessWidget {
  const PremiumGate({
    super.key,
    required this.feature,
    required this.description,
    required this.icon,
    required this.child,
  });

  final String feature;
  final String description;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (hasPremium(context)) return child;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: context.colors.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 42,
                  color: context.colors.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                feature,
                textAlign: TextAlign.center,
                style: context.text.titleLarge,
              ),
              const SizedBox(height: Space.sm),
              Text(
                description,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: Space.xl),
              FilledButton.icon(
                onPressed: () => context.go(Routes.premium),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Unlock with Premium'),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Try it free for 3 days – request a trial on the Premium page.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "Premium" tag for settings rows.
class PremiumTag extends StatelessWidget {
  const PremiumTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
    decoration: BoxDecoration(
      color: context.colors.tertiaryContainer,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Text(
      'Premium',
      style: context.text.labelSmall?.copyWith(
        color: context.colors.onTertiaryContainer,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
