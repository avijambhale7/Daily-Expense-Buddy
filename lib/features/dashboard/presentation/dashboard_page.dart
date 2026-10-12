import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/routes.dart';
import '../../../app/session/session_cubits.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../domain/models/daily_status.dart';
import '../../../domain/models/report_summary.dart';
import '../../../shared/charts/charts.dart';
import '../../../shared/widgets/expense_tile.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../calendar/day_status_actions.dart';
import '../../expenses/presentation/expense_editor.dart';
import '../cubit/dashboard_cubit.dart';
import 'mobile_hero.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final created = session.user.createdAt;
    return BlocProvider(
      create: (context) => DashboardCubit(
        expenses: session.expenses,
        statuses: session.dailyStatus,
        budgets: session.budgets,
        preferences: context.read<PreferencesCubit>(),
        accountStart: created == null ? null : LocalDate.fromDateTime(created),
        now: context.read<AppDependencies>().now,
      ),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<DashboardCubit>().refreshIfDayChanged(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardCubit>().state;
    final fmt = AppFormat.of(context);
    final now = context.read<AppDependencies>().now();
    final name = context.select((AuthCubit c) => c.state.user?.firstName) ?? '';
    final initials =
        context.select((AuthCubit c) => c.state.user?.initials) ?? '?';
    final width = MediaQuery.sizeOf(context).width;
    final size = windowSizeFor(width);

    final summary = state.summary;
    Widget body;
    if (summary == null && state.status == LoadStatus.failure) {
      body = ErrorView(
        message: state.error ?? 'Could not load your dashboard.',
        onRetry: context.read<DashboardCubit>().retry,
      );
    } else if (summary == null) {
      body = const LoadingView(label: 'Loading your dashboard');
    } else {
      body = _DashboardContent(
        summary: summary,
        format: fmt,
        size: size,
        greeting: name.isEmpty ? _greeting(now) : '${_greeting(now)}, $name',
        dateLabel: fmt.dateLong(LocalDate.fromDateTime(now)),
        initials: initials,
      );
    }

    if (size == WindowSize.compact) {
      return Scaffold(body: summary == null ? SafeArea(child: body) : body);
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? _greeting(now) : '${_greeting(now)}, $name',
              style: context.text.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              fmt.dateLong(LocalDate.fromDateTime(now)),
              style: context.text.bodySmall,
            ),
          ],
        ),
        actions: [
          if (size == WindowSize.compact)
            Padding(
              padding: const EdgeInsets.only(right: Space.lg),
              child: Tooltip(
                message: 'Account',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.go(Routes.account),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: context.colors.primaryContainer,
                    foregroundColor: context.colors.onPrimaryContainer,
                    child: Text(initials, style: context.text.labelLarge),
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Reports',
              onPressed: () => context.go(Routes.reports),
              icon: const Icon(Icons.insights_rounded),
            ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: body,
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.summary,
    required this.format,
    required this.size,
    required this.greeting,
    required this.dateLabel,
    required this.initials,
  });

  final DashboardSummary summary;
  final AppFormat format;
  final WindowSize size;
  final String greeting;
  final String dateLabel;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CategoriesCubit>().state;
    final reminders = context.select(
      (PreferencesCubit c) => c.state.preferences.reminders.enabled,
    );
    final s = summary;

    final today = _TodayCard(summary: s, format: format);
    final missed = _MissedDaysCard(summary: s);
    final tiles = [
      StatTile(
        label: 'This week',
        value: format.amount(s.weekTotalMinor),
        icon: Icons.date_range_rounded,
      ),
      StatTile(
        label: format.monthYear(s.today),
        value: format.amount(s.monthTotalMinor),
        icon: Icons.calendar_view_month_rounded,
      ),
      StatTile(
        label: '${s.today.year} so far',
        value: format.amount(s.yearTotalMinor),
        icon: Icons.calendar_today_rounded,
      ),
    ];
    final weekChart = SectionCard(
      title: 'This week',
      subtitle: 'Daily spending',
      trailing: TextButton(
        onPressed: () => context.go(Routes.reports),
        child: const Text('Reports'),
      ),
      child: SpendingBarChart(
        format: format,
        semanticTitle: 'Spending per day this week',
        highlightIndex: s.weekDaily.indexWhere((d) => d.date == s.today),
        data: [
          for (final d in s.weekDaily)
            ChartDatum(
              label: format.weekdayShort(d.date),
              valueMinor: d.totalMinor,
              tooltipLabel: format.weekdayDay(d.date),
              muted: d.date > s.today,
            ),
        ],
      ),
    );
    final categoryCard = SectionCard(
      title: 'Categories',
      subtitle: format.monthYear(s.today),
      child: s.monthCategories.isEmpty
          ? const EmptyState(
              compact: true,
              icon: Icons.donut_large_rounded,
              title: 'No spending this month yet',
            )
          : CategoryBreakdown(
              totals: s.monthCategories,
              resolve: categories.resolve,
              format: format,
              horizontal: size != WindowSize.compact,
            ),
    );
    final trendCard = SectionCard(
      title: 'Monthly trend',
      subtitle: 'Last 6 months',
      child: TrendLineChart(
        format: format,
        data: [
          for (final m in s.trend)
            ChartDatum(
              label: format.monthShort(m.month),
              valueMinor: m.totalMinor,
              tooltipLabel: format.monthYear(m.firstDay),
            ),
        ],
      ),
    );
    final recentCard = SectionCard(
      title: 'Recent expenses',
      trailing: TextButton(
        onPressed: () => context.go(Routes.history),
        child: const Text('View all'),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.sm,
      ),
      child: s.recent.isEmpty
          ? EmptyState(
              compact: true,
              icon: Icons.receipt_long_rounded,
              title: "You haven't recorded any expenses yet",
              action: FilledButton.icon(
                onPressed: () => openExpenseEditor(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Your First Expense'),
              ),
            )
          : Column(
              children: [
                for (final e in s.recent)
                  ExpenseTile(
                    expense: e,
                    category: categories.resolve(e.categoryId),
                    format: format,
                    showDate: true,
                    today: s.today,
                    onTap: () => openExpenseEditor(context, expenseId: e.id),
                  ),
              ],
            ),
    );
    final extras = <Widget>[
      if (s.excludedOtherCurrencyCount > 0)
        InfoBanner(
          message:
              '${s.excludedOtherCurrencyCount} expense(s) this month are in '
              'another currency and are not included in these totals.',
        ),
      if (!reminders)
        InfoBanner(
          icon: Icons.notifications_none_rounded,
          message: 'Get a gentle daily reminder to log your expenses.',
          action: TextButton(
            onPressed: () => context.go(Routes.reminders),
            child: const Text('Set up'),
          ),
        ),
    ];

    const gap = SizedBox(height: Space.lg, width: Space.lg);
    final padding = pagePadding(context);

    if (size == WindowSize.compact) {
      return ListView(
        padding: EdgeInsets.only(bottom: padding.bottom),
        children: [
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: MobileHero(
                  summary: s,
                  format: format,
                  greeting: greeting,
                  dateLabel: dateLabel,
                  initials: initials,
                ),
              ),
              Positioned(
                left: padding.left,
                right: padding.right,
                bottom: 0,
                child: HeroActions(summary: s),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding.left),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.lg),
                const QuickActions(),
                if (missed.isVisible) ...[gap, missed],
                gap,
                for (final e in extras) ...[e, gap],
                weekChart,
                gap,
                recentCard,
                gap,
                categoryCard,
                gap,
                trendCard,
              ],
            ),
          ),
        ],
      );
    }

    final wide = size == WindowSize.expanded;
    return SingleChildScrollView(
      padding: padding,
      child: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: wide ? 2 : 3, child: today),
                  if (wide)
                    for (final t in tiles) ...[gap, Expanded(child: t)],
                ],
              ),
            ),
            if (!wide) ...[
              gap,
              Row(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) gap,
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            ],
            if (missed.isVisible) ...[gap, missed],
            for (final e in extras) ...[gap, e],
            gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: weekChart),
                gap,
                Expanded(flex: 2, child: trendCard),
              ],
            ),
            gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: recentCard),
                gap,
                Expanded(flex: 2, child: categoryCard),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.summary, required this.format});

  final DashboardSummary summary;
  final AppFormat format;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final c = context.colors;
    final app = context.appColors;
    final complete = s.todayState.isComplete;
    final allowance = s.dailyAllowanceMinor;
    final onHero = c.onPrimaryContainer;

    // Ring: today vs. the daily budget when a monthly budget exists;
    // otherwise how many days of this week have been tracked.
    final Widget ring;
    final String caption;
    if (allowance != null) {
      final value = allowance == 0
          ? (s.todayTotalMinor > 0 ? 1.01 : 0.0)
          : s.todayTotalMinor / allowance;
      final left = allowance - s.todayTotalMinor;
      caption = left >= 0
          ? '${format.amount(left)} left for today'
          : "${format.amount(-left)} over today's budget";
      ring = ProgressRing(
        value: value,
        color: c.primary,
        overColor: c.error,
        trackColor: onHero.withValues(alpha: 0.12),
        semanticLabel:
            'Spent ${format.amount(s.todayTotalMinor)} of a daily budget of '
            '${format.amount(allowance)}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allowance == 0
                  ? '—'
                  : '${(s.todayTotalMinor * 100 / allowance).round()}%',
              style: context.text.headlineSmall!.tabular.copyWith(
                color: onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'of daily\nbudget',
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(color: onHero),
            ),
          ],
        ),
      );
    } else {
      final tracked = s.weekReviewedDays;
      final total = s.weekElapsedDays == 0 ? 1 : s.weekElapsedDays;
      caption = tracked == total
          ? 'Every day this week is tracked'
          : '$tracked of $total days tracked this week';
      ring = ProgressRing(
        value: tracked / total,
        color: app.success,
        trackColor: onHero.withValues(alpha: 0.12),
        semanticLabel: '$tracked of $total days tracked this week',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$tracked/$total',
              style: context.text.headlineSmall!.tabular.copyWith(
                color: onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'days\ntracked',
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(color: onHero),
            ),
          ],
        ),
      );
    }

    return Card(
      color: c.primaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ring,
                const SizedBox(width: Space.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spent today',
                        style: context.text.titleSmall?.copyWith(color: onHero),
                      ),
                      Semantics(
                        label:
                            "Today's spending ${format.amount(s.todayTotalMinor)}",
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            format.amount(s.todayTotalMinor),
                            style: context.text.headlineLarge!.tabular.copyWith(
                              color: onHero,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.todayCount == 0
                            ? 'No expenses recorded yet'
                            : '${s.todayCount} expense${s.todayCount == 1 ? '' : 's'}',
                        style: context.text.bodyMedium?.copyWith(color: onHero),
                      ),
                      Text(
                        caption,
                        style: context.text.bodySmall?.copyWith(
                          color: onHero.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      TrackingStatusChip(state: s.todayState, dense: true),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => openExpenseEditor(context, date: s.today),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      s.todayCount == 0
                          ? 'Add Your First Expense'
                          : 'Add expense',
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
                        foregroundColor: onHero,
                        side: BorderSide(color: onHero.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.lg,
                        ),
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
                    style: TextButton.styleFrom(foregroundColor: onHero),
                    onPressed: () => DayStatusActions.reopen(context, s.today),
                    child: const Text('Reopen'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MissedDaysCard extends StatelessWidget {
  const _MissedDaysCard({required this.summary});

  final DashboardSummary summary;

  bool get isVisible => summary.incompleteDays.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final yesterday = summary.today.addDays(-1);
    final yesterdayMissing =
        summary.yesterdayState == DailyTrackingState.notReviewed;
    final others = summary.incompleteDays.where((d) => d != yesterday).length;
    final app = context.appColors;
    final c = context.colors;
    final title = yesterdayMissing
        ? "Yesterday isn't complete"
        : '$others day${others == 1 ? '' : 's'} not completed';
    final subtitle = yesterdayMissing
        ? (others > 0
              ? '+$others more this week · tap to finish'
              : 'Tap to add what you spent')
        : 'Review them in the calendar';
    return Material(
      color: app.warningContainer,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () => yesterdayMissing
            ? openExpenseEditor(context, date: yesterday)
            : context.go(Routes.calendar),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.sm,
            Space.md,
          ),
          child: Row(
            children: [
              IconBadge(
                icon: Icons.pending_actions_rounded,
                color: app.warning,
                size: 40,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.titleSmall?.copyWith(
                        color: c.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: context.text.bodySmall?.copyWith(
                        color: c.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (yesterdayMissing)
                Tooltip(
                  message: "Complete Yesterday's Expenses",
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: c.onSurface),
                    onPressed: () =>
                        openExpenseEditor(context, date: yesterday),
                    child: const Text('Complete'),
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, color: c.onSurface),
            ],
          ),
        ),
      ),
    );
  }
}
