import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_logo.dart';

/// Brand blue of the launch screen; matches the native Android splash so the
/// hand-over from the system splash is seamless.
const _splashTop = Color(0xFF1E63E9);
const _splashBottom = Color(0xFF0B2C8A);

/// Animated launch screen: the logo pops in with soft pulsing rings, then
/// the name and tagline slide up. Shown for a moment at every launch.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else if (!_intro.isAnimating && _intro.value == 0) {
      _intro.forward();
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Animation<double> _interval(double begin, double end, Curve curve) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end, curve: curve),
      );

  @override
  Widget build(BuildContext context) {
    final logoScale = _interval(0, 0.55, Curves.elasticOut);
    final logoFade = _interval(0, 0.25, Curves.easeOut);
    final textIn = _interval(0.4, 0.8, Curves.easeOutCubic);
    final taglineIn = _interval(0.6, 1, Curves.easeOutCubic);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _splashTop,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_splashTop, _splashBottom],
            ),
          ),
          child: Center(
            child: Semantics(
              label: 'Daily Expense Buddy is loading',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Expanding rings behind the logo.
                        for (final offset in const [0.0, 0.5])
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, _) {
                              final t = (_pulse.value + offset) % 1;
                              return Opacity(
                                opacity: (1 - t) * 0.35 * logoFade.value,
                                child: Container(
                                  width: 120 + 100 * t,
                                  height: 120 + 100 * t,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        FadeTransition(
                          opacity: logoFade,
                          child: ScaleTransition(
                            scale: Tween(
                              begin: 0.4,
                              end: 1.0,
                            ).animate(logoScale),
                            child: Container(
                              width: 132,
                              height: 132,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 30,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: const AppLogo(size: 96),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  _SlideFade(
                    animation: textIn,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Daily Expense '),
                          TextSpan(
                            text: 'Buddy',
                            style: TextStyle(
                              color: Colors.greenAccent.shade200,
                            ),
                          ),
                        ],
                      ),
                      style: context.text.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  _SlideFade(
                    animation: taglineIn,
                    child: Text(
                      'Track Today. Spend Smarter.',
                      style: context.text.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        letterSpacing: 0.4,
                      ),
                    ),
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

class _SlideFade extends StatelessWidget {
  const _SlideFade({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.6),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );
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
