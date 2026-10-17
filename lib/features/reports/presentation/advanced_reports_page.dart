import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/services/advanced_report.dart';
import '../../../services/export/file_saver.dart';
import '../../../services/pdf/monthly_statement.dart';
import '../../../shared/charts/charts.dart';
import '../../premium/premium_gate.dart';

/// Premium: 12-month trend, category changes, weekday habits and PDF
/// monthly statements.
class AdvancedReportsPage extends StatelessWidget {
  const AdvancedReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced reports')),
      body: const PremiumGate(
        feature: 'Advanced reports & PDF',
        description:
            'See your 12-month trend, which categories grew, your most '
            'expensive weekdays, and download PDF monthly statements.',
        icon: Icons.insights_rounded,
        child: _AdvancedBody(),
      ),
    );
  }
}

class _AdvancedBody extends StatefulWidget {
  const _AdvancedBody();

  @override
  State<_AdvancedBody> createState() => _AdvancedBodyState();
}

class _AdvancedBodyState extends State<_AdvancedBody> {
  late final LocalDate _today = LocalDate.today(
    context.read<AppDependencies>().now,
  );
  late final Stream<List<Expense>> _stream = SessionScope.of(context).expenses
      .watchRange(AdvancedReport.rangeFor(_today));

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    return StreamBuilder<List<Expense>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return ErrorView(
            message: e is AppFailure
                ? e.message
                : "Couldn't load your reports.",
          );
        }
        final expenses = snap.data;
        if (expenses == null) return const LoadingView();
        final r = AdvancedReport.of(
          expenses: expenses,
          today: _today,
          currencyCode: fmt.currencyCode,
        );
        return _Content(
          report: r,
          expenses: expenses,
          today: _today,
          format: fmt,
        );
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.report,
    required this.expenses,
    required this.today,
    required this.format,
  });

  final AdvancedReport report;
  final List<Expense> expenses;
  final LocalDate today;
  final AppFormat format;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final r = report;
    final fmt = format;
    final categories = context.watch<CategoriesCubit>().state;
    const gap = SizedBox(height: Space.lg);
    final busiest = r.busiestMonth;
    final weekday = r.busiestWeekday;
    final avg = r.averageMonthMinor;
    final tiles = [
      StatTile(
        label: 'Average month',
        value: avg == null ? '—' : fmt.amount(avg),
        icon: Icons.calendar_month_rounded,
      ),
      StatTile(
        label: 'Busiest month',
        value: busiest == null ? '—' : fmt.amount(busiest.totalMinor),
        caption: busiest == null ? null : fmt.monthYear(busiest.month),
        icon: Icons.local_fire_department_rounded,
      ),
      StatTile(
        label: 'Costliest weekday',
        value: weekday == null ? '—' : _weekdayNames[weekday],
        caption: weekday == null
            ? null
            : '${fmt.amount(r.weekdayAverages[weekday])} on average',
        icon: Icons.today_rounded,
      ),
    ];
    return ListView(
      padding: pagePadding(context),
      children: [
        PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 700 ? 3 : 1;
                  final w = (c.maxWidth - (cols - 1) * Space.md) / cols;
                  return Wrap(
                    spacing: Space.md,
                    runSpacing: Space.md,
                    children: [
                      for (final t in tiles) SizedBox(width: w, child: t),
                    ],
                  );
                },
              ),
              gap,
              SectionCard(
                title: 'Last 12 months',
                subtitle: 'Total spending per month',
                child: SpendingBarChart(
                  format: fmt,
                  semanticTitle: 'Spending per month for the last year',
                  highlightIndex: r.months.length - 1,
                  data: [
                    for (final m in r.months)
                      ChartDatum(
                        label: fmt.monthShort(m.month.month),
                        valueMinor: m.totalMinor,
                        tooltipLabel: fmt.monthYear(m.month),
                      ),
                  ],
                ),
              ),
              gap,
              SectionCard(
                title: 'Categories: this month vs last',
                subtitle:
                    '${fmt.monthYear(today)} compared with '
                    '${fmt.monthYear(today.startOfMonth.addMonths(-1))}',
                child: r.categoryChanges.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(Space.md),
                        child: Text('No spending in these two months yet.'),
                      )
                    : Column(
                        children: [
                          for (final ch in r.categoryChanges.take(8))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CategoryAvatar(
                                category: categories.resolve(ch.categoryId),
                                size: 36,
                              ),
                              title: Text(
                                categories.resolve(ch.categoryId).name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Last month ${fmt.amount(ch.lastMonthMinor)}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    fmt.amount(ch.thisMonthMinor),
                                    style: context.text.titleSmall!.tabular,
                                  ),
                                  _ChangeBadge(change: ch),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              gap,
              SectionCard(
                title: 'Spending by weekday',
                subtitle:
                    'Average per day over the last ${r.weekdayWindowDays ~/ 7} '
                    'weeks',
                child: SpendingBarChart(
                  format: fmt,
                  semanticTitle: 'Average spending per weekday',
                  highlightIndex: weekday,
                  data: [
                    for (var i = 0; i < 7; i++)
                      ChartDatum(
                        label: _weekdays[i],
                        valueMinor: r.weekdayAverages[i],
                        tooltipLabel: _weekdayNames[i],
                      ),
                  ],
                ),
              ),
              gap,
              _StatementCard(today: today, format: fmt),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});

  final CategoryChange change;

  @override
  Widget build(BuildContext context) {
    final pct = change.percent;
    if (change.deltaMinor == 0) {
      return Text('No change', style: context.text.labelSmall);
    }
    final up = change.deltaMinor > 0;
    // Spending more is shown as a warning, less as good news.
    final color = up ? context.colors.error : context.appColors.success;
    return Text(
      pct == null ? 'New' : '${up ? '▲' : '▼'} ${pct.abs()}%',
      style: context.text.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Picks a month and shares its PDF statement.
class _StatementCard extends StatefulWidget {
  const _StatementCard({required this.today, required this.format});

  final LocalDate today;
  final AppFormat format;

  @override
  State<_StatementCard> createState() => _StatementCardState();
}

class _StatementCardState extends State<_StatementCard> {
  late LocalDate _month = widget.today.startOfMonth;
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    final session = SessionScope.of(context);
    final categories = context.read<CategoriesCubit>().state;
    final fmt = widget.format;
    final now = context.read<AppDependencies>().now();
    try {
      final range = DateRange(_month, _month.endOfMonth);
      final all = await session.expenses.watchRange(range).first;
      final expenses = [
        for (final e in all)
          if (e.currencyCode == fmt.currencyCode) e,
      ];
      final bytes = await MonthlyStatement.build(
        month: _month,
        monthLabel: fmt.monthYear(_month),
        ownerName: session.user.displayName ?? '',
        expenses: expenses,
        amount: fmt.amount,
        date: fmt.date,
        categoryName: (id) => categories.resolve(id).name,
        generatedAt: now,
      );
      await FileSaver.saveBytes(
        fileName: 'daily-expense-buddy-${_month.monthKey}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } catch (_) {
      if (mounted) showMessage(context, "Couldn't create the PDF. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.format;
    final months = [
      for (var i = 0; i < 12; i++) widget.today.startOfMonth.addMonths(-i),
    ];
    return SectionCard(
      title: 'PDF monthly statement',
      subtitle: 'Totals, categories and every expense, ready to share',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<LocalDate>(
            initialValue: _month,
            decoration: const InputDecoration(labelText: 'Month'),
            items: [
              for (final m in months)
                DropdownMenuItem(value: m, child: Text(fmt.monthYear(m))),
            ],
            onChanged: _busy ? null : (m) => setState(() => _month = m!),
          ),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            onPressed: _busy ? null : _download,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            label: Text(_busy ? 'Creating PDF…' : 'Download PDF'),
          ),
        ],
      ),
    );
  }
}
