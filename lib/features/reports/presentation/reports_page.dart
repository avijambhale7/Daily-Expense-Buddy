import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/dates/report_period.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/report_summary.dart';
import '../../../domain/services/expense_validator.dart';
import '../../../domain/services/report_calculator.dart';
import '../../../shared/charts/charts.dart';
import '../../../shared/widgets/expense_tile.dart';
import '../../expenses/presentation/expense_editor.dart';
import '../cubit/report_cubit.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ReportCubit(
        expenses: SessionScope.of(context).expenses,
        preferences: context.read<PreferencesCubit>(),
        today: LocalDate.today(context.read<AppDependencies>().now),
      ),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView();

  String _periodTitle(ReportPeriod p, AppFormat fmt) {
    switch (p.type) {
      case ReportPeriodType.day:
        return fmt.dateLong(p.range.start);
      case ReportPeriodType.week:
      case ReportPeriodType.custom:
        return fmt.range(p.range);
      case ReportPeriodType.month:
        return fmt.monthYear(p.range.start);
      case ReportPeriodType.year:
        return '${p.range.start.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ReportCubit>().state;
    final cubit = context.read<ReportCubit>();
    final fmt = AppFormat.of(context);
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    final pad = pagePadding(context);

    Future<void> pickCustom() async {
      final r = await showDateRangePicker(
        context: context,
        firstDate: ExpenseValidator.earliestDate.toDateTime(),
        lastDate: state.today.toDateTime(),
        initialDateRange: DateTimeRange(
          start: state.period.range.start.toDateTime(),
          end: LocalDate.min(state.period.range.end, state.today).toDateTime(),
        ),
      );
      if (r != null) {
        cubit.setCustomRange(
          DateRange(
            LocalDate.fromDateTime(r.start),
            LocalDate.fromDateTime(r.end),
          ),
        );
      }
    }

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SegmentedButton<ReportPeriodType>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(value: ReportPeriodType.day, label: Text('Day')),
              ButtonSegment(value: ReportPeriodType.week, label: Text('Week')),
              ButtonSegment(
                value: ReportPeriodType.month,
                label: Text('Month'),
              ),
              ButtonSegment(value: ReportPeriodType.year, label: Text('Year')),
              ButtonSegment(
                value: ReportPeriodType.custom,
                label: Text('Custom'),
              ),
            ],
            selected: {state.period.type},
            onSelectionChanged: (s) => cubit.setType(s.first),
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            if (state.period.type != ReportPeriodType.custom)
              IconButton(
                tooltip: 'Previous period',
                onPressed: cubit.previous,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _periodTitle(state.period, fmt),
                  style: context.text.titleMedium,
                  textAlign: state.period.type == ReportPeriodType.custom
                      ? TextAlign.start
                      : TextAlign.center,
                ),
              ),
            ),
            if (state.period.type == ReportPeriodType.custom)
              OutlinedButton.icon(
                onPressed: pickCustom,
                icon: const Icon(Icons.date_range_rounded),
                label: const Text('Change'),
              )
            else ...[
              IconButton(
                tooltip: 'Next period',
                onPressed: state.canGoNext ? cubit.next : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              if (!state.period.isCurrent(state.today))
                TextButton(
                  onPressed: cubit.showToday,
                  child: const Text('Current'),
                ),
            ],
          ],
        ),
      ],
    );

    final summary = state.summary;
    Widget content;
    if (summary == null && state.status == LoadStatus.failure) {
      content = ErrorView(
        message: state.error ?? 'Could not load this report.',
        onRetry: cubit.retry,
      );
    } else if (summary == null) {
      content = const Padding(
        padding: EdgeInsets.only(top: 80),
        child: LoadingView(),
      );
    } else {
      content = _ReportBody(
        summary: summary,
        format: fmt,
        size: size,
        today: state.today,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: pad,
        children: [
          PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                controls,
                const SizedBox(height: Space.lg),
                content,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatefulWidget {
  const _ReportBody({
    required this.summary,
    required this.format,
    required this.size,
    required this.today,
  });

  final ReportSummary summary;
  final AppFormat format;
  final WindowSize size;
  final LocalDate today;

  @override
  State<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<_ReportBody> {
  bool _weekly = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final fmt = widget.format;
    final categories = context.watch<CategoriesCubit>().state;
    final type = s.period.type;
    final current = s.period.isCurrent(widget.today);
    const gap = SizedBox(height: Space.lg, width: Space.lg);

    final tiles = [
      StatTile(
        label: 'Total spent',
        value: fmt.amount(s.totalMinor),
        icon: Icons.payments_rounded,
        emphasize: true,
      ),
      StatTile(
        label: 'Avg per calendar day',
        value: s.avgPerCalendarDayMinor == null
            ? '—'
            : fmt.amount(s.avgPerCalendarDayMinor!),
        caption: current && s.elapsedDays < s.period.range.dayCount
            ? 'Over ${s.elapsedDays} of ${s.period.range.dayCount} days so far'
            : 'Over ${s.elapsedDays} day${s.elapsedDays == 1 ? '' : 's'}',
        icon: Icons.calendar_view_day_rounded,
      ),
      StatTile(
        label: 'Avg per spending day',
        value: s.avgPerSpendingDayMinor == null
            ? '—'
            : fmt.amount(s.avgPerSpendingDayMinor!),
        caption:
            '${s.spendingDays} day${s.spendingDays == 1 ? '' : 's'} with expenses',
        icon: Icons.event_available_rounded,
      ),
      StatTile(
        label: 'Transactions',
        value: '${s.transactionCount}',
        caption:
            '${s.noSpendDays} day${s.noSpendDays == 1 ? '' : 's'} without expenses',
        icon: Icons.receipt_long_rounded,
      ),
    ];
    final tileGrid = LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * Space.md) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );

    final comparison = _ComparisonCard(summary: s, format: fmt);

    Widget? chart;
    if (type != ReportPeriodType.day) {
      final useMonthly =
          type == ReportPeriodType.year ||
          (type == ReportPeriodType.custom && s.period.range.dayCount > 62);
      List<ChartDatum> data;
      String title;
      if (useMonthly) {
        title = 'Spending by month';
        data = [
          for (final m in s.monthlyTotals)
            ChartDatum(
              label: fmt.monthShort(m.month),
              valueMinor: m.totalMinor,
              tooltipLabel: fmt.monthYear(m.firstDay),
              muted: m.firstDay > widget.today,
            ),
        ];
      } else if (type == ReportPeriodType.month && _weekly) {
        title = 'Spending by week';
        final weekStart = context
            .read<PreferencesCubit>()
            .preferences
            .weekStart;
        data = [
          for (final w in ReportCalculator.weeklyBuckets(
            s.dailyTotals,
            weekStart,
          ))
            ChartDatum(
              label: fmt.dayMonth(w.date),
              valueMinor: w.totalMinor,
              tooltipLabel: 'Week of ${fmt.dayMonth(w.date)}',
              muted: w.date > widget.today,
            ),
        ];
      } else {
        title = 'Spending by day';
        data = [
          for (final d in s.dailyTotals)
            ChartDatum(
              label: type == ReportPeriodType.week
                  ? fmt.weekdayShort(d.date)
                  : '${d.date.day}',
              valueMinor: d.totalMinor,
              tooltipLabel: fmt.weekdayDay(d.date),
              muted: d.date > widget.today,
            ),
        ];
      }
      chart = SectionCard(
        title: title,
        trailing: type == ReportPeriodType.month
            ? SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Daily')),
                  ButtonSegment(value: true, label: Text('Weekly')),
                ],
                selected: {_weekly},
                onSelectionChanged: (v) => setState(() => _weekly = v.first),
              )
            : null,
        child: SpendingBarChart(
          data: data,
          format: fmt,
          height: 220,
          semanticTitle: title,
        ),
      );
    }

    final highlights = _HighlightsCard(summary: s, format: fmt);

    final categoryCard = SectionCard(
      title: 'Categories',
      child: s.categories.isEmpty
          ? const EmptyState(
              compact: true,
              icon: Icons.donut_large_rounded,
              title: 'No spending in this period',
            )
          : CategoryBreakdown(
              totals: s.categories,
              resolve: categories.resolve,
              format: fmt,
              horizontal: widget.size != WindowSize.compact,
            ),
    );

    final List<Expense> listed = type == ReportPeriodType.day
        ? s.expenses
        : ([...s.expenses]
                ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor)))
              .take(5)
              .toList();
    final txCard = SectionCard(
      title: type == ReportPeriodType.day ? 'Transactions' : 'Largest expenses',
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.sm,
      ),
      child: listed.isEmpty
          ? EmptyState(
              compact: true,
              icon: Icons.receipt_long_rounded,
              title: 'No expenses recorded',
              action:
                  type == ReportPeriodType.day &&
                      s.period.range.start <= widget.today
                  ? FilledButton.icon(
                      onPressed: () => openExpenseEditor(
                        context,
                        date: s.period.range.start,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add expense'),
                    )
                  : null,
            )
          : Column(
              children: [
                for (final e in listed)
                  ExpenseTile(
                    expense: e,
                    category: categories.resolve(e.categoryId),
                    format: fmt,
                    showDate: type != ReportPeriodType.day,
                    today: widget.today,
                    onTap: () => openExpenseEditor(context, expenseId: e.id),
                  ),
              ],
            ),
    );

    final notes = Text(
      'Average per calendar day divides the total by every day of the period '
      '(up to today for the current period). Lowest day only considers days '
      'with spending. Comparisons use the equivalent previous period.',
      style: context.text.bodySmall,
    );

    final banners = [
      if (s.excludedOtherCurrencyCount > 0)
        InfoBanner(
          message:
              '${s.excludedOtherCurrencyCount} expense(s) in other currencies are not '
              'included. Reports use your reporting currency (${s.currencyCode}) only.',
        ),
    ];

    if (widget.size == WindowSize.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in banners) ...[b, gap],
          tileGrid,
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: chart ?? categoryCard),
              gap,
              Expanded(
                flex: 2,
                child: Column(children: [comparison, gap, highlights]),
              ),
            ],
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: txCard),
              gap,
              Expanded(
                flex: 2,
                child: chart == null ? const SizedBox.shrink() : categoryCard,
              ),
            ],
          ),
          gap,
          notes,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in banners) ...[b, gap],
        tileGrid,
        gap,
        comparison,
        if (chart != null) ...[gap, chart],
        gap,
        highlights,
        gap,
        categoryCard,
        gap,
        txCard,
        gap,
        notes,
      ],
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.summary, required this.format});

  final ReportSummary summary;
  final AppFormat format;

  @override
  Widget build(BuildContext context) {
    final c = summary.comparison;
    if (c == null) return const SizedBox.shrink();
    final label = summary.period.comparisonLabel;
    final app = context.appColors;
    final IconData icon;
    final Color color;
    final String headline;
    if (c.previousTotalMinor == 0 && summary.totalMinor == 0) {
      icon = Icons.remove_rounded;
      color = context.colors.onSurfaceVariant;
      headline = 'No spending in this or the $label';
    } else if (c.changeBasisPoints == null) {
      icon = Icons.info_outline_rounded;
      color = context.colors.onSurfaceVariant;
      headline = 'No spending in the $label to compare with';
    } else if (c.differenceMinor == 0) {
      icon = Icons.drag_handle_rounded;
      color = context.colors.onSurfaceVariant;
      headline = 'Same as the $label';
    } else {
      final up = c.differenceMinor > 0;
      icon = up ? Icons.trending_up_rounded : Icons.trending_down_rounded;
      color = up ? app.spendingUp : app.spendingDown;
      headline =
          '${MoneyFormatter.percentFromBasisPoints(c.changeBasisPoints!.abs(), locale: format.locale)} '
          '${up ? 'more' : 'less'} than the $label';
    }
    return SectionCard(
      title: 'Compared with the $label',
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${format.amount(summary.totalMinor)} vs ${format.amount(c.previousTotalMinor)}',
                  style: context.text.bodyMedium!.tabular.copyWith(
                    color: context.colors.onSurfaceVariant,
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

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.summary, required this.format});

  final ReportSummary summary;
  final AppFormat format;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final year = s.period.type == ReportPeriodType.year;
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.colors.onSurfaceVariant),
          const SizedBox(width: Space.md),
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          Flexible(
            child: Text(
              value,
              style: context.text.labelLarge!.tabular,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
    String day(DayTotal? d) => d == null
        ? '—'
        : '${format.weekdayDay(d.date)} · ${format.amount(d.totalMinor)}';
    String month(MonthTotal? m) => m == null
        ? '—'
        : '${format.monthShort(m.month)} · ${format.amount(m.totalMinor)}';
    return SectionCard(
      title: 'Highlights',
      child: s.isEmpty
          ? Text(
              'No expenses recorded in this period.',
              style: context.text.bodyMedium,
            )
          : Column(
              children: [
                if (year) ...[
                  row(
                    Icons.arrow_upward_rounded,
                    'Highest month',
                    month(s.highestMonth),
                  ),
                  row(
                    Icons.arrow_downward_rounded,
                    'Lowest month',
                    month(s.lowestMonth),
                  ),
                  row(
                    Icons.functions_rounded,
                    'Average per month',
                    s.avgPerMonthMinor == null
                        ? '—'
                        : format.amount(s.avgPerMonthMinor!),
                  ),
                ],
                if (s.period.type != ReportPeriodType.day) ...[
                  row(
                    Icons.north_east_rounded,
                    'Highest day',
                    day(s.highestDay),
                  ),
                  row(
                    Icons.south_east_rounded,
                    'Lowest spending day',
                    day(s.lowestDay),
                  ),
                  row(
                    Icons.event_busy_rounded,
                    'Days without expenses',
                    '${s.noSpendDays}',
                  ),
                ] else
                  row(
                    Icons.receipt_rounded,
                    'Transactions',
                    '${s.transactionCount}',
                  ),
              ],
            ),
    );
  }
}
