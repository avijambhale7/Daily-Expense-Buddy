import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../app/session/session_cubits.dart';
import '../../app/session/user_scope.dart';
import '../../core/dates/local_date.dart';
import '../../core/errors/app_failure.dart';
import '../../core/formatting/app_format.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../domain/models/expense_filter.dart';
import '../../domain/services/csv_exporter.dart';
import '../../domain/services/expense_validator.dart';
import '../../services/export/file_saver.dart';

enum _Preset { thisMonth, lastMonth, thisYear, last12Months, allTime, custom }

/// CSV export of the signed-in user's own expenses. Uses the given filter's
/// category/payment method and a chosen date range.
Future<void> showExportDialog(
  BuildContext context, {
  ExpenseFilter filter = const ExpenseFilter(),
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(filter: filter),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.filter});

  final ExpenseFilter filter;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late _Preset _preset = widget.filter.range != null
      ? _Preset.custom
      : _Preset.thisMonth;
  DateRange? _custom;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _custom = widget.filter.range;
  }

  LocalDate get _today => LocalDate.today(context.read<AppDependencies>().now);

  DateRange? _rangeFor(_Preset p) {
    final t = _today;
    switch (p) {
      case _Preset.thisMonth:
        return DateRange(t.startOfMonth, t);
      case _Preset.lastMonth:
        final s = t.startOfMonth.addMonths(-1);
        return DateRange(s, s.endOfMonth);
      case _Preset.thisYear:
        return DateRange(t.startOfYear, t);
      case _Preset.last12Months:
        return DateRange(t.addMonths(-12).addDays(1), t);
      case _Preset.allTime:
        return DateRange(ExpenseValidator.earliestDate, t);
      case _Preset.custom:
        return _custom;
    }
  }

  Future<void> _pickCustom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: ExpenseValidator.earliestDate.toDateTime(),
      lastDate: _today.toDateTime(),
      initialDateRange: _custom == null
          ? null
          : DateTimeRange(
              start: _custom!.start.toDateTime(),
              end: _custom!.end.toDateTime(),
            ),
    );
    if (r != null && mounted) {
      setState(() {
        _custom = DateRange(
          LocalDate.fromDateTime(r.start),
          LocalDate.fromDateTime(r.end),
        );
        _preset = _Preset.custom;
      });
    }
  }

  Future<void> _export() async {
    final range = _rangeFor(_preset);
    if (range == null) {
      setState(() => _error = 'Choose a date range first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = SessionScope.of(context);
      final categories = context.read<CategoriesCubit>().state.byId;
      final expenses = await session.expenses.fetch(
        widget.filter.copyWith(range: () => range, newestFirst: false),
      );
      if (expenses.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'There are no expenses in this range to export.';
        });
        return;
      }
      final csv = CsvExporter.build(expenses, categories);
      final result = await FileSaver.saveText(
        fileName: CsvExporter.fileName(range),
        content: csv,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
        context,
        result == FileSaveResult.downloaded
            ? 'Exported ${expenses.length} expenses'
            : (result == FileSaveResult.shared
                  ? 'Export ready (${expenses.length} expenses)'
                  : 'Export cancelled'),
      );
    } on AppFailure catch (f) {
      setState(() {
        _busy = false;
        _error = f.message;
      });
    } catch (e, st) {
      AppLogger.error('Export', 'Export failed', e, st);
      setState(() {
        _busy = false;
        _error = 'The export could not be created. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = AppFormat.of(context);
    String label(_Preset p) => switch (p) {
      _Preset.thisMonth => 'This month',
      _Preset.lastMonth => 'Last month',
      _Preset.thisYear => 'This year',
      _Preset.last12Months => 'Last 12 months',
      _Preset.allTime => 'All time',
      _Preset.custom => _custom == null ? 'Custom range…' : fmt.range(_custom!),
    };
    final categories = context.read<CategoriesCubit>().state;
    final f = widget.filter;
    return AlertDialog(
      title: const Text('Export expenses (CSV)'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date range', style: context.text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final p in _Preset.values)
                  ChoiceChip(
                    label: Text(label(p)),
                    selected: _preset == p,
                    onSelected: _busy
                        ? null
                        : (_) => p == _Preset.custom
                              ? _pickCustom()
                              : setState(() => _preset = p),
                  ),
              ],
            ),
            if (f.categoryId != null || f.paymentMethod != null) ...[
              const SizedBox(height: Space.lg),
              Text(
                'Filters applied: '
                '${[if (f.categoryId != null) categories.resolve(f.categoryId!).name, if (f.paymentMethod != null) f.paymentMethod!.label].join(', ')}',
                style: context.text.bodySmall,
              ),
            ],
            const SizedBox(height: Space.lg),
            Text(
              'The file contains only your own expenses: date, amount, '
              'currency, category, merchant, note, payment method and when it '
              'was recorded.',
              style: context.text.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.md),
              InfoBanner(message: _error!, tone: BannerTone.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.onPrimary,
                  ),
                )
              : const Icon(Icons.download_rounded),
          label: const Text('Export'),
        ),
      ],
    );
  }
}
