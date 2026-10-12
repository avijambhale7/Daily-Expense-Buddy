import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';

/// Premium status. Purchases are not available in this build: entitlements
/// are granted only by a trusted backend writing
/// `users/{uid}/entitlements/premium`. Nothing here simulates a purchase.
class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await context.read<EntitlementCubit>().refresh();
      if (mounted) showMessage(context, 'Premium status refreshed');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = context.watch<EntitlementCubit>().state;
    final now = context.read<AppDependencies>().now();
    final active = e.isPremium(now);
    final fmt = AppFormat.of(context);

    Widget feature(String text, {required bool free}) => ListTile(
      leading: Icon(
        free ? Icons.check_circle_rounded : Icons.workspace_premium_rounded,
        color: free ? context.appColors.success : context.colors.tertiary,
      ),
      title: Text(text),
      trailing: Text(
        free ? 'Free' : 'Premium',
        style: context.text.labelMedium,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: context.colors.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          size: 40,
                          color: context.colors.onTertiaryContainer,
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          active
                              ? 'Premium is active'
                              : 'You are on the free plan',
                          style: context.text.titleLarge?.copyWith(
                            color: context.colors.onTertiaryContainer,
                          ),
                        ),
                        if (active && e.expiresAt != null)
                          Text(
                            'Renews or expires on ${fmt.dateTime(e.expiresAt!)}',
                            style: context.text.bodyMedium?.copyWith(
                              color: context.colors.onTertiaryContainer,
                            ),
                          ),
                        if (e.developerPreview)
                          Text(
                            'Developer preview (debug build only).',
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onTertiaryContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                Card(
                  child: Column(
                    children: [
                      feature(
                        'Unlimited expense tracking & history',
                        free: true,
                      ),
                      feature(
                        'Daily, weekly, monthly & yearly reports',
                        free: true,
                      ),
                      feature('Reminders, calendar and budgets', free: true),
                      feature('Light, Dark and System themes', free: true),
                      feature('CSV export', free: true),
                      feature(
                        'Ocean, Forest, Sunset, Lavender & Midnight themes',
                        free: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                if (!active)
                  const InfoBanner(
                    message:
                        'Purchases are not available in this version yet. When they '
                        'launch, premium will be verified on our servers and linked to '
                        'your account on every device.',
                  ),
                const SizedBox(height: Space.lg),
                OutlinedButton.icon(
                  onPressed: _refreshing ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Restore / refresh premium status'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
