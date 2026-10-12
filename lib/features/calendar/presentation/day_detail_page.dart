import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/daily_status.dart';
import '../../../domain/services/report_calculator.dart';
import '../../../shared/widgets/expense_tile.dart';
import '../../expenses/presentation/expense_editor.dart';
import '../cubit/calendar_cubits.dart';
import '../day_status_actions.dart';

/// Summary of a single day: its expenses, total and tracking status, with
/// actions to add/edit expenses and complete (or reopen) the day.
class DayDetailPage extends StatelessWidget {
  const DayDetailPage({super.key, required this.date});

  final LocalDate date;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return BlocProvider(
      create: (_) => DayCubit(
        expenses: session.expenses,
        statuses: session.dailyStatus,
        date: date,
      ),
      child: _DayView(date: date),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({required this.date});

  final LocalDate date;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DayCubit>().state;
    final fmt = AppFormat.of(context);
    final today = LocalDate.today(context.read<AppDependencies>().now);
    final categories = context.watch<CategoriesCubit>().state;
    final future = date > today;
    final total = ReportCalculator.totalFor(
      state.expenses,
      fmt.currencyCode,
      DateRange(date, date),
    );

    Widget body;
    if (state.status == LoadStatus.loading) {
      body = const LoadingView();
    } else if (state.status == LoadStatus.failure) {
      body = ErrorView(message: state.error ?? 'Could not load this day.');
    } else {
      final tracking = state.trackingState;
      final hasExpenses = state.expenses.isNotEmpty;
      body = ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Total spent',
                                style: context.text.titleSmall,
                              ),
                            ),
                            if (!future) TrackingStatusChip(state: tracking),
                          ],
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          fmt.amount(total),
                          style: context.text.headlineMedium!.tabular,
                        ),
                        Text(
                          '${state.expenses.length} expense${state.expenses.length == 1 ? '' : 's'}',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        if (!future) ...[
                          const SizedBox(height: Space.lg),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.sm,
                            children: [
                              FilledButton.icon(
                                onPressed: () =>
                                    openExpenseEditor(context, date: date),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add expense'),
                              ),
                              if (!tracking.isComplete) ...[
                                if (hasExpenses)
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        DayStatusActions.markComplete(
                                          context,
                                          date,
                                          hasExpenses: true,
                                        ),
                                    icon: const Icon(Icons.task_alt_rounded),
                                    label: const Text('Mark day complete'),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        DayStatusActions.confirmNoExpenses(
                                          context,
                                          date,
                                        ),
                                    icon: const Icon(
                                      Icons.do_not_disturb_on_outlined,
                                    ),
                                    label: const Text('I had no expenses'),
                                  ),
                              ] else
                                TextButton(
                                  onPressed: () =>
                                      DayStatusActions.reopen(context, date),
                                  child: const Text('Reopen day'),
                                ),
                            ],
                          ),
                        ],
                        if (!future &&
                            tracking == DailyTrackingState.notReviewed &&
                            date < today) ...[
                          const SizedBox(height: Space.md),
                          Text(
                            "This day hasn't been reviewed. Add anything you spent, "
                            'or confirm you had no expenses.',
                            style: context.text.bodySmall?.copyWith(
                              color: context.appColors.statusIncomplete,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                SectionCard(
                  title: 'Expenses',
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.lg,
                    Space.lg,
                    Space.sm,
                  ),
                  child: state.expenses.isEmpty
                      ? EmptyState(
                          compact: true,
                          icon: Icons.receipt_long_rounded,
                          title: future
                              ? 'This day is in the future'
                              : 'No expenses recorded for this day',
                        )
                      : Column(
                          children: [
                            for (final e in state.expenses)
                              ExpenseTile(
                                key: ValueKey(e.id),
                                expense: e,
                                category: categories.resolve(e.categoryId),
                                format: fmt,
                                onTap: () =>
                                    openExpenseEditor(context, expenseId: e.id),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fmt.relativeDay(date, today) == 'Today'
              ? 'Today'
              : fmt.dateLong(date),
        ),
      ),
      body: body,
    );
  }
}
