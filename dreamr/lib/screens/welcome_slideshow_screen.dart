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
      title: 'Remember more dreams',
      body: 'Capture dreams fast—then keep everything organized in one private journal.',
      icon: Icons.nights_stay_rounded,
    ),
    _TourPageData(
      title: 'AI insights that feel personal',
      body: 'Themes, emotions, and patterns—grounded in what you wrote.',
      icon: Icons.psychology_alt_rounded,
    ),
    _TourPageData(
      title: 'Connect dreams to real life',
      body: 'Add Life Events and see how stress, change, and relationships show up at night.',
      icon: Icons.event_rounded,
    ),
    _TourPageData(
      title: 'Turn dreams into art',
      body: 'Generate surreal images from your dreams and browse them in a visual gallery.',
      icon: Icons.auto_awesome_rounded,
    ),
    _TourPageData(
      title: 'Find anything instantly',
      body: 'Search, sort, and revisit past dreams when patterns start repeating.',
      icon: Icons.manage_search_rounded,
    ),
    _TourPageData(
      title: 'Ask questions',
      body: 'Explore symbols, themes, and meaning. Learn',
      icon: Icons.question_answer_rounded,
    ),
    _TourPageData(
      title: 'Share when you want',
      body: 'Share dream images or entries with friends—or keep everything private.',
      icon: Icons.ios_share_rounded,
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
      backgroundColor: AppColors.black,
      // backgroundColor: AppColors.purple950,
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
                    backgroundColor: AppColors.purple700,
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
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF82D9FF).withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: const Color(0xFF82D9FF).withValues(alpha: 0.3),
                blurRadius: 60,
                spreadRadius: 20,
              ),
            ],
          ),
          child: Icon(
            page.icon,
            size: 80,
            color: const Color(0xFF82D9FF),
          ),
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
