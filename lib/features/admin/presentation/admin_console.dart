import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/session/user_scope.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/membership.dart';
import '../../../domain/repositories/repositories.dart';
import '../../auth/cubit/auth_cubit.dart';
import '../../membership/membership_cubit.dart';

final _when = DateFormat('d MMM yyyy, h:mm a');

String _date(DateTime? d) => d == null ? 'just now' : _when.format(d.toLocal());

/// Separate console for admin accounts: premium requests, users (ban,
/// premium) and premium settings. Uses its own colour scheme so it is
/// never mistaken for the personal expense app.
class AdminConsole extends StatefulWidget {
  const AdminConsole({super.key});

  @override
  State<AdminConsole> createState() => _AdminConsoleState();
}

class _AdminConsoleState extends State<AdminConsole> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: base.brightness,
    );
    final theme = base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: scheme.primaryContainer,
      ),
    );
    final email = context.select((AuthCubit c) => c.state.user?.email) ?? '';
    const tabs = [
      (Icons.inbox_rounded, 'Requests'),
      (Icons.people_alt_rounded, 'Users'),
      (Icons.tune_rounded, 'Settings'),
    ];
    final body = switch (_tab) {
      0 => const _RequestsTab(),
      1 => const _UsersTab(),
      _ => const _SettingsTab(),
    };
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: const Padding(
              padding: EdgeInsets.only(left: Space.sm),
              child: Icon(Icons.admin_panel_settings_rounded),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Admin console'),
                Text(email, style: context.text.bodySmall),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Log out',
                onPressed: () => context.read<AuthCubit>().signOut(),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tab,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() => _tab = i),
                      destinations: [
                        for (final (icon, label) in tabs)
                          NavigationRailDestination(
                            icon: Icon(icon),
                            label: Text(label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (final (icon, label) in tabs)
                      NavigationDestination(icon: Icon(icon), label: label),
                  ],
                ),
        ),
      ),
    );
  }
}

AdminRepository _admin(BuildContext context) => SessionScope.of(context).admin;

Future<void> _run(
  BuildContext context,
  Future<void> Function() action,
  String done,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } on AppFailure catch (f) {
    messenger.showSnackBar(SnackBar(content: Text(f.message)));
  }
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  bool destructive = false,
}) {
  // No controller: it would be disposed while the dialog animates out.
  var text = '';
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(
        onChanged: (v) => text = v,
        maxLength: 300,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialog).colorScheme.error,
                  foregroundColor: Theme.of(dialog).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(dialog, text),
          child: Text(confirm),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Requests

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  // All requests are watched so "request #n" counts every request a user
  // has ever sent; the pending view filters them on the device.
  late final Stream<List<PremiumRequest>> _all = _admin(context)
      .watchRequests();
  bool _pendingOnly = true;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PremiumRequest>>(
      stream: _all,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return ErrorView(
            message: e is AppFailure ? e.message : "Couldn't load requests.",
          );
        }
        final all = snap.data;
        if (all == null) return const LoadingView();
        final numbers = PremiumGrant.requestNumbers(all);
        final pending = all.where((r) => r.isPending).length;
        final shown = _pendingOnly
            ? all.where((r) => r.isPending).toList()
            : all;
        return ListView(
          padding: pagePadding(context),
          children: [
            PageBody(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    expandedInsets: EdgeInsets.zero,
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text('Pending ($pending)'),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('All (${all.length})'),
                      ),
                    ],
                    selected: {_pendingOnly},
                    onSelectionChanged: (s) =>
                        setState(() => _pendingOnly = s.first),
                  ),
                  const SizedBox(height: Space.lg),
                  if (shown.isEmpty)
                    EmptyState(
                      compact: true,
                      icon: Icons.inbox_rounded,
                      title: _pendingOnly
                          ? 'No pending requests'
                          : 'No requests yet',
                      message: 'Free-trial and payment requests from users appear here.',
                    )
                  else
                    for (final r in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: RequestCard(
                          key: ValueKey(r.id),
                          request: r,
                          number: numbers[r.id] ?? 1,
                        ),
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

class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, required this.number});

  final PremiumRequest request;

  /// How many requests this user has sent up to and including this one.
  final int number;

  Future<void> _approve(BuildContext context) async {
    final config = context.read<MembershipCubit>().state.config;
    final r = request;
    final grant = r.type == PremiumRequestType.trial
        ? 'a ${config.trialDays}-day free trial'
        : '1 year of premium';
    final ok = await showConfirmDialog(
      context,
      title: 'Approve request?',
      message: r.type == PremiumRequestType.payment
          ? 'Check that ${rupees(r.amountPaise ?? 0)} with UPI reference '
                '${r.upiRef} reached your account before approving. '
                '${r.email} will get $grant.'
          : '${r.email} will get $grant.',
      confirmLabel: 'Approve',
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => _admin(context).approve(r, config: config),
      'Approved – premium is now active for ${r.email}',
    );
  }

  Future<void> _reject(BuildContext context) async {
    final note = await _askText(
      context,
      title: 'Reject request?',
      label: 'Reason (optional, shown to the user)',
      confirm: 'Reject',
      destructive: true,
    );
    if (note == null || !context.mounted) return;
    await _run(
      context,
      () => _admin(context).reject(request, note: note),
      'Request rejected',
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    final c = context.colors;
    final payment = r.type == PremiumRequestType.payment;
    final statusColor = switch (r.status) {
      PremiumRequestStatus.pending => c.tertiary,
      PremiumRequestStatus.approved => c.primary,
      PremiumRequestStatus.rejected => c.error,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: c.secondaryContainer,
                  foregroundColor: c.onSecondaryContainer,
                  child: Icon(
                    payment
                        ? Icons.currency_rupee_rounded
                        : Icons.card_giftcard_rounded,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: InkWell(
                    onTap: () => showUserDetail(
                      context,
                      uid: r.uid,
                      title: r.displayName.isEmpty ? r.email : r.displayName,
                      subtitle: r.email,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.displayName.isEmpty ? r.email : r.displayName,
                          style: context.text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          r.email,
                          style: context.text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                _Pill(label: r.status.label, color: statusColor),
              ],
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                _Pill(
                  label: payment
                      ? 'Payment ${rupees(r.amountPaise ?? 0)}'
                      : 'Free trial',
                  color: c.secondary,
                ),
                _Pill(
                  label: number == 1
                      ? 'First request'
                      : 'Request #$number from this user',
                  color: number > 2 ? c.error : c.outline,
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (payment && r.upiRef != null)
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      'UPI ref: ${r.upiRef}',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy reference',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: r.upiRef!)),
                  ),
                ],
              ),
            if (r.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Text('“${r.message}”', style: context.text.bodyMedium),
              ),
            Text('Sent ${_date(r.createdAt)}', style: context.text.bodySmall),
            if (!r.isPending)
              Text(
                '${r.status.label} ${_date(r.decidedAt)}'
                '${r.adminNote == null ? '' : ' · ${r.adminNote}'}',
                style: context.text.bodySmall,
              ),
            if (r.isPending) ...[
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(context),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _approve(context),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
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

// ---------------------------------------------------------------------------
// Users

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  late final Stream<List<AdminUser>> _users = _admin(context).watchUsers();
  late final Stream<Set<String>> _banned = _admin(context).watchBannedUids();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: _banned,
      builder: (context, bannedSnap) => StreamBuilder<List<AdminUser>>(
        stream: _users,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(
              message: e is AppFailure ? e.message : "Couldn't load users.",
            );
          }
          final users = snap.data;
          if (users == null) return const LoadingView();
          final banned = bannedSnap.data ?? const {};
          final shown = users.where((u) => u.matches(_query)).toList();
          return ListView(
            padding: pagePadding(context),
            children: [
              PageBody(
                maxWidth: 760,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search by name or email',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      '${users.length} users · ${banned.length} banned',
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: Space.sm),
                    Card(
                      child: Column(
                        children: [
                          for (final u in shown)
                            ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  (u.displayName.isNotEmpty
                                          ? u.displayName
                                          : u.email.isNotEmpty
                                          ? u.email
                                          : '?')
                                      .characters
                                      .first
                                      .toUpperCase(),
                                ),
                              ),
                              title: Text(
                                u.displayName.isEmpty
                                    ? '(no name)'
                                    : u.displayName,
                              ),
                              subtitle: Text(
                                u.email.isEmpty
                                    ? 'Email not synced yet'
                                    : u.email,
                              ),
                              trailing: banned.contains(u.uid)
                                  ? _Pill(
                                      label: 'Banned',
                                      color: context.colors.error,
                                    )
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: () => showUserDetail(
                                context,
                                uid: u.uid,
                                title: u.displayName.isEmpty
                                    ? u.email
                                    : u.displayName,
                                subtitle: u.email,
                              ),
                            ),
                          if (shown.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(Space.xl),
                              child: Text('No users match.'),
                            ),
                        ],
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

Future<void> showUserDetail(
  BuildContext context, {
  required String uid,
  required String title,
  required String subtitle,
}) {
  final admin = _admin(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _UserDetail(admin: admin, uid: uid, title: title, subtitle: subtitle),
  );
}

class _UserDetail extends StatefulWidget {
  const _UserDetail({
    required this.admin,
    required this.uid,
    required this.title,
    required this.subtitle,
  });

  final AdminRepository admin;
  final String uid;
  final String title;
  final String subtitle;

  @override
  State<_UserDetail> createState() => _UserDetailState();
}

class _UserDetailState extends State<_UserDetail> {
  late Future<AdminUserDetail> _detail = widget.admin.userDetail(widget.uid);
  bool _busy = false;

  Future<void> _act(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    await _run(context, action, done);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _detail = widget.admin.userDetail(widget.uid);
    });
  }

  Future<void> _grant(AdminUserDetail d) async {
    final days = await showDialog<int>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Give premium for'),
        children: [
          for (final (days, label) in const [
            (3, '3 days'),
            (30, '1 month'),
            (365, '1 year'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, days),
              child: Text(label),
            ),
        ],
      ),
    );
    if (days == null) return;
    final now = DateTime.now();
    final current = d.entitlement.isPremium(now)
        ? d.entitlement.expiresAt
        : null;
    final until = PremiumGrant.paidExpiry(
      now: now,
      currentExpiry: current,
      days: days,
    );
    await _act(
      () => widget.admin.setPremium(widget.uid, until),
      'Premium active until ${_date(until)}',
    );
  }

  Future<void> _ban() async {
    final reason = await _askText(
      context,
      title: 'Ban this user?',
      label: 'Reason (shown to the user)',
      confirm: 'Ban',
      destructive: true,
    );
    if (reason == null) return;
    await _act(
      () => widget.admin.ban(widget.uid, reason: reason),
      'User banned',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminUserDetail>(
      future: _detail,
      builder: (context, snap) {
        final d = snap.data;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: context.text.titleLarge),
              Text(widget.subtitle, style: context.text.bodySmall),
              const SizedBox(height: Space.lg),
              if (snap.hasError)
                Text(
                  snap.error is AppFailure
                      ? (snap.error! as AppFailure).message
                      : "Couldn't load this user.",
                )
              else if (d == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                _detailRow(
                  context,
                  'Premium',
                  d.entitlement.isPremium(DateTime.now())
                      ? 'Active until ${_date(d.entitlement.expiresAt)}'
                            '${d.entitlement.source == null ? '' : ' (${d.entitlement.source})'}'
                      : 'Free plan',
                ),
                _detailRow(context, 'Requests sent', '${d.requests.length}'),
                _detailRow(context, 'Trials approved', '${d.trialsApproved}'),
                _detailRow(
                  context,
                  'Status',
                  d.ban == null
                      ? 'Active'
                      : 'Banned ${_date(d.ban!.bannedAt)}'
                            '${d.ban!.reason == null ? '' : ' – ${d.ban!.reason}'}',
                ),
                const SizedBox(height: Space.lg),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _grant(d),
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Give premium'),
                ),
                if (d.entitlement.isPremium(DateTime.now())) ...[
                  const SizedBox(height: Space.sm),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            () => widget.admin.setPremium(widget.uid, null),
                            'Premium removed',
                          ),
                    child: const Text('Remove premium'),
                  ),
                ],
                const SizedBox(height: Space.sm),
                if (d.ban == null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                    ),
                    onPressed: _busy ? null : _ban,
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Ban user'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            () => widget.admin.unban(widget.uid),
                            'User unbanned',
                          ),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Unban user'),
                  ),
                if (d.requests.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  Text('Request history', style: context.text.titleSmall),
                  for (final r in d.requests)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        r.type == PremiumRequestType.payment
                            ? 'Payment ${rupees(r.amountPaise ?? 0)}'
                            : 'Free trial',
                      ),
                      subtitle: Text(_date(r.createdAt)),
                      trailing: Text(r.status.label),
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: context.text.bodyMedium),
            ),
            Expanded(child: Text(value, style: context.text.titleSmall)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Settings

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _form = GlobalKey<FormState>();
  late final PremiumConfig _initial = context
      .read<MembershipCubit>()
      .state
      .config;
  late final _price = TextEditingController(
    text: (_initial.pricePaise / 100).toStringAsFixed(
      _initial.pricePaise % 100 == 0 ? 0 : 2,
    ),
  );
  late final _upi = TextEditingController(text: _initial.upiId);
  late final _payee = TextEditingController(text: _initial.payeeName);
  late final _trial = TextEditingController(text: '${_initial.trialDays}');
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    _upi.dispose();
    _payee.dispose();
    _trial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final paise = (double.parse(_price.text.trim()) * 100).round();
    await _run(
      context,
      () => _admin(context).saveConfig(
        PremiumConfig(
          pricePaise: paise,
          upiId: _upi.text.trim(),
          payeeName: _payee.text.trim(),
          trialDays: int.parse(_trial.text.trim()),
        ),
      ),
      'Settings saved',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: pagePadding(context),
      children: [
        PageBody(
          maxWidth: 560,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Premium plan', style: context.text.titleMedium),
                const SizedBox(height: Space.sm),
                Text(
                  'Users see these details on the Premium screen. Changing '
                  'the price applies to new payments only.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Space.lg),
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Price per year',
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    final n = double.tryParse(v?.trim() ?? '');
                    if (n == null || n < 1 || n > 100000) {
                      return 'Enter a price between ₹1 and ₹1,00,000';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _upi,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID to receive payments',
                    hintText: 'name@bank',
                    prefixIcon: Icon(Icons.qr_code_2_rounded),
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return null;
                    return RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(s)
                        ? null
                        : 'Enter a UPI ID like name@okaxis';
                  },
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _payee,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Payee name shown in UPI apps',
                  ),
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _trial,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Free trial length (days)',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    return n == null || n < 1 || n > 30
                        ? 'Enter 1 to 30 days'
                        : null;
                  },
                ),
                const SizedBox(height: Space.xl),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save settings'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
