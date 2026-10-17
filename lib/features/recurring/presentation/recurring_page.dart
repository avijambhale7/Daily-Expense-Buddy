import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/money/money_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/recurring_expense.dart';
import '../../../domain/repositories/repositories.dart';
import '../../premium/premium_gate.dart';

/// Premium: rent, subscriptions, EMIs and other repeating expenses.
class RecurringPage extends StatelessWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context) {
    final premium = hasPremium(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring expenses')),
      floatingActionButton: premium
          ? FloatingActionButton.extended(
              heroTag: 'add-recurring',
              onPressed: () => showRecurringEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add recurring'),
            )
          : null,
      body: const PremiumGate(
        feature: 'Recurring expenses',
        description:
            'Add rent, subscriptions, bills and EMIs once – they are recorded '
            'automatically every week, month or year.',
        icon: Icons.event_repeat_rounded,
        child: _RecurringList(),
      ),
    );
  }
}

class _RecurringList extends StatefulWidget {
  const _RecurringList();

  @override
  State<_RecurringList> createState() => _RecurringListState();
}

class _RecurringListState extends State<_RecurringList> {
  late final Stream<List<RecurringExpense>> _stream = SessionScope.of(context)
      .recurring
      .watchAll();

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    final categories = context.watch<CategoriesCubit>().state;
    final today = LocalDate.today(context.read<AppDependencies>().now);
    return StreamBuilder<List<RecurringExpense>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return ErrorView(
            message: e is AppFailure
                ? e.message
                : "Couldn't load recurring expenses.",
          );
        }
        final list = snap.data;
        if (list == null) return const LoadingView();
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.event_repeat_rounded,
            title: 'No recurring expenses yet',
            message:
                'Add one for rent, Netflix, phone bills or an EMI and it will '
                'be recorded on its date automatically.',
            action: FilledButton.icon(
              onPressed: () => showRecurringEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add recurring expense'),
            ),
          );
        }
        final monthly = list
            .where(
              (t) =>
                  t.active &&
                  t.frequency == RecurrenceFrequency.monthly &&
                  t.currencyCode == fmt.currencyCode,
            )
            .fold<int>(0, (sum, t) => sum + t.amountMinor);
        return ListView(
          padding: pagePadding(context),
          children: [
            PageBody(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (monthly > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: InfoBanner(
                        icon: Icons.calendar_month_rounded,
                        message:
                            '${fmt.amount(monthly)} goes out every month '
                            'in fixed expenses.',
                      ),
                    ),
                  Card(
                    child: Column(
                      children: [
                        for (final t in list)
                          Builder(
                            builder: (context) {
                              final c = categories.resolve(t.categoryId);
                              final next = t.nextDate(today);
                              final money = t.currencyCode == fmt.currencyCode
                                  ? fmt
                                  : AppFormat.forLocale(
                                      fmt.locale,
                                      t.currencyCode,
                                    );
                              return ListTile(
                                leading: CategoryAvatar(category: c),
                                title: Text(
                                  t.merchant ?? c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    t.frequency.label,
                                    if (!t.active)
                                      'Paused'
                                    else if (next != null)
                                      'Next ${fmt.relativeDay(next, today)}',
                                  ].join(' · '),
                                ),
                                trailing: Text(
                                  money.amount(t.amountMinor),
                                  style: context.text.titleSmall!.tabular
                                      .copyWith(
                                        color: t.active
                                            ? null
                                            : context.colors.onSurfaceVariant,
                                      ),
                                ),
                                onTap: () =>
                                    showRecurringEditor(context, template: t),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    'Expenses are added when the app is opened on or after '
                    'each date. Missed dates are filled in automatically.',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showRecurringEditor(
  BuildContext context, {
  RecurringExpense? template,
}) {
  final session = SessionScope.of(context);
  final today = LocalDate.today(context.read<AppDependencies>().now);
  final categories = context.read<CategoriesCubit>().state;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => BlocProvider.value(
      value: context.read<CategoriesCubit>(),
      child: _RecurringEditor(
        repository: session.recurring,
        template: template,
        // Read while building the sheet, not in the tap handler.
        format: AppFormat.of(sheet),
        today: today,
        defaultCategory: categories.active.isEmpty
            ? 'other'
            : categories.active.first.id,
      ),
    ),
  );
}

class _RecurringEditor extends StatefulWidget {
  const _RecurringEditor({
    required this.repository,
    required this.template,
    required this.format,
    required this.today,
    required this.defaultCategory,
  });

  final RecurringRepository repository;
  final RecurringExpense? template;
  final AppFormat format;
  final LocalDate today;
  final String defaultCategory;

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  late final RecurringExpense? _t = widget.template;
  late final _amount = TextEditingController(
    text: _t == null
        ? ''
        : plainAmount(_t.amountMinor, widget.format.currency.minorDigits),
  );
  late final _name = TextEditingController(text: _t?.merchant ?? '');
  late String _category = _t?.categoryId ?? widget.defaultCategory;
  late RecurrenceFrequency _frequency =
      _t?.frequency ?? RecurrenceFrequency.monthly;
  late LocalDate _start = _t?.startDate ?? widget.today;
  late PaymentMethod? _payment = _t?.paymentMethod;
  late bool _active = _t?.active ?? true;
  String? _amountError;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.toDateTime(),
      firstDate: widget.today.addDays(-366).toDateTime(),
      lastDate: widget.today.addDays(3650).toDateTime(),
      helpText: 'First date',
    );
    if (picked != null) setState(() => _start = LocalDate.fromDateTime(picked));
  }

  Future<void> _save() async {
    final currency = widget.format.currency;
    final parsed = MoneyParser.parse(_amount.text, currency);
    setState(
      () => _amountError = parsed.minorUnits == null
          ? MoneyParser.messageFor(parsed.error!, currency)
          : null,
    );
    if (_amountError != null) return;
    final isNew = _t == null;
    final base =
        _t ??
        RecurringExpense(
          id: widget.repository.newId(),
          amountMinor: parsed.minorUnits!,
          currencyCode: widget.format.currencyCode,
          categoryId: _category,
          frequency: _frequency,
          startDate: _start,
        );
    final name = _name.text.trim();
    final changedSchedule =
        _t != null && (_t.startDate != _start || _t.frequency != _frequency);
    final next = base.copyWith(
      amountMinor: parsed.minorUnits,
      categoryId: _category,
      frequency: _frequency,
      startDate: _start,
      merchant: () => name.isEmpty ? null : name,
      paymentMethod: () => _payment,
      active: _active,
      // A new schedule starts fresh, but never re-adds dates before today.
      lastPostedDate: changedSchedule
          ? () => _start <= widget.today ? widget.today.addDays(-1) : null
          : null,
    );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.save(next, isNew: isNew);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(isNew ? 'Recurring expense added' : 'Changes saved'),
        ),
      );
    } on AppFailure catch (f) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this recurring expense?',
      message:
          'No more expenses will be added. Expenses already recorded stay in '
          'your history.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    try {
      await widget.repository.delete(_t!.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Recurring expense deleted')),
      );
    } on AppFailure catch (f) {
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CategoriesCubit>().state;
    final currency = widget.format.currency;
    final options = [
      ...categories.active,
      if (!categories.active.any((c) => c.id == _category))
        categories.resolve(_category),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        0,
        Space.xl,
        MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t == null ? 'New recurring expense' : 'Edit recurring expense',
              style: context.text.titleLarge,
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _amount,
              autofocus: _t == null,
              keyboardType: TextInputType.numberWithOptions(
                decimal: currency.minorDigits > 0,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${currency.symbol} ',
                errorText: _amountError,
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _name,
              maxLength: Expense.maxMerchantLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'What is it?',
                hintText: 'e.g. Rent, Netflix, Car EMI',
                counterText: '',
              ),
            ),
            const SizedBox(height: Space.md),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in options)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        CategoryAvatar(category: c, size: 24),
                        const SizedBox(width: Space.sm),
                        Text(c.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: Space.lg),
            Text('How often', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            SegmentedButton<RecurrenceFrequency>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: RecurrenceFrequency.weekly,
                  label: Text('Weekly'),
                ),
                ButtonSegment(
                  value: RecurrenceFrequency.monthly,
                  label: Text('Monthly'),
                ),
                ButtonSegment(
                  value: RecurrenceFrequency.yearly,
                  label: Text('Yearly'),
                ),
              ],
              selected: {_frequency},
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
            const SizedBox(height: Space.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('First date'),
              subtitle: Text(widget.format.date(_start)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _pickStart,
            ),
            DropdownButtonFormField<PaymentMethod?>(
              initialValue: _payment,
              decoration: const InputDecoration(
                labelText: 'Payment method (optional)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not set')),
                for (final m in PaymentMethod.values)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => _payment = v),
            ),
            if (_t != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Pause to stop adding new expenses'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_t == null ? 'Save recurring expense' : 'Save'),
            ),
            if (_t != null) ...[
              const SizedBox(height: Space.sm),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.error,
                ),
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
