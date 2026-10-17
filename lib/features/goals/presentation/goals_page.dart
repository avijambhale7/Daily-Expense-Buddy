import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/money/money_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/savings_goal.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../services/sound/sound_effects.dart';
import '../../premium/premium_gate.dart';

/// Premium: savings targets with progress.
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final premium = hasPremium(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: premium
          ? FloatingActionButton.extended(
              heroTag: 'add-goal',
              onPressed: () => showGoalEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New goal'),
            )
          : null,
      body: const PremiumGate(
        feature: 'Savings goals',
        description:
            'Set a target like "₹10,000 for Diwali", add money as you save '
            'and see how much to put aside each day.',
        icon: Icons.savings_rounded,
        child: _GoalList(),
      ),
    );
  }
}

class _GoalList extends StatefulWidget {
  const _GoalList();

  @override
  State<_GoalList> createState() => _GoalListState();
}

class _GoalListState extends State<_GoalList> {
  late final Stream<List<SavingsGoal>> _stream = SessionScope.of(context).goals
      .watchAll();

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    final today = LocalDate.today(context.read<AppDependencies>().now);
    return StreamBuilder<List<SavingsGoal>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return ErrorView(
            message: e is AppFailure ? e.message : "Couldn't load your goals.",
          );
        }
        final goals = snap.data;
        if (goals == null) return const LoadingView();
        if (goals.isEmpty) {
          return EmptyState(
            icon: Icons.savings_rounded,
            title: 'No savings goals yet',
            message: 'Create a goal for a trip, a new phone or a festival.',
            action: FilledButton.icon(
              onPressed: () => showGoalEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create a goal'),
            ),
          );
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            PageBody(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in goals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: _GoalCard(goal: g, format: fmt, today: today),
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

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.format,
    required this.today,
  });

  final SavingsGoal goal;
  final AppFormat format;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    final money = g.currencyCode == format.currencyCode
        ? format
        : AppFormat.forLocale(format.locale, g.currencyCode);
    final color = g.reached
        ? context.appColors.success
        : context.colors.primary;
    final perDay = g.perDayMinor(today);
    return Card(
      child: InkWell(
        onTap: () => showGoalEditor(context, goal: g),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: g.reached
                        ? Icons.emoji_events_rounded
                        : Icons.savings_rounded,
                    color: color,
                    size: 40,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: context.text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          g.reached
                              ? 'Goal reached!'
                              : g.targetDate == null
                              ? '${money.amount(g.remainingMinor)} to go'
                              : '${money.amount(g.remainingMinor)} to go · '
                                    'by ${format.date(g.targetDate!)}',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(g.progress * 100).round()}%',
                    style: context.text.titleMedium!.tabular.copyWith(
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: g.progress,
                  minHeight: 10,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                  semanticsLabel: '${(g.progress * 100).round()}% saved',
                ),
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${money.amount(g.savedMinor)} of '
                      '${money.amount(g.targetMinor)}',
                      style: context.text.bodyMedium!.tabular,
                    ),
                  ),
                  if (perDay != null)
                    Text(
                      '${money.amount(perDay)}/day',
                      style: context.text.labelMedium,
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: g.savedMinor == 0
                          ? null
                          : () => _change(context, add: false),
                      child: const Text('Take out'),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _change(context, add: true),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add money'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _change(BuildContext context, {required bool add}) async {
    final currency = format.currency;
    // No controller: it would be disposed while the dialog animates out.
    var input = '';
    final minor = await showDialog<int>(
      context: context,
      builder: (dialog) {
        String? error;
        return StatefulBuilder(
          builder: (dialog, setDialog) => AlertDialog(
            title: Text(add ? 'Add to ${goal.name}' : 'Take out money'),
            content: TextField(
              onChanged: (v) => input = v,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(
                decimal: currency.minorDigits > 0,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                prefixText: '${currency.symbol} ',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final r = MoneyParser.parse(input, currency);
                  if (r.minorUnits == null) {
                    setDialog(
                      () => error = MoneyParser.messageFor(r.error!, currency),
                    );
                    return;
                  }
                  if (!add && r.minorUnits! > goal.savedMinor) {
                    setDialog(
                      () => error =
                          'Only ${format.amount(goal.savedMinor)} is saved.',
                    );
                    return;
                  }
                  Navigator.pop(dialog, r.minorUnits);
                },
                child: Text(add ? 'Add' : 'Take out'),
              ),
            ],
          ),
        );
      },
    );
    if (minor == null || !context.mounted) return;
    final repo = SessionScope.of(context).goals;
    final sounds = context.read<AppDependencies>().soundEffects;
    final next = goal.withChange(add ? minor : -minor);
    try {
      await repo.save(next, isNew: false);
      if (next.reached && !goal.reached) {
        await sounds.play(Sfx.celebrate);
        if (context.mounted) showMessage(context, 'You reached your goal!');
      }
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }
}

Future<void> showGoalEditor(BuildContext context, {SavingsGoal? goal}) {
  final session = SessionScope.of(context);
  final today = LocalDate.today(context.read<AppDependencies>().now);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    // The format is read while building the sheet, not in the tap handler.
    builder: (sheet) => _GoalEditor(
      repository: session.goals,
      goal: goal,
      format: AppFormat.of(sheet),
      today: today,
    ),
  );
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({
    required this.repository,
    required this.goal,
    required this.format,
    required this.today,
  });

  final GoalRepository repository;
  final SavingsGoal? goal;
  final AppFormat format;
  final LocalDate today;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final SavingsGoal? _g = widget.goal;
  late final _name = TextEditingController(text: _g?.name ?? '');
  late final _target = TextEditingController(
    text: _g == null
        ? ''
        : plainAmount(_g.targetMinor, widget.format.currency.minorDigits),
  );
  late LocalDate? _date = _g?.targetDate;
  String? _nameError;
  String? _targetError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (_date ?? widget.today.addDays(30)).toDateTime(),
      firstDate: widget.today.toDateTime(),
      lastDate: widget.today.addDays(3650).toDateTime(),
      helpText: 'Target date',
    );
    if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
  }

  Future<void> _save() async {
    final currency = widget.format.currency;
    final name = _name.text.trim();
    final r = MoneyParser.parse(_target.text, currency);
    setState(() {
      _nameError = name.isEmpty ? 'Give your goal a name' : null;
      _targetError = r.minorUnits == null
          ? MoneyParser.messageFor(r.error!, currency)
          : null;
    });
    if (_nameError != null || _targetError != null) return;
    final isNew = _g == null;
    final goal =
        (_g ??
                SavingsGoal(
                  id: widget.repository.newId(),
                  name: name,
                  targetMinor: r.minorUnits!,
                  currencyCode: widget.format.currencyCode,
                ))
            .copyWith(
              name: name.length > 60 ? name.substring(0, 60) : name,
              targetMinor: r.minorUnits,
              targetDate: () => _date,
            );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.save(goal, isNew: isNew);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(isNew ? 'Goal created' : 'Goal updated')),
      );
    } on AppFailure catch (f) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this goal?',
      message: 'The goal and its saved amount will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    try {
      await widget.repository.delete(_g!.id);
      messenger.showSnackBar(const SnackBar(content: Text('Goal deleted')));
    } on AppFailure catch (f) {
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.format.currency;
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
              _g == null ? 'New savings goal' : 'Edit goal',
              style: context.text.titleLarge,
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _name,
              autofocus: _g == null,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Goal name',
                hintText: 'e.g. Goa trip, New phone',
                errorText: _nameError,
                counterText: '',
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _target,
              keyboardType: TextInputType.numberWithOptions(
                decimal: currency.minorDigits > 0,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: InputDecoration(
                labelText: 'Target amount',
                prefixText: '${currency.symbol} ',
                errorText: _targetError,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_rounded),
              title: const Text('Target date (optional)'),
              subtitle: Text(
                _date == null ? 'No deadline' : widget.format.date(_date!),
              ),
              trailing: _date == null
                  ? const Icon(Icons.edit_calendar_rounded)
                  : IconButton(
                      tooltip: 'Remove date',
                      onPressed: () => setState(() => _date = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
              onTap: _pickDate,
            ),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(_g == null ? 'Create goal' : 'Save'),
            ),
            if (_g != null) ...[
              const SizedBox(height: Space.sm),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.error,
                ),
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete goal'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
