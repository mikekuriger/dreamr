// screens/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/screens/welcome_slideshow_screen.dart';
import 'package:dreamr/widgets/main_scaffold.dart';
import 'package:dreamr/theme/colors.dart';

/// SharedPreferences helper for the welcome tour.
class WelcomeTourPrefs {
  static const String _seenKey = 'welcome_tour_seen_v1';

  static Future<bool> hasSeenTour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }
}

/// Helper used by SplashScreen/Login to decide whether to show the welcome
/// page or jump straight into the main app.
Future<void> navigateToPostLoginDestination(BuildContext context) async {
  final hasSeen = await WelcomeTourPrefs.hasSeenTour();
  // final hasSeen = false;

  if (hasSeen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MainScaffold(initialIndex: 0),
      ),
    );
  } else {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const WelcomeTourScreen(),
      ),
    );
  }
}

class WelcomeTourScreen extends StatefulWidget {
  const WelcomeTourScreen({super.key});

  @override
  State<WelcomeTourScreen> createState() => _WelcomeTourScreenState();
}

// class _WelcomeTourScreenState extends State<WelcomeTourScreen> {
class _WelcomeTourScreenState extends State<WelcomeTourScreen> with SingleTickerProviderStateMixin {

  bool _submitting = false;
  String? _userName;

  late final AnimationController _anim;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _bodyFade;
  late final Animation<Offset> _bodySlide;
  late final Animation<double> _buttonsFade;
  late final Animation<Offset> _buttonsSlide;


 @override
  void initState() {
    super.initState();
    _loadProfile();

// Preload app icon for smoother transition later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/icon.png'), context);
    });

    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _titleFade = CurvedAnimation(parent: _anim, curve: const Interval(0.00, 0.45, curve: Curves.easeOut));
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _anim, curve: const Interval(0.00, 0.45, curve: Curves.easeOut)),
    );

    _bodyFade = CurvedAnimation(parent: _anim, curve: const Interval(0.15, 0.70, curve: Curves.easeOut));
    _bodySlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _anim, curve: const Interval(0.15, 0.70, curve: Curves.easeOut)),
    );

    _buttonsFade = CurvedAnimation(parent: _anim, curve: const Interval(0.35, 1.00, curve: Curves.easeOut));
    _buttonsSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _anim, curve: const Interval(0.35, 1.00, curve: Curves.easeOut)),
    );

    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }


  /// Load first name from API.
  Future<void> _loadProfile() async {
    try {
      final data = await ApiService.getProfile();
      setState(() {
        _userName = data['first_name'] ?? '';
      });
    } catch (e) {
      debugPrint('WelcomeTour: failed to load profile: $e');
    }
  }


  /// Skip: no profile updates, mark welcome as seen, go into app.
  Future<void> _onSkip() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await WelcomeTourPrefs.markSeen();
    } catch (e) {
      debugPrint('WelcomeTour: failed to mark seen on skip: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MainScaffold(initialIndex: 0),
      ),
    );
  }

  /// Take tour: do NOT save, just mark welcome as seen and go to slideshow.
  Future<void> _onTakeTour() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await WelcomeTourPrefs.markSeen();
    } catch (e) {
      debugPrint('WelcomeTour: failed to mark seen on tour: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const WelcomeSlideshowScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String titleText = (_userName != null && _userName!.isNotEmpty)
        ? 'Welcome $_userName'
        : 'Welcome to Dreamr';


    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // App Icon
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.purple600.withValues(alpha: 0.4),
                        blurRadius: 70,
                        spreadRadius: 40,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Welcome Title
                FadeTransition(
                  opacity: _titleFade,
                  // child: SlideTransition(
                  //   position: _titleSlide,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.98, end: 1.0).animate(_titleFade),
                    child: Text(
                      titleText,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Welcome Message
                FadeTransition(
                  opacity: _bodyFade,
                  child: SlideTransition(
                    position: _bodySlide,
                    child: const Column(
                      children: [
                        Text(
                          'Your dreams are trying to tell you something.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.25,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Capture them fast, spot patterns over time, and connect them to real life.\n'
                          'Explore meaning with AI insights and dream-inspired visuals.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),


                const SizedBox(height: 36),

                // Secondary actions
                // Secondary actions
                FadeTransition(
                  opacity: _buttonsFade,
                  child: SlideTransition(
                    position: _buttonsSlide,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.purple800.withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: TextButton(
                            onPressed: _submitting ? null : _onTakeTour,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.purple200.withValues(alpha: 1),
                            ),
                            child: const Text('Take a quick tour'),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF82D9FF).withValues(alpha: 0.15),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: TextButton(
                            onPressed: _submitting ? null : _onSkip,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF82D9FF),
                            ),
                            child: const Text('Skip for now'),
                          ),
                        ),
                      ],
                    ),
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