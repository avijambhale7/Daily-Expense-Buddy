import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/loan.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../services/sound/sound_effects.dart';

/// Colour used for each direction: green for money coming back to the user,
/// orange for money the user has to return.
Color loanColor(BuildContext context, LoanDirection d) =>
    d == LoanDirection.lent
    ? context.appColors.success
    : context.appColors.warning;

class LoansPage extends StatefulWidget {
  const LoansPage({super.key});

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  late final Stream<List<Loan>> _loans = SessionScope.of(context).loans
      .watchAll();
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    final today = LocalDate.today(context.read<AppDependencies>().now);
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-loan',
        onPressed: () => showLoanEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add loan'),
      ),
      body: StreamBuilder<List<Loan>>(
        stream: _loans,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(
              message: e is AppFailure ? e.message : 'Could not load loans.',
            );
          }
          final loans = snap.data;
          if (loans == null) return const LoadingView();
          final totals = LoanTotals.of(loans, fmt.currencyCode, today);
          final shown = loans.where((l) => l.settled == _showSettled).toList()
            ..sort((a, b) {
              // Overdue first, then by due date, then newest.
              final ao = a.isOverdue(today) ? 0 : 1;
              final bo = b.isOverdue(today) ? 0 : 1;
              if (ao != bo) return ao - bo;
              return b.date.compareTo(a.date);
            });
          final pad = pagePadding(context);
          return ListView(
            padding: pad,
            children: [
              PageBody(
                maxWidth: Breakpoints.formMaxWidth + 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _TotalCard(
                            label: "You'll get",
                            amount: fmt.amount(totals.toReceiveMinor),
                            icon: Icons.south_west_rounded,
                            color: loanColor(context, LoanDirection.lent),
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: _TotalCard(
                            label: 'You owe',
                            amount: fmt.amount(totals.toPayMinor),
                            icon: Icons.north_east_rounded,
                            color: loanColor(context, LoanDirection.borrowed),
                          ),
                        ),
                      ],
                    ),
                    if (totals.overdueCount > 0) ...[
                      const SizedBox(height: Space.md),
                      InfoBanner(
                        icon: Icons.schedule_rounded,
                        tone: BannerTone.warning,
                        message:
                            '${totals.overdueCount} loan${totals.overdueCount == 1 ? ' is' : 's are'} past the due date.',
                      ),
                    ],
                    const SizedBox(height: Space.lg),
                    SegmentedButton<bool>(
                      expandedInsets: EdgeInsets.zero,
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text('Active (${totals.openCount})'),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                            'Settled (${loans.where((l) => l.settled).length})',
                          ),
                        ),
                      ],
                      selected: {_showSettled},
                      onSelectionChanged: (s) =>
                          setState(() => _showSettled = s.first),
                    ),
                    const SizedBox(height: Space.lg),
                    if (shown.isEmpty)
                      EmptyState(
                        compact: true,
                        icon: _showSettled
                            ? Icons.task_alt_rounded
                            : Icons.handshake_rounded,
                        title: _showSettled
                            ? 'No settled loans yet'
                            : 'No active loans',
                        message: _showSettled
                            ? 'Loans you mark as settled will move here.'
                            : 'Keep track of money you lend to or borrow '
                                  'from friends and family.',
                        action: _showSettled
                            ? null
                            : FilledButton.icon(
                                onPressed: () => showLoanEditor(context),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add your first loan'),
                              ),
                      )
                    else
                      for (var i = 0; i < shown.length; i++)
                        AppearIn(
                          key: ValueKey(shown[i].id),
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: Space.md),
                            child: LoanTile(
                              loan: shown[i],
                              format: fmt,
                              today: today,
                              onTap: () => showLoanDetails(context, shown[i]),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg + 4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: color, size: 34),
            const SizedBox(height: Space.sm),
            Text(label, style: context.text.labelLarge),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: context.text.titleLarge!.tabular.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoanTile extends StatelessWidget {
  const LoanTile({
    super.key,
    required this.loan,
    required this.format,
    required this.today,
    this.onTap,
  });

  final Loan loan;
  final AppFormat format;
  final LocalDate today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = loan;
    final color = loanColor(context, l.direction);
    final c = context.colors;
    final money = l.currencyCode == format.currencyCode
        ? format
        : AppFormat.forLocale(format.locale, l.currencyCode);
    final overdue = l.isOverdue(today);
    final subtitle = [
      l.direction == LoanDirection.lent ? 'You lent' : 'You borrowed',
      format.relativeDay(l.date, today),
      if (l.dueDate != null && !l.settled)
        'Due ${format.relativeDay(l.dueDate!, today)}',
    ].join(' · ');
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: color.withValues(alpha: 0.18),
                    foregroundColor: color,
                    child: Text(
                      _initials(l.personName),
                      style: context.text.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.personName,
                          style: context.text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: context.text.bodySmall?.copyWith(
                            color: overdue ? c.error : c.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money.amount(
                          l.settled ? l.amountMinor : l.outstandingMinor,
                        ),
                        style: context.text.titleMedium!.tabular.copyWith(
                          color: l.settled ? c.onSurfaceVariant : color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (overdue)
                        _Badge(label: 'Overdue', color: c.error)
                      else if (l.settled)
                        _Badge(
                          label: 'Settled',
                          color: context.appColors.success,
                        )
                      else if (l.repaidMinor > 0)
                        Text(
                          'of ${money.amount(l.amountMinor)}',
                          style: context.text.labelSmall,
                        ),
                    ],
                  ),
                ],
              ),
              if (!l.settled && l.repaidMinor > 0) ...[
                const SizedBox(height: Space.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: l.progress),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.15),
                      semanticsLabel:
                          '${(l.progress * 100).round()}% paid back',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Text(
      label,
      style: context.text.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.take(2).map((p) => p.characters.first.toUpperCase());
  final s = letters.join();
  return s.isEmpty ? '?' : s;
}

// ---------------------------------------------------------------------------
// Details sheet

Future<void> showLoanDetails(BuildContext context, Loan loan) {
  final repo = SessionScope.of(context).loans;
  return showModalBottomSheet<void>(
    context: context,
    // Above the navigation bar, which is drawn over tab content.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => _LoanDetails(loan: loan, repository: repo),
  );
}

class _LoanDetails extends StatelessWidget {
  const _LoanDetails({required this.loan, required this.repository});

  final Loan loan;
  final LoanRepository repository;

  Future<void> _save(BuildContext context, Loan updated, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final sounds = context.read<AppDependencies>().soundEffects;
    Navigator.pop(context);
    try {
      await repository.update(updated);
      if (updated.settled && !loan.settled) {
        unawaited(sounds.play(Sfx.celebrate));
      }
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on AppFailure catch (f) {
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  Future<void> _repay(BuildContext context, AppFormat fmt) async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _RepaymentDialog(loan: loan, format: fmt),
    );
    if (amount == null || !context.mounted) return;
    final updated = loan.withRepayment(amount);
    await _save(
      context,
      updated,
      updated.settled ? 'Fully repaid – loan settled' : 'Repayment recorded',
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this loan?',
      message: 'The record for ${loan.personName} will be removed everywhere.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    try {
      await repository.delete(loan.id);
      messenger.showSnackBar(const SnackBar(content: Text('Loan deleted')));
    } on AppFailure catch (f) {
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    final money = loan.currencyCode == fmt.currencyCode
        ? fmt
        : AppFormat.forLocale(fmt.locale, loan.currencyCode);
    final today = LocalDate.today(context.read<AppDependencies>().now);
    final color = loanColor(context, loan.direction);
    final lent = loan.direction == LoanDirection.lent;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          Text(value, style: context.text.titleSmall!.tabular),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: lent
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  color: color,
                  size: 44,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.personName, style: context.text.titleLarge),
                      Text(
                        lent
                            ? '${loan.personName} owes you'
                            : 'You owe ${loan.personName}',
                        style: context.text.bodyMedium?.copyWith(color: color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            Center(
              child: Text(
                money.amount(loan.outstandingMinor),
                style: context.text.displaySmall!.tabular.copyWith(
                  color: loan.settled ? context.colors.onSurfaceVariant : color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Center(
              child: Text(
                loan.settled ? 'Settled' : 'still to ${lent ? 'get' : 'pay'}',
                style: context.text.labelLarge,
              ),
            ),
            const SizedBox(height: Space.lg),
            row('Original amount', money.amount(loan.amountMinor)),
            row('Paid back', money.amount(loan.repaidMinor)),
            row('Date', fmt.date(loan.date)),
            if (loan.dueDate != null)
              row(
                loan.isOverdue(today) ? 'Due (overdue)' : 'Due',
                fmt.date(loan.dueDate!),
              ),
            if (loan.note != null && loan.note!.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(loan.note!, style: context.text.bodyMedium),
            ],
            const SizedBox(height: Space.xl),
            if (!loan.settled) ...[
              FilledButton.icon(
                onPressed: () => _repay(context, money),
                icon: const Icon(Icons.payments_rounded),
                label: Text(lent ? 'Record money received' : 'Record payment'),
              ),
              const SizedBox(height: Space.sm),
              FilledButton.tonalIcon(
                onPressed: () => _save(
                  context,
                  loan.copyWith(repaidMinor: loan.amountMinor, settled: true),
                  'Loan settled',
                ),
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('Mark as settled'),
              ),
            ] else
              FilledButton.tonalIcon(
                onPressed: () => _save(
                  context,
                  loan.copyWith(settled: false),
                  'Loan reopened',
                ),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Reopen'),
              ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showLoanEditor(context, loan: loan);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                    ),
                    onPressed: () => _delete(context),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RepaymentDialog extends StatefulWidget {
  const _RepaymentDialog({required this.loan, required this.format});

  final Loan loan;
  final AppFormat format;

  @override
  State<_RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends State<_RepaymentDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final currency = widget.format.currency;
    final r = MoneyParser.parse(_ctrl.text, currency);
    if (r.minorUnits == null) {
      setState(() => _error = MoneyParser.messageFor(r.error!, currency));
      return;
    }
    if (r.minorUnits! > widget.loan.outstandingMinor) {
      setState(
        () => _error =
            'That is more than the ${widget.format.amount(widget.loan.outstandingMinor)} still owed.',
      );
      return;
    }
    Navigator.pop(context, r.minorUnits);
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.format.currency;
    return AlertDialog(
      title: const Text('How much was paid back?'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: currency.minorDigits > 0,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          LengthLimitingTextInputFormatter(20),
        ],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          prefixText: '${currency.symbol} ',
          helperText:
              'Still owed: ${widget.format.amount(widget.loan.outstandingMinor)}',
          errorText: _error,
          errorMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit sheet

Future<void> showLoanEditor(BuildContext context, {Loan? loan}) {
  final session = SessionScope.of(context);
  final today = LocalDate.today(context.read<AppDependencies>().now);
  return showModalBottomSheet<void>(
    context: context,
    // Above the navigation bar, which is drawn over tab content.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    // The format is read while building the sheet (not in the tap handler).
    builder: (sheet) => _LoanEditor(
      repository: session.loans,
      loan: loan,
      format: AppFormat.of(sheet),
      today: today,
    ),
  );
}

class _LoanEditor extends StatefulWidget {
  const _LoanEditor({
    required this.repository,
    required this.format,
    required this.today,
    this.loan,
  });

  final LoanRepository repository;
  final AppFormat format;
  final LocalDate today;
  final Loan? loan;

  @override
  State<_LoanEditor> createState() => _LoanEditorState();
}

class _LoanEditorState extends State<_LoanEditor> {
  late final String _id = widget.loan?.id ?? widget.repository.newId();
  late LoanDirection _direction = widget.loan?.direction ?? LoanDirection.lent;
  late final _name = TextEditingController(text: widget.loan?.personName);
  late final _amount = TextEditingController(
    text: widget.loan == null
        ? ''
        : MoneyParser.toInputText(widget.loan!.amountMinor, _currency),
  );
  late final _note = TextEditingController(text: widget.loan?.note);
  late LocalDate _date = widget.loan?.date ?? widget.today;
  late LocalDate? _due = widget.loan?.dueDate;
  String? _nameError;
  String? _amountError;
  bool _saving = false;

  bool get _editing => widget.loan != null;
  CurrencyConfiguration get _currency =>
      widget.loan == null ||
          widget.loan!.currencyCode == widget.format.currencyCode
      ? widget.format.currency
      : AppFormat.forLocale(
          widget.format.locale,
          widget.loan!.currencyCode,
        ).currency;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool due}) async {
    final initial = (due ? _due : _date) ?? widget.today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: due
          ? widget.today.addDays(3650).toDateTime()
          : widget.today.toDateTime(),
    );
    if (picked == null) return;
    setState(() {
      final d = LocalDate.fromDateTime(picked);
      if (due) {
        _due = d;
      } else {
        _date = d;
      }
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final parsed = MoneyParser.parse(_amount.text, _currency);
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _amountError = parsed.minorUnits == null
          ? MoneyParser.messageFor(parsed.error!, _currency)
          : null;
    });
    if (_nameError != null || _amountError != null) return;
    final amount = parsed.minorUnits!;
    final base = widget.loan;
    final repaid = base == null ? 0 : base.repaidMinor.clamp(0, amount);
    final loan = Loan(
      id: _id,
      direction: _direction,
      personName: name.length > 60 ? name.substring(0, 60) : name,
      amountMinor: amount,
      repaidMinor: repaid,
      currencyCode: base?.currencyCode ?? widget.format.currencyCode,
      date: _date,
      dueDate: _due,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      settled: base != null && repaid >= amount,
    );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_editing) {
        await widget.repository.update(loan);
      } else {
        await widget.repository.create(loan);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? 'Loan updated' : 'Loan saved')),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = _currency;
    final fmt = widget.format;
    final color = loanColor(context, _direction);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing ? 'Edit loan' : 'Add a loan',
              style: context.text.titleLarge,
            ),
            const SizedBox(height: Space.lg),
            SegmentedButton<LoanDirection>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: LoanDirection.lent,
                  icon: Icon(Icons.south_west_rounded),
                  label: Text('I lent'),
                ),
                ButtonSegment(
                  value: LoanDirection.borrowed,
                  icon: Icon(Icons.north_east_rounded),
                  label: Text('I borrowed'),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: Space.lg),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: TextField(
                controller: _amount,
                autofocus: !_editing,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: currency.minorDigits > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                style: context.text.headlineLarge!.tabular.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  prefixText: '${currency.symbol} ',
                  hintText: currency.minorDigits > 0 ? '0.00' : '0',
                  errorText: _amountError,
                  errorMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              decoration: InputDecoration(
                labelText: _direction == LoanDirection.lent
                    ? 'Who did you lend to?'
                    : 'Who did you borrow from?',
                prefixIcon: const Icon(Icons.person_rounded),
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(due: false),
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                      fmt.relativeDay(_date, widget.today),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: _due == null
                      ? OutlinedButton.icon(
                          onPressed: () => _pickDate(due: true),
                          icon: const Icon(Icons.alarm_add_rounded, size: 18),
                          label: const Text('Due date'),
                        )
                      : InputChip(
                          avatar: const Icon(Icons.alarm_rounded, size: 18),
                          label: Text('Due ${fmt.dayMonth(_due!)}'),
                          onPressed: () => _pickDate(due: true),
                          onDeleted: () => setState(() => _due = null),
                        ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _note,
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: Space.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_editing ? 'Save changes' : 'Save loan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "you'll get / you owe" card for the home screen. Renders nothing
/// until the user has at least one active loan.
class LoansSummaryCard extends StatefulWidget {
  const LoansSummaryCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<LoansSummaryCard> createState() => _LoansSummaryCardState();
}

class _LoansSummaryCardState extends State<LoansSummaryCard> {
  late final Stream<List<Loan>> _loans = SessionScope.of(context).loans
      .watchAll();

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    final today = LocalDate.today(context.read<AppDependencies>().now);
    return StreamBuilder<List<Loan>>(
      stream: _loans,
      builder: (context, snap) {
        final loans = snap.data;
        if (loans == null) return const SizedBox.shrink();
        final t = LoanTotals.of(loans, fmt.currencyCode, today);
        if (t.isEmpty) return const SizedBox.shrink();
        Widget side(String label, int amount, LoanDirection d) => Expanded(
          child: Row(
            children: [
              IconBadge(
                icon: d == LoanDirection.lent
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                color: loanColor(context, d),
                size: 32,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.labelMedium),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        fmt.amount(amount),
                        style: context.text.titleMedium!.tabular.copyWith(
                          fontWeight: FontWeight.w700,
                          color: loanColor(context, d),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: Card(
            child: InkWell(
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Loans', style: context.text.titleMedium),
                        ),
                        if (t.overdueCount > 0)
                          _Badge(
                            label: '${t.overdueCount} overdue',
                            color: context.colors.error,
                          ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        side(
                          "You'll get",
                          t.toReceiveMinor,
                          LoanDirection.lent,
                        ),
                        const SizedBox(width: Space.md),
                        side('You owe', t.toPayMinor, LoanDirection.borrowed),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
