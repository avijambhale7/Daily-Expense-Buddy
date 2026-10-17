import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../app/session/user_scope.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/money/money_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/category_visuals.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/expense_category.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../services/sound/sound_effects.dart';
import '../../../domain/services/expense_validator.dart';
import '../cubit/expense_form_cubit.dart';

/// Full-screen add/edit page (phones, deep links, notification taps).
class ExpenseFormPage extends StatelessWidget {
  const ExpenseFormPage({super.key, this.initialDate, this.expenseId});

  final LocalDate? initialDate;
  final String? expenseId;

  @override
  Widget build(BuildContext context) {
    return ExpenseFormView(initialDate: initialDate, expenseId: expenseId);
  }
}

/// The expense form, usable as a page or inside a dialog.
class ExpenseFormView extends StatelessWidget {
  const ExpenseFormView({
    super.key,
    this.initialDate,
    this.expenseId,
    this.inDialog = false,
  });

  final LocalDate? initialDate;
  final String? expenseId;
  final bool inDialog;

  @override
  Widget build(BuildContext context) {
    final deps = context.read<AppDependencies>();
    return BlocProvider(
      create: (context) => ExpenseFormCubit(
        repository: SessionScope.of(context).expenses,
        currencyCode: context.read<PreferencesCubit>().preferences.currencyCode,
        today: LocalDate.today(deps.now),
        initialDate: initialDate,
        expenseId: expenseId,
      ),
      child: _ExpenseFormBody(inDialog: inDialog),
    );
  }
}

class _ExpenseFormBody extends StatefulWidget {
  const _ExpenseFormBody({required this.inDialog});

  final bool inDialog;

  @override
  State<_ExpenseFormBody> createState() => _ExpenseFormBodyState();
}

class _ExpenseFormBodyState extends State<_ExpenseFormBody> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _syncControllers(context.read<ExpenseFormCubit>().state);
  }

  void _syncControllers(ExpenseFormState s) {
    if (_amount.text != s.amountText) _amount.text = s.amountText;
    if (_merchant.text != s.merchant) _merchant.text = s.merchant;
    if (_note.text != s.note) _note.text = s.note;
    if (s.isEditing &&
        (s.merchant.isNotEmpty ||
            s.note.isNotEmpty ||
            s.paymentMethod != null)) {
      _showDetails = true;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  /// Adds [major] whole units to the typed amount (integer maths only).
  void _quickAdd(ExpenseFormState s, int major) {
    final currency = s.currency;
    final factor = _pow10(currency.minorDigits);
    final current = MoneyParser.parse(_amount.text, currency).minorUnits ?? 0;
    final next = current + major * factor;
    final whole = next ~/ factor;
    final frac = next % factor;
    final text = currency.minorDigits == 0
        ? '$whole'
        : '$whole.${frac.toString().padLeft(currency.minorDigits, '0')}';
    _amount.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    context.read<ExpenseFormCubit>().amountChanged(text);
    HapticFeedback.selectionClick();
  }

  static int _pow10(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  Future<void> _pickDate(ExpenseFormState s) async {
    final today = LocalDate.today(context.read<AppDependencies>().now);
    final picked = await showDatePicker(
      context: context,
      initialDate: s.date.toDateTime(),
      firstDate: ExpenseValidator.earliestDate.toDateTime(),
      lastDate: today.toDateTime(),
      helpText: 'Expense date',
    );
    if (picked != null && mounted) {
      context.read<ExpenseFormCubit>().dateChanged(
        LocalDate.fromDateTime(picked),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this expense?',
      message:
          'It will be removed from your history and all reports on every '
          'device. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok && mounted) await context.read<ExpenseFormCubit>().delete();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExpenseFormCubit, ExpenseFormState>(
      listenWhen: (p, c) => p.status != c.status,
      listener: (context, s) {
        if (_isDone(s.status)) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final pending = s.outcome == SaveOutcome.pendingSync;
          final text = switch (s.status) {
            ExpenseFormStatus.deleted =>
              pending
                  ? 'Deleted on this device. It will sync when you are online.'
                  : 'Expense deleted',
            _ =>
              pending
                  ? 'Saved on this device. It will sync when you are online.'
                  : (s.isEditing ? 'Expense updated' : 'Expense added'),
          };
          if (s.status == ExpenseFormStatus.saved) {
            unawaited(
              context.read<AppDependencies>().soundEffects.play(
                Sfx.expenseSaved,
              ),
            );
          }
          _close();
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(text)));
        } else if (s.status == ExpenseFormStatus.ready) {
          setState(() => _syncControllers(s));
        }
      },
      builder: (context, s) {
        final title = s.isEditing ? 'Edit expense' : 'Add expense';
        final body = switch (s.status) {
          ExpenseFormStatus.loading => const LoadingView(),
          ExpenseFormStatus.notFound => EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Expense not found',
            message: 'It may have been deleted on another device.',
            action: OutlinedButton(
              onPressed: _close,
              child: const Text('Close'),
            ),
          ),
          _ => _form(context, s),
        };

        if (widget.inDialog) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xxl,
                  Space.lg,
                  Space.sm,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: context.text.titleLarge),
                    ),
                    if (s.isEditing) _deleteButton(s),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: s.isBusy ? null : _close,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(child: body),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close',
              onPressed: s.isBusy ? null : _close,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text(title),
            actions: [if (s.isEditing) _deleteButton(s)],
          ),
          body: PageBody(maxWidth: Breakpoints.formMaxWidth, child: body),
        );
      },
    );
  }

  bool _isDone(ExpenseFormStatus s) =>
      s == ExpenseFormStatus.saved || s == ExpenseFormStatus.deleted;

  Widget _deleteButton(ExpenseFormState s) => IconButton(
    tooltip: 'Delete expense',
    onPressed: s.isBusy ? null : _confirmDelete,
    icon: Icon(Icons.delete_outline_rounded, color: context.colors.error),
  );

  Widget _form(BuildContext context, ExpenseFormState s) {
    final cubit = context.read<ExpenseFormCubit>();
    final fmt = AppFormat.of(context);
    final today = LocalDate.today(context.read<AppDependencies>().now);
    final categoriesState = context.watch<CategoriesCubit>().state;
    final categories = [
      ...categoriesState.active,
      if (s.categoryId != null &&
          !categoriesState.active.any((c) => c.id == s.categoryId))
        categoriesState.resolve(s.categoryId!),
    ];
    final v = s.validation;
    final currency = s.currency;

    final fields = ListView(
      shrinkWrap: widget.inDialog,
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.lg,
        Space.xxl,
        Space.xl,
      ),
      children: [
        if (s.original?.hasPendingWrites ?? false) ...[
          const InfoBanner(
            icon: Icons.cloud_upload_outlined,
            message: 'This expense has changes waiting to sync.',
          ),
          const SizedBox(height: Space.lg),
        ],
        Container(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.md,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.colors.primaryContainer,
                context.colors.primaryContainer.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(Radii.xl),
          ),
          child: Column(
            children: [
              Text(
                'How much did you spend?',
                style: context.text.titleSmall?.copyWith(
                  color: context.colors.onPrimaryContainer,
                ),
              ),
              TextField(
                controller: _amount,
                autofocus: !s.isEditing,
                enabled: !s.isBusy,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: currency.minorDigits > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                textInputAction: TextInputAction.done,
                onChanged: cubit.amountChanged,
                onSubmitted: (_) => cubit.submit(),
                style: context.text.displaySmall!.tabular.copyWith(
                  color: context.colors.onPrimaryContainer,
                ),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  prefixText: '${currency.symbol} ',
                  prefixStyle: context.text.headlineSmall?.copyWith(
                    color: context.colors.onPrimaryContainer.withValues(
                      alpha: 0.7,
                    ),
                  ),
                  hintText: currency.minorDigits > 0 ? '0.00' : '0',
                  hintStyle: context.text.displaySmall!.tabular.copyWith(
                    color: context.colors.onPrimaryContainer.withValues(
                      alpha: 0.3,
                    ),
                  ),
                  errorText: v?.amountError,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: Space.sm),
              // Quick amounts: tap to add to what is typed.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  for (final step in const [10, 50, 100, 500])
                    ActionChip(
                      label: Text('+${currency.symbol}$step'),
                      tooltip: 'Add ${currency.symbol}$step',
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: context.colors.onPrimaryContainer.withValues(
                          alpha: 0.25,
                        ),
                      ),
                      backgroundColor: context.colors.surface.withValues(
                        alpha: 0.6,
                      ),
                      onPressed: s.isBusy ? null : () => _quickAdd(s, step),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        _SectionLabel(icon: Icons.edit_note_rounded, text: 'What was it for?'),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _merchant,
          enabled: !s.isBusy,
          onChanged: cubit.merchantChanged,
          maxLength: Expense.maxMerchantLength,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'e.g. Lunch, Uber, Flipkart (optional)',
            prefixIcon: const Icon(Icons.storefront_rounded),
            errorText: v?.merchantError,
            counterText: '',
          ),
        ),
        const SizedBox(height: Space.xl),
        _SectionLabel(
          icon: Icons.category_rounded,
          text: s.categoryId == null
              ? 'Category'
              : 'Category · ${categoriesState.resolve(s.categoryId!).name}',
        ),
        const SizedBox(height: Space.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            // As many columns as fit (4 on most phones), equal widths.
            final cols = (constraints.maxWidth / 84).floor().clamp(3, 6);
            final width = constraints.maxWidth / cols;
            return Wrap(
              runSpacing: Space.xs,
              children: [
                for (final c in categories)
                  SizedBox(
                    width: width,
                    child: _CategoryChoice(
                      category: c,
                      selected: s.categoryId == c.id,
                      onSelected: s.isBusy
                          ? null
                          : (sel) => cubit.categoryChanged(sel ? c.id : null),
                    ),
                  ),
              ],
            );
          },
        ),
        if (s.categoryId == null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'No category selected – it will be saved as "Other".',
              style: context.text.bodySmall,
            ),
          ),
        const SizedBox(height: Space.xl),
        const _SectionLabel(icon: Icons.event_rounded, text: 'Date'),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            ChoiceChip(
              label: const Text('Today'),
              selected: s.date == today,
              onSelected: s.isBusy ? null : (_) => cubit.dateChanged(today),
            ),
            ChoiceChip(
              label: const Text('Yesterday'),
              selected: s.date == today.addDays(-1),
              onSelected: s.isBusy
                  ? null
                  : (_) => cubit.dateChanged(today.addDays(-1)),
            ),
            ActionChip(
              avatar: const Icon(Icons.event_rounded, size: 18),
              label: Text(
                s.date < today.addDays(-1) ? fmt.date(s.date) : 'Pick a date',
              ),
              onPressed: s.isBusy ? null : () => _pickDate(s),
            ),
          ],
        ),
        if (v?.dateError != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              v!.dateError!,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        const SizedBox(height: Space.lg),
        Theme(
          data: context.theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _showDetails,
            leading: const Icon(Icons.tune_rounded),
            title: Text('More details', style: context.text.titleSmall),
            subtitle: Text(
              s.paymentMethod == null && s.note.isEmpty
                  ? 'Note and payment method (optional)'
                  : [
                      if (s.paymentMethod != null) s.paymentMethod!.label,
                      if (s.note.isNotEmpty) 'Note added',
                    ].join(' · '),
              style: context.text.bodySmall,
            ),
            childrenPadding: const EdgeInsets.only(bottom: Space.sm),
            children: [
              TextField(
                controller: _note,
                enabled: !s.isBusy,
                onChanged: cubit.noteChanged,
                maxLength: Expense.maxNoteLength,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Note',
                  errorText: v?.noteError,
                ),
              ),
              const SizedBox(height: Space.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Payment method', style: context.text.labelLarge),
              ),
              const SizedBox(height: Space.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final m in PaymentMethod.values)
                      ChoiceChip(
                        avatar: Icon(_paymentIcon(m), size: 18),
                        label: Text(m.label),
                        selected: s.paymentMethod == m,
                        onSelected: s.isBusy
                            ? null
                            : (sel) => cubit.paymentChanged(sel ? m : null),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (s.error != null) ...[
          const SizedBox(height: Space.md),
          InfoBanner(
            message: s.error!,
            tone: BannerTone.error,
            icon: Icons.error_outline_rounded,
          ),
        ],
      ],
    );

    // The save action stays visible at the bottom so a quick entry never
    // requires scrolling.
    final saveBar = Material(
      color: widget.inDialog
          ? Colors.transparent
          : context.theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.xxl,
            Space.sm,
            Space.xxl,
            Space.lg,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: s.isBusy ? null : cubit.submit,
              icon: s.status == ExpenseFormStatus.saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                s.status == ExpenseFormStatus.saving
                    ? 'Saving…'
                    : (s.isEditing ? 'Save changes' : 'Save expense'),
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: widget.inDialog ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          fit: widget.inDialog ? FlexFit.loose : FlexFit.tight,
          child: fields,
        ),
        const Divider(height: 1),
        saveBar,
      ],
    );
  }
}

IconData _paymentIcon(PaymentMethod m) => switch (m) {
  PaymentMethod.cash => Icons.payments_rounded,
  PaymentMethod.card => Icons.credit_card_rounded,
  PaymentMethod.mobile => Icons.qr_code_2_rounded,
  PaymentMethod.bankTransfer => Icons.account_balance_rounded,
  PaymentMethod.wallet => Icons.account_balance_wallet_rounded,
  PaymentMethod.other => Icons.more_horiz_rounded,
};

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.colors.primary),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.selected,
    required this.onSelected,
  });

  final ExpenseCategory category;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final color = category.color(context);
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onSelected == null ? null : () => onSelected!(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: selected ? color : color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? c.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Icon(
                  selected ? Icons.check_rounded : category.icon,
                  color: selected ? Colors.white : color,
                  size: 26,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                category.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: selected ? c.onSurface : c.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
