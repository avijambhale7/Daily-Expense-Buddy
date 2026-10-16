import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/money/money_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/budget.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/expense_category.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/budget_calculator.dart';

class BudgetsState extends Equatable {
  const BudgetsState({
    this.status = LoadStatus.loading,
    this.statuses = const [],
    this.error,
  });

  final LoadStatus status;
  final List<BudgetStatus> statuses;
  final String? error;

  BudgetStatus? get overall =>
      statuses.where((s) => s.budget.isOverall).firstOrNull;
  List<BudgetStatus> get categoryBudgets =>
      statuses.where((s) => !s.budget.isOverall).toList();

  @override
  List<Object?> get props => [status, statuses, error];
}

class BudgetsCubit extends Cubit<BudgetsState> {
  BudgetsCubit({
    required this.repository,
    required ExpenseRepository expenses,
    required PreferencesCubit preferences,
    required this.month,
  }) : _preferences = preferences,
       super(const BudgetsState()) {
    void onError(Object e) {
      if (!isClosed) {
        emit(
          BudgetsState(
            status: LoadStatus.failure,
            statuses: state.statuses,
            error: e is AppFailure ? e.message : AppFailure.unknown(e).message,
          ),
        );
      }
    }

    _bSub = repository.watchAll().listen((b) {
      _budgets = b;
      _recompute();
    }, onError: onError);
    _eSub = expenses.watchRange(DateRange(month, month.endOfMonth)).listen((e) {
      _expenses = e;
      _recompute();
    }, onError: onError);
    _pSub = preferences.stream.listen((_) => _recompute());
  }

  final BudgetRepository repository;
  final LocalDate month;
  final PreferencesCubit _preferences;
  StreamSubscription<List<Budget>>? _bSub;
  StreamSubscription<List<Expense>>? _eSub;
  StreamSubscription<PreferencesState>? _pSub;
  List<Budget>? _budgets;
  List<Expense>? _expenses;

  void _recompute() {
    final b = _budgets;
    final e = _expenses;
    if (b == null || e == null || isClosed) return;
    emit(
      BudgetsState(
        status: LoadStatus.ready,
        statuses: BudgetCalculator.statuses(
          budgets: b,
          expenses: e,
          month: month,
          thresholds: _preferences.preferences.budgetAlertThresholds,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _bSub?.cancel();
    await _eSub?.cancel();
    await _pSub?.cancel();
    return super.close();
  }
}

class BudgetsPage extends StatelessWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return BlocProvider(
      create: (context) => BudgetsCubit(
        repository: session.budgets,
        expenses: session.expenses,
        preferences: context.read<PreferencesCubit>(),
        month: LocalDate.today(context.read<AppDependencies>().now)
            .startOfMonth,
      ),
      child: const _BudgetsView(),
    );
  }
}

class _BudgetsView extends StatelessWidget {
  const _BudgetsView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BudgetsCubit>().state;
    final cubit = context.read<BudgetsCubit>();
    final fmt = AppFormat.of(context);
    final prefs = context.watch<PreferencesCubit>().state.preferences;
    final categories = context.watch<CategoriesCubit>().state;

    Widget content;
    if (state.status == LoadStatus.loading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 80),
        child: LoadingView(),
      );
    } else if (state.status == LoadStatus.failure && state.statuses.isEmpty) {
      content = ErrorView(message: state.error ?? 'Could not load budgets.');
    } else {
      final overall = state.overall;
      final usedCategoryIds = state.categoryBudgets
          .map((s) => s.budget.categoryId)
          .toSet();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fmt.monthYear(cubit.month), style: context.text.titleMedium),
          const SizedBox(height: Space.md),
          if (overall == null)
            SectionCard(
              title: 'Monthly budget',
              child: EmptyState(
                compact: true,
                icon: Icons.savings_rounded,
                title: 'Set a monthly spending budget',
                message: 'See how much you have left each month.',
                action: FilledButton.icon(
                  onPressed: () => _editBudget(context, null, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Set budget'),
                ),
              ),
            )
          else
            _BudgetCard(
              status: overall,
              title: 'Overall budget',
              onEdit: () => _editBudget(context, overall.budget, null),
            ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Category budgets',
                  style: context.text.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    _pickCategoryForBudget(context, usedCategoryIds),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (state.categoryBudgets.isEmpty)
            Text(
              'Optional: set limits for individual categories.',
              style: context.text.bodyMedium,
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 840 ? 2 : 1;
                final w = (c.maxWidth - (cols - 1) * Space.md) / cols;
                return Wrap(
                  spacing: Space.md,
                  runSpacing: Space.md,
                  children: [
                    for (final s in state.categoryBudgets)
                      SizedBox(
                        width: w,
                        child: _BudgetCard(
                          status: s,
                          category: categories.resolve(s.budget.categoryId!),
                          title: categories.resolve(s.budget.categoryId!).name,
                          onEdit: () => _editBudget(
                            context,
                            s.budget,
                            s.budget.categoryId,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: Space.xl),
          SectionCard(
            title: 'Budget alerts',
            subtitle: 'Notify me when spending reaches',
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final t in const [50, 80, 90, 100])
                  FilterChip(
                    label: Text('$t%'),
                    selected: prefs.budgetAlertThresholds.contains(t),
                    onSelected: (sel) {
                      final set = {...prefs.budgetAlertThresholds};
                      sel ? set.add(t) : set.remove(t);
                      context.read<PreferencesCubit>().update(
                        prefs.copyWith(
                          budgetAlertThresholds: set.toList()..sort(),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          Text(
            'Budgets and alerts are based on the expenses you record in '
            '${prefs.currencyCode}, not on your bank transactions. Each alert is sent '
            'once per month.',
            style: context.text.bodySmall,
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: ListView(
        padding: pagePadding(context),
        children: [PageBody(maxWidth: 960, child: content)],
      ),
    );
  }

  Future<void> _pickCategoryForBudget(
    BuildContext context,
    Set<String?> used,
  ) async {
    final categories = context
        .read<CategoriesCubit>()
        .state
        .active
        .where((c) => !used.contains(c.id))
        .toList();
    final picked = await showModalBottomSheet<ExpenseCategory>(
      context: context,
      // Above the navigation bar, which is drawn over tab content.
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xxl,
                  0,
                  Space.xxl,
                  Space.md,
                ),
                child: Text(
                  'Choose a category',
                  style: context.text.titleMedium,
                ),
              ),
              for (final c in categories)
                ListTile(
                  leading: CategoryAvatar(category: c, size: 36),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && context.mounted) {
      await _editBudget(context, null, picked.id);
    }
  }

  Future<void> _editBudget(
    BuildContext context,
    Budget? existing,
    String? categoryId,
  ) async {
    final cubit = context.read<BudgetsCubit>();
    final currencyCode =
        existing?.currencyCode ??
        context.read<PreferencesCubit>().preferences.currencyCode;
    final currency = Currencies.byCode(currencyCode);
    final controller = TextEditingController(
      text: existing == null
          ? ''
          : MoneyParser.toInputText(existing.amountMinor, currency),
    );
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(
            existing == null ? 'Set monthly budget' : 'Edit monthly budget',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: currency.minorDigits > 0,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Amount per month (${currency.code})',
              prefixText: '${currency.symbol} ',
              errorText: error,
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'delete'),
                child: Text(
                  'Remove',
                  style: TextStyle(color: dialogContext.colors.error),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final r = MoneyParser.parse(controller.text, currency);
                if (!r.isValid) {
                  setState(
                    () => error = MoneyParser.messageFor(r.error!, currency),
                  );
                  return;
                }
                Navigator.pop(dialogContext, 'save');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (result == null || !context.mounted) return;
    try {
      if (result == 'delete' && existing != null) {
        await cubit.repository.delete(existing.id);
      } else if (result == 'save') {
        final amount = MoneyParser.parse(text, currency).minorUnits!;
        await cubit.repository.save(
          Budget(
            id:
                existing?.id ??
                (categoryId == null
                    ? Budget.overallId
                    : Budget.idForCategory(categoryId)),
            amountMinor: amount,
            currencyCode: currencyCode,
            categoryId: categoryId,
          ),
        );
      }
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.status,
    required this.title,
    required this.onEdit,
    this.category,
  });

  final BudgetStatus status;
  final String title;
  final ExpenseCategory? category;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    final money = AppFormat.forLocale(fmt.locale, status.budget.currencyCode);
    final app = context.appColors;
    final (color, icon, label) = switch (status.level) {
      BudgetLevel.onTrack => (
        context.colors.primary,
        Icons.check_circle_outline_rounded,
        'On track',
      ),
      BudgetLevel.warning => (
        app.warning,
        Icons.warning_amber_rounded,
        'Approaching limit',
      ),
      BudgetLevel.exceeded => (
        context.colors.error,
        Icons.error_outline_rounded,
        'Over budget',
      ),
    };
    final remaining = status.remainingMinor;
    final pct = MoneyFormatter.percentFromBasisPoints(
      status.usedBasisPoints,
      locale: fmt.locale,
    );
    return Card(
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (category != null) ...[
                    CategoryAvatar(category: category!, size: 32),
                    const SizedBox(width: Space.md),
                  ],
                  Expanded(child: Text(title, style: context.text.titleSmall)),
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: Space.xs),
                  Text(label, style: context.text.labelMedium),
                  IconButton(
                    tooltip: 'Edit budget',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Semantics(
                label: '$pct of budget used',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: (status.usedBasisPoints / 10000).clamp(0.0, 1.0),
                    minHeight: 10,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.lg,
                runSpacing: Space.xs,
                children: [
                  Text(
                    'Spent ${money.amount(status.spentMinor)} of ${money.amount(status.budget.amountMinor)}',
                    style: context.text.bodyMedium!.tabular,
                  ),
                  Text(
                    remaining >= 0
                        ? '${money.amount(remaining)} left'
                        : '${money.amount(-remaining)} over',
                    style: context.text.labelLarge!.tabular.copyWith(
                      color: remaining >= 0
                          ? context.colors.onSurface
                          : context.colors.error,
                    ),
                  ),
                  Text(pct, style: context.text.bodySmall),
                ],
              ),
              if (status.budget.currencyCode != fmt.currencyCode)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    'This budget is in ${status.budget.currencyCode}; only '
                    '${status.budget.currencyCode} expenses count toward it.',
                    style: context.text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
