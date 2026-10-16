import 'package:material_ui/material_ui.dart';

import '../../domain/models/daily_status.dart';
import '../../domain/models/expense_category.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/category_visuals.dart';
import '../theme/design_tokens.dart';

/// Card with an optional title row; the standard dashboard building block.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(title!, style: context.text.titleMedium),
                        ),
                        if (subtitle != null)
                          Text(subtitle!, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: Space.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: label,
        child: const Padding(
          padding: EdgeInsets.all(Space.xxl),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? Space.lg : Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 24 : 32,
                color: context.colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              title,
              style: compact
                  ? context.text.titleSmall
                  : context.text.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: Space.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  message!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: Space.lg), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: context.colors.error,
            ),
            const SizedBox(height: Space.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Space.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline banner for informational / warning messages.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = BannerTone.info,
    this.action,
  });

  final String message;
  final IconData icon;
  final BannerTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = context.appColors;
    final (bg, fg) = switch (tone) {
      BannerTone.info => (c.secondaryContainer, c.onSecondaryContainer),
      BannerTone.warning => (a.warningContainer, c.onSurface),
      BannerTone.success => (a.successContainer, c.onSurface),
      BannerTone.error => (c.errorContainer, c.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: IconSizes.md),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              message,
              style: context.text.bodyMedium?.copyWith(color: fg),
            ),
          ),
          if (action != null) ...[const SizedBox(width: Space.sm), action!],
        ],
      ),
    );
  }
}

enum BannerTone { info, warning, success, error }

/// Circular category icon in the category's themed colour.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 40});

  final ExpenseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = category.color(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(category.icon, color: color, size: size * 0.5),
      ),
    );
  }
}

/// Day tracking status with icon + label (never colour alone).
class TrackingStatusChip extends StatelessWidget {
  const TrackingStatusChip({
    super.key,
    required this.state,
    this.dense = false,
  });

  final DailyTrackingState state;
  final bool dense;

  static IconData iconFor(DailyTrackingState s) => switch (s) {
    DailyTrackingState.completedWithExpenses => Icons.check_circle_rounded,
    DailyTrackingState.confirmedNoExpenses => Icons.do_not_disturb_on_rounded,
    DailyTrackingState.notReviewed => Icons.pending_rounded,
  };

  static Color colorFor(BuildContext context, DailyTrackingState s) =>
      switch (s) {
        DailyTrackingState.completedWithExpenses =>
          context.appColors.statusComplete,
        DailyTrackingState.confirmedNoExpenses =>
          context.appColors.statusNoExpenses,
        DailyTrackingState.notReviewed => context.appColors.statusIncomplete,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(context, state);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Space.sm : Space.md,
        vertical: dense ? 2 : Space.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(state), size: dense ? 14 : 16, color: color),
          const SizedBox(width: Space.xs),
          Text(
            state.label,
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and slides a list item in, staggered by [index].
class AppearIn extends StatelessWidget {
  const AppearIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + 60 * index.clamp(0, 6)),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - v)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Icon in a soft tinted circle, used to give cards a friendly accent.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.size = 32, this.color});

  final IconData icon;
  final double size;

  /// Accent colour; defaults to the theme's primary colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.colors.primary;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size * 0.56, color: accent),
      ),
    );
  }
}

/// Large amount + label summary tile.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.emphasize = false,
    this.action,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final bool emphasize;

  /// Optional control at the end of the header row (e.g. a period picker).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    IconBadge(icon: icon!),
                    const SizedBox(width: Space.sm),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: context.text.labelLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ?action,
                ],
              ),
              const SizedBox(height: Space.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style:
                      (emphasize
                              ? context.text.headlineMedium
                              : context.text.titleLarge)!
                          .tabular,
                  maxLines: 1,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: Space.xs),
                Text(
                  caption!,
                  style: context.text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Centers [child] with a max width and responsive horizontal padding.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

EdgeInsets pagePadding(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final h = w >= Breakpoints.expanded
      ? Space.xxxl
      : (w >= Breakpoints.medium ? Space.xxl : Space.lg);
  // The phone navigation bar is translucent and drawn over the content, so
  // its height (reported as bottom padding) is added to keep the last item
  // reachable.
  final bottom = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(h, Space.sm, h, Space.xxxl + 56 + bottom);
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: context.colors.error,
                  foregroundColor: context.colors.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
