import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/app_logo.dart';
import '../auth/cubit/auth_cubit.dart';
import '../expenses/presentation/expense_editor.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Order matches the router's shell branches.
const _destinations = [
  _Destination(
    'Dashboard',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard_rounded,
  ),
  _Destination(
    'History',
    Icons.receipt_long_outlined,
    Icons.receipt_long_rounded,
  ),
  _Destination('Reports', Icons.insights_outlined, Icons.insights_rounded),
  _Destination(
    'Calendar',
    Icons.calendar_month_outlined,
    Icons.calendar_month_rounded,
  ),
  _Destination('Budgets', Icons.savings_outlined, Icons.savings_rounded),
  _Destination('Categories', Icons.category_outlined, Icons.category_rounded),
  _Destination('Settings', Icons.settings_outlined, Icons.settings_rounded),
];

/// Responsive navigation chrome shared by all signed-in screens:
/// * compact (< 600 px): bottom navigation bar + add button
/// * medium (600–1023 px): navigation rail
/// * expanded (≥ 1024 px): permanent sidebar with brand and account
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final size = windowSizeFor(MediaQuery.sizeOf(context).width);
    final content = switch (size) {
      WindowSize.compact => _CompactShell(shell: shell, onSelect: _go),
      WindowSize.medium => _RailShell(shell: shell, onSelect: _go),
      WindowSize.expanded => _SidebarShell(shell: shell, onSelect: _go),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, alt: true): () =>
            openExpenseEditor(context),
      },
      child: FocusScope(autofocus: true, child: content),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({required this.shell, required this.onSelect});

  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;

  // Bottom bar: Home, History, Reports, Calendar, More (settings branch).
  static const _bar = [0, 1, 2, 3, 6];

  @override
  Widget build(BuildContext context) {
    final current = shell.currentIndex;
    final selected = _bar.contains(current)
        ? _bar.indexOf(current)
        : 4; // Budgets/Categories live under "More".
    // Home has its own prominent Add button in the header card.
    final showFab = current == 1 || current == 3;
    return Scaffold(
      body: shell,
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              heroTag: 'add-expense',
              onPressed: () => openExpenseEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add expense'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => onSelect(_bar[i]),
        destinations: [
          for (final i in _bar)
            NavigationDestination(
              icon: Icon(i == 6 ? Icons.menu_rounded : _destinations[i].icon),
              selectedIcon: Icon(
                i == 6
                    ? Icons.menu_open_rounded
                    : _destinations[i].selectedIcon,
              ),
              label: i == 0
                  ? 'Home'
                  : (i == 6 ? 'More' : _destinations[i].label),
            ),
        ],
      ),
    );
  }
}

class _RailShell extends StatelessWidget {
  const _RailShell({required this.shell, required this.onSelect});

  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: onSelect,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: Space.sm, bottom: Space.lg),
                child: Column(
                  children: [
                    const AppLogo(size: 40),
                    const SizedBox(height: Space.lg),
                    Tooltip(
                      message: 'Add expense (Alt+N)',
                      child: FloatingActionButton(
                        heroTag: 'add-expense',
                        elevation: 0,
                        onPressed: () => openExpenseEditor(context),
                        child: const Icon(Icons.add_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      ),
    );
  }
}

class _SidebarShell extends StatelessWidget {
  const _SidebarShell({required this.shell, required this.onSelect});

  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = context.select((AuthCubit c) => c.state.user);
    return Scaffold(
      body: Row(
        children: [
          Material(
            color: context.theme.navigationRailTheme.backgroundColor,
            child: SizedBox(
              width: 264,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        Space.xl,
                        Space.xl,
                        Space.lg,
                        Space.lg,
                      ),
                      child: AppLogo(size: 40, showName: true),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                      child: Tooltip(
                        message: 'Shortcut: Alt+N',
                        child: FilledButton.icon(
                          onPressed: () => openExpenseEditor(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add expense'),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                        ),
                        children: [
                          for (var i = 0; i < _destinations.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: ListTile(
                                selected: i == shell.currentIndex,
                                selectedTileColor: colors.primaryContainer,
                                selectedColor: colors.onPrimaryContainer,
                                leading: Icon(
                                  i == shell.currentIndex
                                      ? _destinations[i].selectedIcon
                                      : _destinations[i].icon,
                                ),
                                title: Text(
                                  _destinations[i].label,
                                  style: context.text.labelLarge?.copyWith(
                                    color: i == shell.currentIndex
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                                dense: true,
                                visualDensity: VisualDensity.standard,
                                onTap: () => onSelect(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (user != null)
                      Padding(
                        padding: const EdgeInsets.all(Space.md),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colors.secondaryContainer,
                            foregroundColor: colors.onSecondaryContainer,
                            child: Text(user.initials),
                          ),
                          title: Text(
                            user.displayName?.isNotEmpty == true
                                ? user.displayName!
                                : 'Your account',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => context.go('/settings/account'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
