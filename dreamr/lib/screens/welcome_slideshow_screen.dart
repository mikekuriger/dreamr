// screens/welcome_slideshow_screen.dart
import 'package:flutter/material.dart';
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

  final List<_TourPageData> _pages = const [
    _TourPageData(
      title: 'Capture your dreams',
      body: 'Write down your dreams in seconds, any time of night or day. Dreamr keeps them all in one place.',
      icon: Icons.bedtime,
    ),
    _TourPageData(
      title: 'AI dream insights',
      body: 'Get AI-powered interpretations, themes, and emotional patterns—personalized to you.',
      icon: Icons.psychology,
    ),
    _TourPageData(
      title: 'Images & journal',
      body: 'Turn dreams into surreal images and browse your dream history in a visual gallery.',
      icon: Icons.image,
    ),
  ];

  void _goNext() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  void _skip() {
    _finish();
  }

  Future<void> _finish() async {
    // At this point WelcomeTourPrefs.markSeen() was already called
    // by the previous screen, so just go to app.
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
    return Scaffold(
      backgroundColor: AppColors.purple950,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Top bar: Skip
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF82D9FF),
                    ),
                    child: const Text('Skip'),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Quick tour',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return _buildPage(page);
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF82D9FF)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 16),

              // Next / Done button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _goNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple600,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1
                        ? 'Start using Dreamr'
                        : 'Next',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(_TourPageData page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          page.icon,
          size: 80,
          color: const Color(0xFF82D9FF),
        ),
        const SizedBox(height: 24),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}

class _TourPageData {
  final String title;
  final String body;
  final IconData icon;

  const _TourPageData({
    required this.title,
    required this.body,
    required this.icon,
  });
}
