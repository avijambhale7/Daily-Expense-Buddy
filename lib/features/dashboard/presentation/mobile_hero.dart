import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../domain/models/daily_status.dart';
import '../../../domain/models/report_summary.dart';
import '../../calendar/day_status_actions.dart';
import '../../expenses/presentation/expense_editor.dart';

/// Colourful full-width header for the phone home screen: greeting, a large
/// progress ring for today, and the week / month totals.
class MobileHero extends StatelessWidget {
  const MobileHero({
    super.key,
    required this.summary,
    required this.format,
    required this.greeting,
    required this.dateLabel,
    required this.initials,
  });

  final DashboardSummary summary;
  final AppFormat format;
  final String greeting;
  final String dateLabel;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final c = context.colors;
    final dark = c.brightness == Brightness.dark;
    final top = dark ? c.primaryContainer : c.primary;
    final bottom = Color.lerp(top, Colors.black, dark ? 0.35 : 0.28)!;
    final onHero = dark ? c.onPrimaryContainer : Colors.white;
    final muted = onHero.withValues(alpha: 0.75);

    final allowance = s.dailyAllowanceMinor;
    final double ringValue;
    final String ringLabel;
    final String ringSemantics;
    if (allowance != null) {
      ringValue = allowance == 0
          ? (s.todayTotalMinor > 0 ? 1.01 : 0)
          : s.todayTotalMinor / allowance;
      final left = allowance - s.todayTotalMinor;
      ringLabel = left >= 0
          ? '${format.amount(left)} left today'
          : '${format.amount(-left)} over budget';
      ringSemantics =
          'Spent ${format.amount(s.todayTotalMinor)} today. $ringLabel.';
    } else {
      final total = s.weekElapsedDays == 0 ? 1 : s.weekElapsedDays;
      ringValue = s.weekReviewedDays / total;
      ringLabel = '${s.weekReviewedDays}/$total days tracked';
      ringSemantics =
          'Spent ${format.amount(s.todayTotalMinor)} today. $ringLabel this week.';
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons over the coloured header in both themes.
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [top, bottom],
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(Radii.xl + 8),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Soft colourful glows behind the header content (iOS-style
            // mesh gradient).
            const Positioned(
              top: -60,
              right: -40,
              child: _Glow(color: Color(0xFF22D3EE), size: 220),
            ),
            const Positioned(
              bottom: -70,
              left: -50,
              child: _Glow(color: Color(0xFFF472B6), size: 240),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xl,
                  Space.md,
                  Space.xl,
                  Space.xxxl + Space.xl,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                greeting,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.titleLarge?.copyWith(
                                  color: onHero,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                dateLabel,
                                style: context.text.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Account',
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => context.go(Routes.account),
                            child: CircleAvatar(
                              radius: 21,
                              backgroundColor: onHero.withValues(alpha: 0.18),
                              foregroundColor: onHero,
                              child: Text(
                                initials,
                                style: context.text.labelLarge?.copyWith(
                                  color: onHero,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.xl),
                    ProgressRing(
                      size: 140,
                      strokeWidth: 10,
                      value: ringValue,
                      color: onHero,
                      overColor: const Color(0xFFFFB4A9),
                      trackColor: onHero.withValues(alpha: 0.18),
                      semanticLabel: ringSemantics,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Spent today',
                            style: context.text.labelLarge?.copyWith(
                              color: muted,
                            ),
                          ),
                          _CountUp(
                            value: s.todayTotalMinor,
                            format: format,
                            style: context.text.headlineMedium!.tabular
                                .copyWith(
                                  color: onHero,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ringLabel,
                            style: context.text.labelMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    _StatusPill(state: s.todayState, onHero: onHero),
                    const SizedBox(height: Space.xl),
                    _Glass(
                      child: Row(
                        children: [
                          _HeroStat(
                            label: 'This week',
                            value: format.amount(s.weekTotalMinor),
                            onHero: onHero,
                          ),
                          _Divider(color: onHero),
                          _HeroStat(
                            label: format.monthYear(s.today),
                            value: format.amount(s.monthTotalMinor),
                            onHero: onHero,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blurred colour blob used for the header's glow.
class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}

/// Frosted-glass panel on the coloured header.
class _Glass extends StatelessWidget {
  const _Glass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.lg + 4);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Amount that counts up to [value] when it first appears or changes.
class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.format,
    required this.style,
  });

  final int value;
  final AppFormat format;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final text = Text(format.amount(value), style: style);
    if (MediaQuery.disableAnimationsOf(context)) return text;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format.amount(v.round()), style: style),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.onHero});

  final DailyTrackingState state;
  final Color onHero;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (state) {
      DailyTrackingState.completedWithExpenses => (
        Icons.check_circle_rounded,
        'Today is complete',
      ),
      DailyTrackingState.confirmedNoExpenses => (
        Icons.do_not_disturb_on_rounded,
        'No spending today',
      ),
      DailyTrackingState.notReviewed => (
        Icons.radio_button_unchecked_rounded,
        'Today not completed yet',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: onHero.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: onHero),
          const SizedBox(width: Space.xs),
          Text(label, style: context.text.labelMedium?.copyWith(color: onHero)),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.onHero,
  });

  final String label;
  final String value;
  final Color onHero;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MergeSemantics(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: context.text.titleMedium!.tabular.copyWith(
                  color: onHero,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: onHero.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: color.withValues(alpha: 0.25));
}

/// Floating card with the two main actions, overlapping the hero's edge.
class HeroActions extends StatelessWidget {
  const HeroActions({super.key, required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final complete = s.todayState.isComplete;
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openExpenseEditor(context, date: s.today),
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  s.todayCount == 0 ? 'Add Your First Expense' : 'Add expense',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            if (!complete)
              Tooltip(
                message: s.todayCount > 0
                    ? 'Mark today as complete'
                    : 'Confirm you had no expenses today',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  ),
                  onPressed: () => DayStatusActions.markComplete(
                    context,
                    s.today,
                    hasExpenses: s.todayCount > 0,
                  ),
                  icon: const Icon(Icons.task_alt_rounded),
                  label: Text(s.todayCount > 0 ? 'Done' : 'No spend'),
                ),
              )
            else
              TextButton(
                onPressed: () => DayStatusActions.reopen(context, s.today),
                child: const Text('Reopen'),
              ),
          ],
        ),
      ),
    );
  }
}
