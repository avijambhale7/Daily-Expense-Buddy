import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../app/session/session_cubits.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/category_visuals.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/expense_category.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CategoriesCubit>().state;
    final active = state.active;
    final archived = state.categories.where((c) => c.isArchived).toList();

    Widget tile(ExpenseCategory c) => ListTile(
      key: ValueKey(c.id),
      leading: CategoryAvatar(category: c),
      title: Text(c.name),
      subtitle: Text(c.isBuiltIn ? 'Built-in' : 'Custom'),
      onTap: () => _edit(context, c),
      trailing: PopupMenuButton<String>(
        tooltip: 'Category actions',
        onSelected: (v) => _action(context, c, v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'expenses', child: Text('View expenses')),
          PopupMenuItem(
            value: c.isArchived ? 'unarchive' : 'archive',
            child: Text(c.isArchived ? 'Restore' : 'Archive'),
          ),
          if (!c.isBuiltIn)
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          TextButton.icon(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New category'),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.status == LoadStatus.failure)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: InfoBanner(
                      message: state.error ?? 'Could not sync categories.',
                      tone: BannerTone.warning,
                    ),
                  ),
                Card(
                  child: Column(children: [for (final c in active) tile(c)]),
                ),
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: Space.xl),
                  Text('Archived', style: context.text.titleSmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Archived categories are hidden when adding expenses but keep '
                    'their history in reports.',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: Space.sm),
                  Card(
                    child: Column(
                      children: [for (final c in archived) tile(c)],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _action(
    BuildContext context,
    ExpenseCategory c,
    String action,
  ) async {
    final cubit = context.read<CategoriesCubit>();
    try {
      switch (action) {
        case 'edit':
          await _edit(context, c);
        case 'expenses':
          context.go(Routes.historyForCategory(c.id));
        case 'archive':
          await cubit.setArchived(c, true);
          if (context.mounted) showMessage(context, '${c.name} archived');
        case 'unarchive':
          await cubit.setArchived(c, false);
        case 'delete':
          final ok = await showConfirmDialog(
            context,
            title: 'Delete "${c.name}"?',
            message: 'Only categories that are not used by any expense can be deleted.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (!ok) return;
          final deleted = await cubit.deleteIfUnused(c);
          if (!context.mounted) return;
          if (!deleted) {
            final archive = await showConfirmDialog(
              context,
              title: 'Category is in use',
              message:
                  'Some expenses use "${c.name}". Deleting it would affect your '
                  'history, so you can archive it instead.',
              confirmLabel: 'Archive',
            );
            if (archive) await cubit.setArchived(c, true);
          } else {
            showMessage(context, 'Category deleted');
          }
      }
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }

  Future<void> _edit(BuildContext context, ExpenseCategory? existing) async {
    final cubit = context.read<CategoriesCubit>();
    final result = await showDialog<ExpenseCategory>(
      context: context,
      builder: (_) => _CategoryDialog(
        existing: existing,
        newId: existing?.id ?? cubit.newId(),
        nextSortOrder: cubit.state.categories.length + 100,
      ),
    );
    if (result == null) return;
    try {
      await cubit.save(result);
    } on AppFailure catch (f) {
      if (context.mounted) showMessage(context, f.message);
    }
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.existing,
    required this.newId,
    required this.nextSortOrder,
  });

  final ExpenseCategory? existing;
  final String newId;
  final int nextSortOrder;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.iconKey ?? 'other';
  late int _color = widget.existing?.colorIndex ?? 0;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (name.length > ExpenseCategory.maxNameLength) {
      setState(
        () =>
            _error = 'Use ${ExpenseCategory.maxNameLength} characters or fewer',
      );
      return;
    }
    final e = widget.existing;
    Navigator.pop(
      context,
      e == null
          ? ExpenseCategory(
              id: widget.newId,
              name: name,
              iconKey: _icon,
              colorIndex: _color,
              sortOrder: widget.nextSortOrder,
            )
          : e.copyWith(name: name, iconKey: _icon, colorIndex: _color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appColors.categoryPalette;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New category' : 'Edit category'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: ExpenseCategory.maxNameLength,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: Space.md),
              Text('Icon', style: context.text.titleSmall),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final entry in CategoryIcons.catalogue.entries)
                    IconButton(
                      tooltip: entry.key.replaceAll('_', ' '),
                      isSelected: _icon == entry.key,
                      style: IconButton.styleFrom(
                        backgroundColor: _icon == entry.key
                            ? context.colors.primaryContainer
                            : null,
                      ),
                      onPressed: () => setState(() => _icon = entry.key),
                      icon: Icon(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Text('Colour', style: context.text.titleSmall),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (var i = 0; i < palette.length; i++)
                    Semantics(
                      label: 'Colour ${i + 1}',
                      selected: _color == i,
                      button: true,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = i),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: palette[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == i
                                  ? context.colors.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: _color == i
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
