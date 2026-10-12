import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/dates/local_date.dart';
import '../../../core/theme/design_tokens.dart';
import 'expense_form_page.dart';

/// Opens the add/edit expense UI in the most appropriate form:
/// a full-screen page on phones, a centred dialog on tablets and desktops
/// (so the dashboard and navigation stay visible).
Future<void> openExpenseEditor(
  BuildContext context, {
  LocalDate? date,
  String? expenseId,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
  if (!wide) {
    await context.push(
      expenseId == null
          ? Routes.newExpense(date: date)
          : Routes.editExpense(expenseId),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(Space.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.formMaxWidth),
        child: ExpenseFormView(
          initialDate: date,
          expenseId: expenseId,
          inDialog: true,
        ),
      ),
    ),
  );
}
