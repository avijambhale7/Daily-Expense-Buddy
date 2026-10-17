import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/membership.dart';
import '../../membership/membership_cubit.dart';

/// Premium status, free-trial requests and UPI payment.
///
/// Nothing here grants premium: users send a request (trial, or "I paid"
/// with the UPI reference) and an admin approves it, which writes
/// `users/{uid}/entitlements/premium`. Client writes there are denied.
class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  final _utr = TextEditingController();
  bool _refreshing = false;
  bool _sending = false;

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await context.read<EntitlementCubit>().refresh();
      if (mounted) showMessage(context, 'Premium status refreshed');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _send(Future<void> Function() action, String done) async {
    setState(() => _sending = true);
    try {
      await action();
      if (mounted) showMessage(context, done);
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _requestTrial(MembershipState m) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Request a free trial?',
      message:
          'An admin will review your request. Once approved you get every '
          'premium feature free for ${m.config.trialDays} days.',
      confirmLabel: 'Send request',
    );
    if (!ok || !mounted) return;
    final cubit = context.read<MembershipCubit>();
    await _send(
      cubit.requestTrial,
      'Request sent. You will get premium once an admin approves it.',
    );
  }

  Future<void> _openUpi(PremiumConfig config) async {
    final uri = config.upiPayUri(note: 'Daily Expense Buddy premium');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      showMessage(
        context,
        'No UPI app found. Pay to ${config.upiId} from any UPI app.',
      );
    }
  }

  Future<void> _submitPayment() async {
    final cubit = context.read<MembershipCubit>();
    await _send(
      () => cubit.requestActivation(upiRef: _utr.text),
      'Thanks! An admin will check your payment and activate premium.',
    );
    if (mounted) _utr.clear();
  }

  @override
  Widget build(BuildContext context) {
    final e = context.watch<EntitlementCubit>().state;
    final m = context.watch<MembershipCubit>().state;
    final now = context.read<AppDependencies>().now();
    final active = e.isPremium(now);
    final fmt = AppFormat.of(context);
    final price = rupees(m.config.pricePaise);
    final trialRequests = m.requests
        .where((r) => r.type == PremiumRequestType.trial)
        .length;

    Widget feature(String text, {required String tag, bool free = false}) =>
        ListTile(
          leading: Icon(
            free ? Icons.check_circle_rounded : Icons.workspace_premium_rounded,
            color: free ? context.appColors.success : context.colors.tertiary,
          ),
          title: Text(text),
          trailing: Text(tag, style: context.text.labelMedium),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusCard(
                  active: active,
                  title: active
                      ? (e.source == 'trial'
                            ? 'Your free trial is active'
                            : 'Premium is active')
                      : 'You are on the free plan',
                  subtitle: active && e.expiresAt != null
                      ? 'Until ${fmt.dateTime(e.expiresAt!)}'
                      : 'Premium: $price per year',
                  preview: e.developerPreview,
                ),
                const SizedBox(height: Space.lg),
                Card(
                  child: Column(
                    children: [
                      feature(
                        'Unlimited expenses, history and reports',
                        tag: 'Free',
                        free: true,
                      ),
                      feature(
                        'Reminders, calendar, budgets and loans',
                        tag: 'Free',
                        free: true,
                      ),
                      feature(
                        'Light, Dark and System themes · CSV export',
                        tag: 'Free',
                        free: true,
                      ),
                      feature(
                        'Ocean, Forest, Sunset, Lavender & Midnight themes',
                        tag: 'Premium',
                      ),
                      feature(
                        'Advanced reports and PDF statements',
                        tag: 'Premium',
                      ),
                      feature(
                        'Recurring expenses (rent, bills, EMIs)',
                        tag: 'Premium',
                      ),
                      feature('Savings goals', tag: 'Premium'),
                      feature('App lock with PIN', tag: 'Premium'),
                    ],
                  ),
                ),
                if (!active) ...[
                  const SizedBox(height: Space.lg),
                  _Section(
                    icon: Icons.card_giftcard_rounded,
                    title: 'Try premium free for ${m.config.trialDays} days',
                    children: [
                      Text(
                        'Send a request and an admin will switch on premium '
                        'for you.',
                        style: context.text.bodyMedium,
                      ),
                      if (trialRequests > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Text(
                            m.hasPendingTrial
                                ? 'Your request is waiting for approval.'
                                : 'You have sent $trialRequests trial '
                                      'request${trialRequests == 1 ? '' : 's'}.',
                            style: context.text.bodySmall,
                          ),
                        ),
                      const SizedBox(height: Space.md),
                      FilledButton.tonalIcon(
                        onPressed: _sending ? null : () => _requestTrial(m),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Request free trial'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.lg),
                _Section(
                  icon: Icons.currency_rupee_rounded,
                  title: active
                      ? 'Extend premium · $price / year'
                      : 'Get premium · $price / year',
                  children: [
                    if (!m.config.canPay)
                      Text(
                        'Payments will open soon.',
                        style: context.text.bodyMedium,
                      )
                    else ...[
                      Text(
                        '1. Pay $price by UPI to:',
                        style: context.text.bodyMedium,
                      ),
                      const SizedBox(height: Space.xs),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              m.config.upiId,
                              style: context.text.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy UPI ID',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: m.config.upiId),
                              );
                              showMessage(context, 'UPI ID copied');
                            },
                            icon: const Icon(Icons.copy_rounded),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openUpi(m.config),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: Text('Pay $price with a UPI app'),
                      ),
                      const SizedBox(height: Space.lg),
                      Text(
                        '2. Enter the UPI transaction ID (UTR) from your '
                        'payment receipt:',
                        style: context.text.bodyMedium,
                      ),
                      const SizedBox(height: Space.sm),
                      TextField(
                        controller: _utr,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'UPI transaction ID',
                          hintText: 'e.g. 412345678901',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      FilledButton.icon(
                        onPressed: _sending ? null : _submitPayment,
                        icon: const Icon(Icons.verified_rounded),
                        label: const Text("I've paid – activate premium"),
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        'An admin checks the payment and activates premium '
                        'for one year. Keep your UPI receipt until then.',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ],
                ),
                if (m.requests.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  _Section(
                    icon: Icons.history_rounded,
                    title: 'Your requests',
                    children: [
                      for (final r in m.requests)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(switch (r.status) {
                            PremiumRequestStatus.pending =>
                              Icons.hourglass_top_rounded,
                            PremiumRequestStatus.approved =>
                              Icons.check_circle_rounded,
                            PremiumRequestStatus.rejected =>
                              Icons.cancel_rounded,
                          }),
                          title: Text(
                            r.type == PremiumRequestType.trial
                                ? 'Free trial'
                                : 'Payment ${rupees(r.amountPaise ?? 0)}',
                          ),
                          subtitle: Text(
                            [
                              if (r.createdAt != null)
                                fmt.dateTime(r.createdAt!),
                              if (r.adminNote != null) r.adminNote!,
                            ].join(' · '),
                          ),
                          trailing: Text(r.status.label),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.lg),
                OutlinedButton.icon(
                  onPressed: _refreshing ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh premium status'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.active,
    required this.title,
    required this.subtitle,
    required this.preview,
  });

  final bool active;
  final String title;
  final String subtitle;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final on = context.colors.onTertiaryContainer;
    return Card(
      color: context.colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              active
                  ? Icons.workspace_premium_rounded
                  : Icons.workspace_premium_outlined,
              size: 40,
              color: on,
            ),
            const SizedBox(height: Space.md),
            Text(title, style: context.text.titleLarge?.copyWith(color: on)),
            Text(subtitle, style: context.text.bodyMedium?.copyWith(color: on)),
            if (preview)
              Text(
                'Developer preview (debug build only).',
                style: context.text.bodySmall?.copyWith(color: on),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: context.colors.primary),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(title, style: context.text.titleMedium)),
              ],
            ),
            const SizedBox(height: Space.md),
            ...children,
          ],
        ),
      ),
    );
  }
}
