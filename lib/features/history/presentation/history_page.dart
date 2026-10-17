import 'dart:async';

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
import '../../../domain/models/expense_filter.dart';
import '../../../domain/services/expense_validator.dart';
import '../../../shared/widgets/expense_tile.dart';
import '../../expenses/presentation/expense_editor.dart';
import '../../export/export_dialog.dart';
import '../bloc/history_bloc.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.initialCategoryId});

  final String? initialCategoryId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => HistoryBloc(SessionScope.of(context).expenses)
        ..add(
          initialCategoryId == null
              ? const HistoryStarted()
              : HistoryFilterChanged(
                  ExpenseFilter(categoryId: initialCategoryId),
                ),
        ),
      child: const _HistoryView(),
    );
  }
}

class _HistoryView extends StatefulWidget {
  const _HistoryView();

  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _clearAll() {
    _debounce?.cancel();
    _search.clear();
    context.read<HistoryBloc>().add(const HistoryFiltersCleared());
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) context.read<HistoryBloc>().add(HistorySearchChanged(q));
    });
  }

  Future<void> _delete(Expense e) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this expense?',
      message:
          'It will be removed from your history and reports on every device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await SessionScope.of(context).expenses.delete(e.id);
      if (mounted) showMessage(context, 'Expense deleted');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HistoryBloc>().state;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: () => showExportDialog(context, filter: state.filter),
            icon: const Icon(Icons.download_rounded),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400 &&
              state.hasMore &&
              !state.loadingMore) {
            context.read<HistoryBloc>().add(const HistoryLoadMore());
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: pagePadding(context).left,
              ),
              sliver: SliverToBoxAdapter(
                child: PageBody(
                  child: _Filters(
                    search: _search,
                    onSearch: _onSearch,
                    onClearAll: _clearAll,
                    state: state,
                  ),
                ),
              ),
            ),
            ..._content(context, state, wide),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, HistoryState state, bool wide) {
    final pad = pagePadding(context);
    if (state.status == LoadStatus.loading && state.items.isEmpty) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
      ];
    }
    if (state.status == LoadStatus.failure && state.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message:
                state.error ??
                "We couldn't load your expenses. "
                    'Check your connection and try again.',
            onRetry: () =>
                context.read<HistoryBloc>().add(const HistoryRetried()),
          ),
        ),
      ];
    }
    final visible = state.visible;
    if (visible.isEmpty) {
      final filtered = state.filter.hasFilters || state.query.isNotEmpty;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: filtered
                ? Icons.filter_alt_off_rounded
                : Icons.receipt_long_rounded,
            title: filtered ? 'No matching expenses' : 'No expenses yet',
            message: filtered
                ? (state.hasMore
                      ? 'Only loaded expenses are searched. Load more to search further back.'
                      : 'Try changing your search or filters.')
                : 'Expenses you record will appear here.',
            action: filtered
                ? (state.hasMore
                      ? OutlinedButton(
                          onPressed: () => context.read<HistoryBloc>().add(
                            const HistoryLoadMore(),
                          ),
                          child: const Text('Load more'),
                        )
                      : FilledButton.tonalIcon(
                          onPressed: _clearAll,
                          icon: const Icon(Icons.filter_alt_off_rounded),
                          label: const Text('Clear filters'),
                        ))
                : FilledButton.icon(
                    onPressed: () => openExpenseEditor(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Your First Expense'),
                  ),
          ),
        ),
      ];
    }

    final fmt = AppFormat.of(context);
    final categories = context.watch<CategoriesCubit>().state;
    final today = LocalDate.today(context.read<AppDependencies>().now);
    final footer = Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Center(
        child: state.loadingMore
            ? const CircularProgressIndicator()
            : state.hasMore
            ? OutlinedButton(
                onPressed: () =>
                    context.read<HistoryBloc>().add(const HistoryLoadMore()),
                child: const Text('Load more'),
              )
            : Text('${visible.length} expenses', style: context.text.bodySmall),
      ),
    );

    if (wide) {
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            pad.left,
            Space.md,
            pad.right,
            pad.bottom,
          ),
          sliver: SliverToBoxAdapter(
            child: PageBody(
              child: Card(
                child: Column(
                  children: [
                    const _TableHeader(),
                    const Divider(),
                    for (final e in visible)
                      _TableRow(
                        key: ValueKey(e.id),
                        expense: e,
                        format: fmt,
                        today: today,
                        onEdit: () =>
                            openExpenseEditor(context, expenseId: e.id),
                        onDelete: () => _delete(e),
                      ),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    // Group by date (list is already sorted by date).
    final groups = <LocalDate, List<Expense>>{};
    for (final e in visible) {
      groups.putIfAbsent(e.date, () => []).add(e);
    }
    final keys = groups.keys.toList();
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad.left, Space.sm, pad.right, 0),
        sliver: SliverList.builder(
          itemCount: keys.length,
          itemBuilder: (context, i) {
            final day = keys[i];
            final items = groups[day]!;
            final total = items
                .where((e) => e.currencyCode == fmt.currencyCode)
                .fold<int>(0, (s, e) => s + e.amountMinor);
            final group = Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: PageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.xs,
                        Space.sm,
                        Space.xs,
                        Space.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              fmt.relativeDay(day, today),
                              style: context.text.titleSmall,
                            ),
                          ),
                          Text(
                            fmt.amount(total),
                            style: context.text.labelLarge!.tabular,
                          ),
                        ],
                      ),
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.xs),
                        child: Column(
                          children: [
                            for (final e in items)
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
                    ),
                  ],
                ),
              ),
            );
            // Animate only the first screenful so long scrolls stay snappy.
            return i < 6
                ? AppearIn(key: ValueKey(day), index: i, child: group)
                : KeyedSubtree(key: ValueKey(day), child: group);
          },
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(bottom: pad.bottom),
          child: footer,
        ),
      ),
    ];
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.search,
    required this.onSearch,
    required this.onClearAll,
    required this.state,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearAll;
  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<HistoryBloc>();
    final fmt = AppFormat.of(context);
    final categories = context.watch<CategoriesCubit>().state;
    final f = state.filter;
    final today = LocalDate.today(context.read<AppDependencies>().now);

    void apply(ExpenseFilter next) => bloc.add(HistoryFilterChanged(next));

    Future<void> pickRange() async {
      final r = await showDateRangePicker(
        context: context,
        firstDate: ExpenseValidator.earliestDate.toDateTime(),
        lastDate: today.toDateTime(),
        initialDateRange: f.range == null
            ? null
            : DateTimeRange(
                start: f.range!.start.toDateTime(),
                end: f.range!.end.toDateTime(),
              ),
      );
      if (r != null) {
        apply(
          f.copyWith(
            range: () => DateRange(
              LocalDate.fromDateTime(r.start),
              LocalDate.fromDateTime(r.end),
            ),
          ),
        );
      }
    }

    Future<void> pickCategory() async {
      final picked = await _showPicker<String>(
        context,
        title: 'Filter by category',
        allLabel: 'All categories',
        selected: f.categoryId,
        options: [
          for (final c in categories.categories)
            _PickerOption(
              c.id,
              c.name,
              leading: CategoryAvatar(category: c, size: 36),
            ),
        ],
      );
      if (picked != null) apply(f.copyWith(categoryId: () => picked.value));
    }

    Future<void> pickPayment() async {
      final picked = await _showPicker<PaymentMethod>(
        context,
        title: 'Filter by payment method',
        allLabel: 'Any payment method',
        selected: f.paymentMethod,
        options: [
          for (final m in PaymentMethod.values)
            _PickerOption(
              m,
              m.label,
              leading: const IconBadge(icon: Icons.payments_rounded, size: 36),
            ),
        ],
      );
      if (picked != null) apply(f.copyWith(paymentMethod: () => picked.value));
    }

    final active = state.activeFilterCount;
    final hasFilters = active > 0;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: search,
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search notes and merchants',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        search.clear();
                        bloc.add(const HistorySearchChanged(''));
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: Space.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: hasFilters
                      ? Padding(
                          padding: const EdgeInsets.only(right: Space.sm),
                          child: ActionChip(
                            avatar: Icon(
                              Icons.filter_alt_off_rounded,
                              size: 18,
                              color: context.colors.onErrorContainer,
                            ),
                            label: Text('Clear filters ($active)'),
                            tooltip:
                                '$active active filter'
                                '${active == 1 ? '' : 's'}. Tap to clear all.',
                            labelStyle: TextStyle(
                              color: context.colors.onErrorContainer,
                            ),
                            backgroundColor: context.colors.errorContainer,
                            side: BorderSide.none,
                            onPressed: onClearAll,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                _FilterChip(
                  icon: Icons.date_range_rounded,
                  label: f.range == null ? 'Any date' : fmt.range(f.range!),
                  active: f.range != null,
                  onTap: pickRange,
                  onClear: () => apply(f.copyWith(range: () => null)),
                ),
                const SizedBox(width: Space.sm),
                _FilterChip(
                  icon: Icons.category_rounded,
                  label: f.categoryId == null
                      ? 'All categories'
                      : categories.resolve(f.categoryId!).name,
                  active: f.categoryId != null,
                  onTap: pickCategory,
                  onClear: () => apply(f.copyWith(categoryId: () => null)),
                ),
                const SizedBox(width: Space.sm),
                _FilterChip(
                  icon: Icons.payments_rounded,
                  label: f.paymentMethod?.label ?? 'Any payment',
                  active: f.paymentMethod != null,
                  onTap: pickPayment,
                  onClear: () => apply(f.copyWith(paymentMethod: () => null)),
                ),
                const SizedBox(width: Space.sm),
                ActionChip(
                  avatar: Icon(
                    f.newestFirst
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 18,
                  ),
                  label: Text(f.newestFirst ? 'Newest first' : 'Oldest first'),
                  tooltip: 'Change sort order',
                  onPressed: () =>
                      apply(f.copyWith(newestFirst: !f.newestFirst)),
                ),
              ],
            ),
          ),
          if (state.query.isNotEmpty && state.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Searching ${state.items.length} loaded expenses. Scroll to load more.',
                style: context.text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip for one filter: tap to change it, ✕ to remove it when active.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: active,
      showCheckmark: false,
      onPressed: onTap,
      onDeleted: active ? onClear : null,
      deleteButtonTooltipMessage: 'Remove filter',
    );
  }
}

class _PickerOption<T> {
  const _PickerOption(this.value, this.label, {this.leading});
  final T value;
  final String label;
  final Widget? leading;
}

/// Wraps the picked value so "All" (null) can be told apart from "dismissed".
class _Picked<T> {
  const _Picked(this.value);
  final T? value;
}

Future<_Picked<T>?> _showPicker<T>(
  BuildContext context, {
  required String title,
  required String allLabel,
  required T? selected,
  required List<_PickerOption<T>> options,
}) {
  return showModalBottomSheet<_Picked<T>>(
    context: context,
    // Above the navigation bar, which is drawn over tab content.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                0,
                Space.xl,
                Space.sm,
              ),
              child: Text(title, style: context.text.titleMedium),
            ),
            ListTile(
              leading: const IconBadge(
                icon: Icons.select_all_rounded,
                size: 36,
              ),
              title: Text(allLabel),
              trailing: selected == null
                  ? Icon(Icons.check_rounded, color: context.colors.primary)
                  : null,
              selected: selected == null,
              onTap: () => Navigator.pop(context, _Picked<T>(null)),
            ),
            for (final o in options)
              ListTile(
                leading: o.leading,
                title: Text(o.label),
                trailing: o.value == selected
                    ? Icon(Icons.check_rounded, color: context.colors.primary)
                    : null,
                selected: o.value == selected,
                onTap: () => Navigator.pop(context, _Picked<T>(o.value)),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text('Date', style: style)),
          Expanded(flex: 3, child: Text('Category', style: style)),
          Expanded(flex: 4, child: Text('Description', style: style)),
          Expanded(flex: 2, child: Text('Payment', style: style)),
          SizedBox(
            width: 130,
            child: Text('Amount', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    super.key,
    required this.expense,
    required this.format,
    required this.today,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final AppFormat format;
  final LocalDate today;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final category = context.select(
      (CategoriesCubit c) => c.state.resolve(expense.categoryId),
    );
    final e = expense;
    final amount = e.currencyCode == format.currencyCode
        ? format.amount(e.amountMinor)
        : AppFormat.forLocale(
            format.locale,
            e.currencyCode,
          ).amount(e.amountMinor);
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(
                format.relativeDay(e.date, today),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CategoryAvatar(category: category, size: 32),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                e.description.isEmpty ? '—' : e.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                e.paymentMethod?.label ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 130,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (e.hasPendingWrites) ...[
                    const PendingSyncIcon(),
                    const SizedBox(width: Space.xs),
                  ],
                  Flexible(
                    child: Text(
                      amount,
                      style: context.text.titleSmall!.tabular,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 96,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: context.colors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
