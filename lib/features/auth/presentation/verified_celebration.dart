import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../cubit/auth_cubit.dart';

/// Plays the "Email verified" celebration once, the first time the signed-in
/// shell appears after the address was verified in this session.
class VerifiedCelebrationGate extends StatefulWidget {
  const VerifiedCelebrationGate({super.key, required this.child});

  final Widget child;

  @override
  State<VerifiedCelebrationGate> createState() =>
      _VerifiedCelebrationGateState();
}

class _VerifiedCelebrationGateState extends State<VerifiedCelebrationGate> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (!mounted || _showing) return;
    final auth = context.read<AuthCubit>();
    if (!auth.state.justVerified) return;
    _showing = true;
    auth.acknowledgeVerified();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Email verified',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const _Celebration(),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (p, c) => !p.justVerified && c.justVerified,
      listener: (_, _) => _maybeShow(),
      child: widget.child,
    );
  }
}

class _Celebration extends StatefulWidget {
  const _Celebration();

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  Timer? _close;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _close = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final green = context.appColors.success;
    final pop = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.5, curve: Curves.elasticOut),
    );
    final check = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.25, 0.6, curve: Curves.easeOutCubic),
    );
    final burst = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.2, 1, curve: Curves.easeOutCubic),
    );
    return Semantics(
      liveRegion: true,
      label: 'Email verified. Welcome to Daily Expense Buddy.',
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.black.withValues(alpha: 0.25),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 220,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Stack(
                      alignment: Alignment.center,
                      children: [
                        // Confetti-like burst of coloured dots.
                        for (var i = 0; i < 14; i++)
                          Transform.translate(
                            offset: Offset.fromDirection(
                              i * 2 * math.pi / 14,
                              40 + 70 * burst.value,
                            ),
                            child: Opacity(
                              opacity: (1 - burst.value).clamp(0, 1),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: context.appColors.category(i),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        Transform.scale(
                          scale: pop.value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: green,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: green.withValues(alpha: 0.5),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                            child: CustomPaint(
                              painter: _CheckPainter(check.value),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: check,
                  child: Column(
                    children: [
                      Text(
                        'Email verified!',
                        style: context.text.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Welcome to Daily Expense Buddy',
                        style: context.text.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a white tick that grows from left to right as [progress] goes 0→1.
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final p1 = Offset(size.width * 0.28, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.67);
    final p3 = Offset(size.width * 0.73, size.height * 0.36);
    final path = Path()..moveTo(p1.dx, p1.dy);
    final first = (p2 - p1).distance;
    final second = (p3 - p2).distance;
    final len = (first + second) * progress;
    if (len <= first) {
      final q = p1 + (p2 - p1) * (len / first);
      path.lineTo(q.dx, q.dy);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final q = p2 + (p3 - p2) * ((len - first) / second);
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
