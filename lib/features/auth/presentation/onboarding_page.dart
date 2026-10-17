import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_gate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';

class _Slide {
  const _Slide({
    required this.title,
    required this.text,
    required this.icon,
    required this.orbit,
    required this.colors,
  });

  final String title;
  final String text;
  final IconData icon;
  final List<IconData> orbit;
  final List<Color> colors;
}

const _slides = [
  _Slide(
    title: 'Every Expense, Under Control',
    text:
        'Record daily spending in seconds and keep everything organized in '
        'one simple place.',
    icon: Icons.add_card_rounded,
    orbit: [
      Icons.restaurant_rounded,
      Icons.directions_bus_rounded,
      Icons.shopping_bag_rounded,
    ],
    colors: [Color(0xFF2F6BFF), Color(0xFF1238B8)],
  ),
  _Slide(
    title: 'See Where Your Money Goes',
    text:
        'Explore daily, weekly, and monthly summaries to understand your '
        'spending habits.',
    icon: Icons.insights_rounded,
    orbit: [
      Icons.pie_chart_rounded,
      Icons.savings_rounded,
      Icons.bar_chart_rounded,
    ],
    colors: [Color(0xFF8B5CF6), Color(0xFF5B21B6)],
  ),
  _Slide(
    title: 'Build a Better Money Habit',
    text:
        'Use gentle reminders to stay consistent and complete your daily '
        'expense tracking.',
    icon: Icons.notifications_active_rounded,
    orbit: [
      Icons.calendar_month_rounded,
      Icons.task_alt_rounded,
      Icons.local_fire_department_rounded,
    ],
    colors: [Color(0xFF10B981), Color(0xFF047857)],
  ),
  _Slide(
    title: 'Keep Lending and Borrowing Organized',
    text:
        'Remember money you have lent to others and money you need to '
        'repay.',
    icon: Icons.handshake_rounded,
    orbit: [
      Icons.south_west_rounded,
      Icons.north_east_rounded,
      Icons.currency_rupee_rounded,
    ],
    colors: [Color(0xFFFF8A3D), Color(0xFFD9480F)],
  ),
];

/// Intro slides shown once on a device to people who are not signed in.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.onDone});

  /// Replay mode (from Settings): called instead of marking the intro as
  /// seen, which it already is.
  final VoidCallback? onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() => setState(() => _page = _pages.page ?? 0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _float.dispose();
    super.dispose();
  }

  bool get _isLast => _page.round() == _slides.length - 1;

  void _finish() {
    final onDone = widget.onDone;
    if (onDone != null) return onDone();
    context.read<OnboardingActions>().complete();
  }

  bool get _isFirst => _page.round() == 0;

  void _back() {
    if (_isFirst) return;
    _pages.previousPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_isLast) return _finish();
    _pages.nextPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Background colour blends smoothly between slides while swiping.
    final i = _page.floor().clamp(0, _slides.length - 1);
    final j = (i + 1).clamp(0, _slides.length - 1);
    final t = _page - i;
    final top = Color.lerp(_slides[i].colors[0], _slides[j].colors[0], t)!;
    final bottom = Color.lerp(_slides[i].colors[1], _slides[j].colors[1], t)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: Row(
                    children: [
                      AnimatedOpacity(
                        opacity: _isFirst ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: IconButton(
                          color: Colors.white,
                          tooltip: 'Back',
                          onPressed: _isFirst ? null : _back,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: _isLast ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isLast ? null : _finish,
                          child: const Text('Skip'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    itemBuilder: (context, index) => _SlideView(
                      slide: _slides[index],
                      float: _float,
                      // 0 when centred, ±1 one page away: drives parallax.
                      offset: (_page - index).clamp(-1, 1).toDouble(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    Space.lg,
                    Space.xxl,
                    Space.xxl,
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        label:
                            'Slide ${_page.round() + 1} of ${_slides.length}',
                        child: Row(
                          children: [
                            for (var k = 0; k < _slides.length; k++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.only(right: 6),
                                width: _page.round() == k ? 26 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: _page.round() == k ? 1 : 0.45,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    Radii.pill,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: bottom,
                            minimumSize: const Size(56, 56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.xl,
                            ),
                          ),
                          onPressed: _next,
                          child: _isLast
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Get started'),
                                    SizedBox(width: Space.sm),
                                    Icon(Icons.arrow_forward_rounded),
                                  ],
                                )
                              : const Icon(
                                  Icons.arrow_forward_rounded,
                                  semanticLabel: 'Next',
                                ),
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

class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.slide,
    required this.float,
    required this.offset,
  });

  final _Slide slide;
  final Animation<double> float;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final fade = 1 - offset.abs();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: Offset(offset * -80, 0),
            child: _Illustration(slide: slide, float: float),
          ),
          const SizedBox(height: Space.xxxl + Space.lg),
          Opacity(
            opacity: fade.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(offset * -40, 0),
              child: Column(
                children: [
                  Text(
                    slide.title,
                    textAlign: TextAlign.center,
                    style: context.text.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    slide.text,
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted-glass circle with the main icon, gently floating, and three small
/// icons orbiting it.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.slide, required this.float});

  final _Slide slide;
  final Animation<double> float;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 260,
        child: AnimatedBuilder(
          animation: float,
          builder: (context, _) {
            final t = float.value * 2 * math.pi;
            return Stack(
              alignment: Alignment.center,
              children: [
                // Soft glow.
                Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                for (var k = 0; k < slide.orbit.length; k++)
                  Transform.translate(
                    offset: Offset(
                      math.cos(t + k * 2 * math.pi / 3) * 108,
                      math.sin(t + k * 2 * math.pi / 3) * 108,
                    ),
                    child: _GlassBubble(size: 52, icon: slide.orbit[k]),
                  ),
                Transform.translate(
                  offset: Offset(0, math.sin(t * 2) * 8),
                  child: _GlassBubble(size: 140, icon: slide.icon),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GlassBubble extends StatelessWidget {
  const _GlassBubble({required this.size, required this.icon});

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.45),
                Colors.white.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Icon(icon, size: size * 0.48, color: Colors.white),
        ),
      ),
    );
  }
}
