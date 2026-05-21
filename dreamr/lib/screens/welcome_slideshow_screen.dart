// screens/welcome_slideshow_screen.dart
//
// Four-slide onboarding tour. Each slide layers an animated visual over
// a soft purple gradient. The visual prefers a Lottie animation if its
// asset exists (drop .json files into assets/animations/ to enable),
// otherwise it falls back to a scale-in + pulsing-glow Material icon
// in Dreamr's palette so the slideshow always looks alive.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:dreamr/widgets/main_scaffold.dart';
import 'package:dreamr/theme/colors.dart';

class WelcomeSlideshowScreen extends StatefulWidget {
  const WelcomeSlideshowScreen({super.key});

  @override
  State<WelcomeSlideshowScreen> createState() => _WelcomeSlideshowScreenState();
}

class _WelcomeSlideshowScreenState extends State<WelcomeSlideshowScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  // Lottie paths are optional. If the file isn't present, the icon
  // fallback inside _OnboardingVisual kicks in via Lottie's errorBuilder.
  static const _gold = Color(0xFFFFD68A);
  static const _starlight = Color(0xFFB39BFF);

  final List<_SlideData> _pages = const [
    _SlideData(
      title: 'Capture what you remember',
      body: 'Write or speak your dreams the moment you wake. Everything stays private in your journal.',
      lottieAsset: 'assets/animations/onboarding_capture.json',
      icon: Icons.nights_stay_rounded,
      accent: _starlight,
    ),
    _SlideData(
      title: 'See what your mind is telling you',
      body: 'Personalized AI analysis, emotional tone, and an interpreter who fits your style.',
      lottieAsset: 'assets/animations/onboarding_analyze.json',
      icon: Icons.auto_awesome_rounded,
      accent: _gold,
    ),
    _SlideData(
      title: 'Watch patterns emerge',
      body: 'Recurring symbols, emotional themes, and a weekly reflection across your whole journal.',
      lottieAsset: 'assets/animations/onboarding_patterns.json',
      icon: Icons.insights_rounded,
      accent: _starlight,
    ),
    _SlideData(
      title: 'Turn dreams into art',
      body: 'Visualize each dream in a style you choose, then explore deeper with the AI.',
      lottieAsset: 'assets/animations/onboarding_art.json',
      icon: Icons.palette_rounded,
      accent: _gold,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  Future<void> _finish() async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MainScaffold(initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _pages[_currentPage].accent;
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.purple950,
              const Color(0xFF0B0418),
              Colors.black,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Soft radial highlight behind the visual, tinted by the active
            // slide's accent for a subtle "the room shifts color" effect.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.3),
                      radius: 0.9,
                      colors: [
                        accent.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  children: [
                    // Top bar: Skip
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _skip,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(alpha: 0.7),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: _pages.length,
                        onPageChanged: (i) => setState(() => _currentPage = i),
                        itemBuilder: (context, i) {
                          final page = _pages[i];
                          return _SlideView(
                            key: ValueKey('slide-$i'),
                            data: page,
                            isActive: i == _currentPage,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Page dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (i) {
                        final active = i == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? accent
                                : Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    // Primary CTA
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _goNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.purple600,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(
                          _currentPage == _pages.length - 1
                              ? 'Start dreaming'
                              : 'Next',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _SlideData data;
  final bool isActive;
  const _SlideView({super.key, required this.data, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _OnboardingVisual(
          lottieAsset: data.lottieAsset,
          icon: data.icon,
          glowColor: data.accent,
          isActive: isActive,
        ),
        const SizedBox(height: 36),
        Text(
          data.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            data.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// Animated visual for a single slide. Loads a Lottie file if available
/// (drop `.json` files into assets/animations/) and otherwise renders an
/// animated Material icon with a scale-in entry and an infinite pulse
/// glow tinted by the slide's accent color.
class _OnboardingVisual extends StatefulWidget {
  final String? lottieAsset;
  final IconData icon;
  final Color glowColor;
  final bool isActive;

  const _OnboardingVisual({
    required this.lottieAsset,
    required this.icon,
    required this.glowColor,
    required this.isActive,
  });

  @override
  State<_OnboardingVisual> createState() => _OnboardingVisualState();
}

class _OnboardingVisualState extends State<_OnboardingVisual>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    if (widget.isActive) {
      _entry.forward();
    } else {
      _entry.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_OnboardingVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _entry.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entry, _pulse]),
      builder: (context, _) {
        final entry = Curves.easeOutBack.transform(_entry.value);
        // Smooth pulse using a sine so the glow breathes instead of
        // ticking. 0..1 → 0.4..1.0 envelope.
        final pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi));
        return Opacity(
          opacity: _entry.value,
          child: Transform.scale(
            scale: entry,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.glowColor.withValues(alpha: 0.35 * pulse),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                  BoxShadow(
                    color: widget.glowColor.withValues(alpha: 0.12 * pulse),
                    blurRadius: 90,
                    spreadRadius: 28,
                  ),
                ],
              ),
              child: _visual(),
            ),
          ),
        );
      },
    );
  }

  Widget _visual() {
    final iconFallback = Center(
      child: Icon(widget.icon, size: 96, color: widget.glowColor),
    );
    final asset = widget.lottieAsset;
    if (asset == null) return iconFallback;
    return Lottie.asset(
      asset,
      width: 180,
      height: 180,
      fit: BoxFit.contain,
      // When the asset isn't bundled yet, gracefully show the icon.
      errorBuilder: (_, _, _) => iconFallback,
    );
  }
}

class _SlideData {
  final String title;
  final String body;
  final String? lottieAsset;
  final IconData icon;
  final Color accent;

  const _SlideData({
    required this.title,
    required this.body,
    required this.lottieAsset,
    required this.icon,
    required this.accent,
  });
}
