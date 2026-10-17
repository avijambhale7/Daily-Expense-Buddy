import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/routes.dart';
import '../../../app/session/session_cubits.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/money/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/user_preferences.dart';
import '../../../services/sound/sound_effects.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../auth/presentation/onboarding_page.dart';
import '../../export/export_dialog.dart';

/// Signs out after warning about changes that have not synced yet.
Future<void> confirmAndSignOut(BuildContext context) async {
  final deps = context.read<AppDependencies>();
  final auth = context.read<AuthCubit>();
  final pending = await deps.hasPendingWrites?.call() ?? false;
  if (!context.mounted) return;
  final ok = await showConfirmDialog(
    context,
    title: 'Log out?',
    message: pending
        ? 'Some changes on this device have not synced yet. If you log out '
              'now they will be lost. Connect to the internet first to keep them.'
        : 'Your expenses stay safely synced to your account.',
    confirmLabel: pending ? 'Log out anyway' : 'Log out',
    destructive: pending,
  );
  if (!ok) return;
  try {
    await auth.signOut();
  } on AppFailure catch (f) {
    if (context.mounted) showMessage(context, f.message);
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const formatLocales = {
    'en_US': 'English (United States)',
    'en_GB': 'English (United Kingdom)',
    'en_IN': 'English (India)',
    'en_AU': 'English (Australia)',
    'en_CA': 'English (Canada)',
    'de_DE': 'Deutsch (Deutschland)',
    'fr_FR': 'Français (France)',
    'es_ES': 'Español (España)',
    'ja_JP': '日本語 (日本)',
    'ar_AE': 'العربية (الإمارات)',
  };

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthCubit c) => c.state.user);
    final prefsCubit = context.read<PreferencesCubit>();
    final prefs = context.watch<PreferencesCubit>().state.preferences;
    final theme = context.watch<ThemeCubit>().state;
    final premium = context.watch<EntitlementCubit>().state;
    final deps = context.read<AppDependencies>();
    final sounds = deps.soundEffects;
    final fmt = AppFormat.of(context);
    final isPremium = premium.isPremium(deps.now());
    final currency = Currencies.byCode(prefs.currencyCode);

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
            child: Semantics(
              header: true,
              child: Text(title, style: context.text.titleSmall),
            ),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                section('Profile', [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: context.colors.secondaryContainer,
                      foregroundColor: context.colors.onSecondaryContainer,
                      child: Text(user?.initials ?? '?'),
                    ),
                    title: Text(
                      user?.displayName?.isNotEmpty == true
                          ? user!.displayName!
                          : 'Your account',
                    ),
                    subtitle: Text(user?.email ?? ''),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.account),
                  ),
                ]),
                section('Preferences', [
                  ListTile(
                    leading: const Icon(Icons.currency_exchange_rounded),
                    title: const Text('Reporting currency'),
                    subtitle: Text('${currency.code} · ${currency.name}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickCurrency(context, prefsCubit, prefs),
                  ),
                  ListTile(
                    leading: const Icon(Icons.view_week_rounded),
                    title: const Text('Week starts on'),
                    trailing: DropdownButton<int>(
                      value: prefs.weekStart,
                      underline: const SizedBox.shrink(),
                      onChanged: (v) => v == null
                          ? null
                          : prefsCubit.update(prefs.copyWith(weekStart: v)),
                      items: const [
                        DropdownMenuItem(
                          value: DateTime.monday,
                          child: Text('Monday'),
                        ),
                        DropdownMenuItem(
                          value: DateTime.sunday,
                          child: Text('Sunday'),
                        ),
                        DropdownMenuItem(
                          value: DateTime.saturday,
                          child: Text('Saturday'),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: const Text('Number & date format'),
                    subtitle: Text(
                      prefs.formatLocale == null
                          ? 'Device default (${deps.locale})'
                          : formatLocales[prefs.formatLocale] ??
                                prefs.formatLocale!,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickLocale(context, prefsCubit, prefs),
                  ),
                ]),
                section('Appearance', [
                  Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Mode', style: context.text.labelLarge),
                        const SizedBox(height: Space.sm),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System'),
                              icon: Icon(Icons.brightness_auto_rounded),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode_rounded),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode_rounded),
                            ),
                          ],
                          selected: {theme.mode},
                          onSelectionChanged: (s) =>
                              context.read<ThemeCubit>().setMode(s.first),
                        ),
                        const SizedBox(height: Space.lg),
                        Text('Theme', style: context.text.labelLarge),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: [
                            for (final p in AppPalettes.all)
                              _PaletteOption(
                                palette: p,
                                selected: theme.effectivePalette.id == p.id,
                                locked: p.isPremium && !isPremium,
                                onTap: () async {
                                  final ok = await context
                                      .read<ThemeCubit>()
                                      .setPalette(p.id);
                                  if (!ok && context.mounted) {
                                    context.go(Routes.premium);
                                  }
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ]),
                section('Tracking', [
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Daily reminders'),
                    subtitle: Text(
                      prefs.reminders.enabled
                          ? 'On at ${fmt.timeOfDay(prefs.reminders.timeMinutes)}'
                          : 'Off',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.reminders),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: sounds.enabled,
                    builder: (context, on, _) => SwitchListTile(
                      secondary: Icon(
                        on
                            ? Icons.volume_up_outlined
                            : Icons.volume_off_outlined,
                      ),
                      title: const Text('Sound effects'),
                      subtitle: const Text(
                        'When you save an expense or complete a day',
                      ),
                      value: on,
                      onChanged: (v) async {
                        await sounds.setEnabled(v);
                        if (v) await sounds.play(Sfx.celebrate);
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.handshake_outlined),
                    title: const Text('Loans'),
                    subtitle: const Text('Money you lent or borrowed'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.loans),
                  ),
                  ListTile(
                    leading: const Icon(Icons.savings_outlined),
                    title: const Text('Budgets'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.budgets),
                  ),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Categories'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.categories),
                  ),
                ]),
                section('Data & privacy', [
                  ListTile(
                    leading: const Icon(Icons.download_rounded),
                    title: const Text('Export expenses (CSV)'),
                    onTap: () => showExportDialog(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy & your data'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.privacy),
                  ),
                ]),
                section('Account', [
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('Premium'),
                    subtitle: Text(isPremium ? 'Active' : 'Free plan'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.premium),
                  ),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('Account & security'),
                    subtitle: const Text('Password reset, delete account'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go(Routes.account),
                  ),
                  ListTile(
                    leading: const Icon(Icons.slideshow_rounded),
                    title: const Text('Feature tour'),
                    subtitle: const Text('See the introduction again'),
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (route) => OnboardingPage(
                              onDone: () => Navigator.of(route).pop(),
                            ),
                          ),
                        ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: const Text('Help & about'),
                    onTap: () => _showAbout(context, deps.appVersion),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.logout_rounded,
                      color: context.colors.error,
                    ),
                    title: Text(
                      'Log out',
                      style: TextStyle(color: context.colors.error),
                    ),
                    onTap: () => confirmAndSignOut(context),
                  ),
                ]),
                Center(
                  child: Text(
                    'Daily Expense Buddy ${deps.appVersion}',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCurrency(
    BuildContext context,
    PreferencesCubit cubit,
    UserPreferences prefs,
  ) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Reporting currency'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.xxl,
              0,
              Space.xxl,
              Space.md,
            ),
            child: Text(
              'New expenses are recorded in this currency. Existing expenses keep '
              'their original currency and amounts are never converted. Reports '
              'and budgets include only expenses in the reporting currency.',
              style: context.text.bodySmall,
            ),
          ),
          for (final c in Currencies.all)
            ListTile(
              selected: c.code == prefs.currencyCode,
              leading: SizedBox(
                width: 40,
                child: Center(child: Text(c.symbol)),
              ),
              title: Text(c.name),
              subtitle: Text(c.code),
              trailing: c.code == prefs.currencyCode
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, c.code),
            ),
        ],
      ),
    );
    if (picked != null && picked != prefs.currencyCode) {
      await cubit.update(prefs.copyWith(currencyCode: picked));
    }
  }

  Future<void> _pickLocale(
    BuildContext context,
    PreferencesCubit cubit,
    UserPreferences prefs,
  ) async {
    const deviceKey = '__device__';
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Number & date format'),
        children: [
          ListTile(
            title: const Text('Device default'),
            trailing: prefs.formatLocale == null
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, deviceKey),
          ),
          for (final e in formatLocales.entries)
            ListTile(
              title: Text(e.value),
              trailing: prefs.formatLocale == e.key
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, e.key),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await cubit.update(
      prefs.copyWith(formatLocale: () => picked == deviceKey ? null : picked),
    );
  }

  void _showAbout(BuildContext context, String version) {
    showAboutDialog(
      context: context,
      applicationName: 'Daily Expense Buddy',
      applicationVersion: version,
      applicationIcon: const AppLogo(size: 48),
      applicationLegalese: 'Track Today. Spend Smarter.',
      children: [
        const SizedBox(height: Space.lg),
        const Text(
          'Tips:\n'
          '• Tap "Add expense" (Alt+N on desktop) – amount, category, save.\n'
          '• Mark each day complete so reminders stop for that day.\n'
          '• A day without expenses only counts as "no expenses" once you confirm it.\n'
          '• Reports and budgets use your reporting currency only.',
        ),
      ],
    );
  }
}

class _PaletteOption extends StatelessWidget {
  const _PaletteOption({
    required this.palette,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name} theme${locked ? ', premium' : ''}',
      excludeSemantics: true,
      child: Tooltip(
        message: locked ? '${palette.name} (Premium)' : palette.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.md),
          child: Container(
            width: 112,
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: selected ? c.primary : c.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final color in palette.preview)
                      Expanded(
                        child: Container(
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (locked) ...[
                      Icon(
                        Icons.lock_rounded,
                        size: 14,
                        color: c.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                    ] else if (selected) ...[
                      Icon(Icons.check_rounded, size: 14, color: c.primary),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: Text(
                        palette.name,
                        style: context.text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
