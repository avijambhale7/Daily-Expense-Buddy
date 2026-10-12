import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_logo.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 96),
            SizedBox(height: Space.xxl),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the build has no Firebase configuration. Explains the exact
/// steps instead of pretending authentication works.
class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String text, [String? code]) => Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: context.colors.primaryContainer,
            child: Text(n, style: context.text.labelLarge),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: context.text.bodyLarge),
                if (code != null) ...[
                  const SizedBox(height: Space.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: SelectableText(
                      code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(size: 64, showName: true),
                  const SizedBox(height: Space.xxl),
                  Text(
                    'Firebase setup required',
                    style: context.text.headlineSmall,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    'This build has no Firebase configuration, so sign-in and '
                    'sync are not available yet. Complete these steps, then '
                    'rebuild the app.',
                    style: context.text.bodyLarge?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Space.xxl),
                  step(
                    '1',
                    'Install the Firebase and FlutterFire CLIs and log in.',
                    'npm install -g firebase-tools\nfirebase login\n'
                        'dart pub global activate flutterfire_cli',
                  ),
                  step(
                    '2',
                    'Generate lib/firebase_options.dart for your project.',
                    'flutterfire configure --platforms=android,ios,web',
                  ),
                  step(
                    '3',
                    'In the Firebase console enable Email/Password sign-in '
                        'and create a Cloud Firestore database.',
                  ),
                  step(
                    '4',
                    'Deploy the security rules and indexes.',
                    'firebase deploy --only firestore:rules,firestore:indexes',
                  ),
                  step(
                    '5',
                    'Or try everything locally with the Emulator Suite.',
                    'firebase emulators:start --project demo-daily-expense-buddy\n'
                        'flutter run --dart-define=USE_FIREBASE_EMULATOR=true',
                  ),
                  Text(
                    'Full instructions are in README.md.',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
