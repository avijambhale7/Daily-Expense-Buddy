import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../export/export_dialog.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget block(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: Space.xs),
          Text(body, style: context.text.bodyMedium),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & your data')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 680,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(
                      'What we store',
                      'Your name and email (for sign-in), and the data you enter: expenses '
                          '(amount, currency, category, date, optional merchant, note and '
                          'payment method), custom categories, budgets, daily completion '
                          'statuses and your preferences.',
                    ),
                    block(
                      'Where it is stored',
                      'In Google Firebase (Authentication and Cloud Firestore) under your '
                          'account. Security rules allow only you to read or change your '
                          'records. On phones a copy is cached on the device for offline use '
                          'and removed when you log out; in the browser nothing is cached '
                          'after you close the tab.',
                    ),
                    block(
                      'What we do not collect',
                      'No bank connections, no location, no contacts and no advertising '
                          'trackers. Passwords are handled by Firebase Authentication and '
                          'never stored by the app.',
                    ),
                    block(
                      'Sync is not a backup',
                      'Syncing keeps your devices up to date, so deleting an expense deletes '
                          'it everywhere. Use CSV export to keep your own copy.',
                    ),
                    block(
                      'Deleting your data',
                      'Account & security → Delete account removes your login and all of '
                          'your records from our servers.',
                    ),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => showExportDialog(context),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Export my data'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go(Routes.account),
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Account & security'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
