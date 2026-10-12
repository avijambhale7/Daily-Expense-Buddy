import 'package:material_ui/material_ui.dart';

import '../../core/dates/local_date.dart';
import '../../core/formatting/app_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../domain/models/expense.dart';
import '../../domain/models/expense_category.dart';

/// Icon shown for expenses whose latest change has not reached the server.
class PendingSyncIcon extends StatelessWidget {
  const PendingSyncIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Waiting to sync',
      child: Icon(
        Icons.cloud_upload_outlined,
        size: 16,
        color: context.colors.onSurfaceVariant,
        semanticLabel: 'Waiting to sync',
      ),
    );
  }
}

/// Touch-friendly expense row used on phones and in compact lists.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    required this.category,
    required this.format,
    this.onTap,
    this.showDate = false,
    this.today,
  });

  final Expense expense;
  final ExpenseCategory category;
  final AppFormat format;
  final VoidCallback? onTap;
  final bool showDate;
  final LocalDate? today;

  @override
  Widget build(BuildContext context) {
    final title = expense.merchant ?? category.name;
    final details = <String>[
      if (expense.merchant != null) category.name,
      if (showDate && today != null) format.relativeDay(expense.date, today!),
      if (expense.note != null) expense.note!,
    ];
    final otherCurrency = expense.currencyCode != format.currencyCode;
    final amountText = otherCurrency
        ? AppFormat.forLocale(
            format.locale,
            expense.currencyCode,
          ).amount(expense.amountMinor)
        : format.amount(expense.amountMinor);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.sm),
      leading: CategoryAvatar(category: category),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (expense.hasPendingWrites) ...[
            const PendingSyncIcon(),
            const SizedBox(width: Space.xs),
          ],
          Text(amountText, style: context.text.titleSmall!.tabular),
        ],
      ),
    );
  }
}
