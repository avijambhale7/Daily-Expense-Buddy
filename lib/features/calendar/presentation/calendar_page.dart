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
import '../../../domain/models/daily_status.dart';
import '../cubit/calendar_cubits.dart';

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return BlocProvider(
      create: (context) => CalendarCubit(
        expenses: session.expenses,
        statuses: session.dailyStatus,
        preferences: context.read<PreferencesCubit>(),
        today: LocalDate.today(context.read<AppDependencies>().now),
      ),
      child: const _CalendarView(),
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CalendarCubit>().state;
    final cubit = context.read<CalendarCubit>();
    final fmt = AppFormat.of(context);
    final today = LocalDate.today(context.read<AppDependencies>().now);
    final pad = pagePadding(context);

    Widget grid;
    if (state.status == LoadStatus.failure && state.days.isEmpty) {
      grid = ErrorView(
        message: state.error ?? 'Could not load the calendar.',
        onRetry: cubit.retry,
      );
    } else {
      grid = _MonthGrid(state: state, format: fmt, today: today);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: ListView(
        padding: pad,
        children: [
          PageBody(
            maxWidth: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: cubit.previousMonth,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          fmt.monthYear(state.month),
                          style: context.text.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: cubit.nextMonth,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                if (state.status == LoadStatus.ready)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: Text(
                      'Total this month: ${fmt.amount(state.monthTotalMinor)}',
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium!.tabular,
                    ),
                  ),
                if (state.month != today.startOfMonth)
                  Center(
                    child: TextButton(
                      onPressed: () => cubit.showMonth(today),
                      child: const Text('Back to this month'),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.sm),
                    child: grid,
                  ),
                ),
                const SizedBox(height: Space.lg),
                const _Legend(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.state,
    required this.format,
    required this.today,
  });

  final CalendarState state;
  final AppFormat format;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final headers = format.weekdayHeaders();
    final first = state.month;
    final leading = (first.weekday - format.weekStart + 7) % 7;
    final daysInMonth = LocalDate.daysInMonth(first.year, first.month);
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final loading = state.status == LoadStatus.loading;

    return Column(
      children: [
        Row(
          children: [
            for (final h in headers)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Text(
                    h,
                    textAlign: TextAlign.center,
                    style: context.text.labelMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final index = r * 7 + c - leading;
                      if (index < 0 || index >= daysInMonth) {
                        return const AspectRatio(
                          aspectRatio: 0.8,
                          child: SizedBox(),
                        );
                      }
                      final date = first.addDays(index);
                      return _DayCell(
                        date: date,
                        day: state.days[date],
                        format: format,
                        today: today,
                        loading: loading,
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.day,
    required this.format,
    required this.today,
    required this.loading,
  });

  final LocalDate date;
  final CalendarDay? day;
  final AppFormat format;
  final LocalDate today;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final future = date > today;
    final isToday = date == today;
    final d = day;
    final c = context.colors;
    final state = d?.state;
    final showStatus = !future && !loading && state != null;
    final statusLabel = showStatus ? state.label : (future ? 'Future' : '');
    final semantic =
        '${format.dateLong(date)}. '
        '${d != null && d.totalMinor > 0 ? 'Spent ${format.amount(d.totalMinor)}. ' : ''}'
        '$statusLabel';

    return Semantics(
      button: !future,
      label: semantic,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AspectRatio(
          aspectRatio: 0.8,
          child: Material(
            color: isToday ? c.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: future ? null : () => context.go(Routes.day(date)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: context.text.labelLarge?.copyWith(
                        color: future
                            ? c.onSurface.withValues(alpha: 0.38)
                            : (isToday ? c.onPrimaryContainer : c.onSurface),
                      ),
                    ),
                    const Spacer(),
                    if (d != null && d.totalMinor > 0)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          format.compact(d.totalMinor),
                          style: context.text.labelSmall!.tabular.copyWith(
                            color: isToday ? c.onPrimaryContainer : c.onSurface,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    if (showStatus)
                      Icon(
                        TrackingStatusChip.iconFor(state),
                        size: 14,
                        color: TrackingStatusChip.colorFor(context, state),
                      )
                    else
                      const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.sm,
      alignment: WrapAlignment.center,
      children: [
        for (final s in DailyTrackingState.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                TrackingStatusChip.iconFor(s),
                size: 16,
                color: TrackingStatusChip.colorFor(context, s),
              ),
              const SizedBox(width: Space.xs),
              Text(switch (s) {
                DailyTrackingState.completedWithExpenses => 'Completed',
                DailyTrackingState.confirmedNoExpenses =>
                  'Confirmed no expenses',
                DailyTrackingState.notReviewed => 'Not reviewed yet',
              }, style: context.text.bodySmall),
            ],
          ),
        Text(
          'A day without expenses is only "no expenses" once you confirm it.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}
