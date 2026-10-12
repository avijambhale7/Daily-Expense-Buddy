import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_logo.dart';

/// Layout for signed-out screens: a brand panel beside the form on wide
/// screens, a single scrolling column on phones.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                const Center(child: AppLogo(size: 72)),
                const SizedBox(height: Space.lg),
              ],
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: context.text.headlineMedium,
                  textAlign: wide ? TextAlign.start : TextAlign.center,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Space.sm),
                Text(
                  subtitle!,
                  style: context.text.bodyLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  textAlign: wide ? TextAlign.start : TextAlign.center,
                ),
              ],
              const SizedBox(height: Space.xxl),
              child,
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  const Expanded(child: BrandPanel()),
                  Expanded(child: form),
                ],
              )
            : form,
      ),
    );
  }
}

class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          Icon(icon, color: c.onPrimaryContainer),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              text,
              style: context.text.bodyLarge?.copyWith(
                color: c.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.all(Space.lg),
      padding: const EdgeInsets.all(Space.xxxl),
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(size: 120),
              const SizedBox(height: Space.xxl),
              const AppWordmark(fontSize: 32),
              const SizedBox(height: Space.sm),
              Text(
                'Track Today. Spend Smarter.',
                style: context.text.titleLarge?.copyWith(
                  color: c.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: Space.xxl),
              point(Icons.bolt_rounded, 'Record an expense in a few seconds'),
              point(
                Icons.insights_rounded,
                'See daily, weekly and monthly totals',
              ),
              point(
                Icons.devices_rounded,
                'Synced across your phone and the web',
              ),
              point(
                Icons.notifications_active_rounded,
                'Gentle reminders to keep the habit',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
