// widgets/main_scaffold.dart
// import 'package:dreamr/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dreamr/services/dio_client.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/screens/dashboard_screen.dart';
import 'package:dreamr/screens/dream_journal_screen.dart';
import 'package:dreamr/screens/dream_journal_editor_screen.dart';
import 'package:dreamr/screens/dream_gallery_screen.dart';
import 'package:dreamr/screens/profile_screen.dart';
import 'package:dreamr/screens/settings_screen.dart';
import 'package:dreamr/screens/subscription_screen.dart';
import 'package:dreamr/screens/life_events_screen.dart';
import 'package:dreamr/screens/help_screen.dart';
import 'package:dreamr/screens/interpreters_screen.dart';
import 'package:dreamr/screens/image_style_selection_screen.dart';
import 'package:dreamr/screens/insights_screen.dart';
// import 'package:dreamr/constants.dart';
import 'package:dreamr/utils/session_manager.dart';
import 'package:dreamr/state/subscription_model.dart';

// Refresh triggers for each screen
final ValueNotifier<int> dreamEntryRefreshTrigger = ValueNotifier<int>(0);
final ValueNotifier<int> journalRefreshTrigger = ValueNotifier<int>(0);
final ValueNotifier<int> galleryRefreshTrigger = ValueNotifier<int>(0);
final ValueNotifier<int> profileRefreshTrigger = ValueNotifier<int>(0);
final ValueNotifier<int> editorRefreshTrigger = ValueNotifier<int>(0);
final ValueNotifier<int> settingsRefreshTrigger = ValueNotifier<int>(0);
final ValueNotifier<int> insightsRefreshTrigger = ValueNotifier<int>(0);

// Flipped by the AppBar search icon when the Journal tab is active.
// The journal screen listens and reveals an inline search field.
final ValueNotifier<bool> journalSearchActive = ValueNotifier<bool>(false);


class MainScaffold extends StatefulWidget {
  final int initialIndex;

  const MainScaffold({super.key, this.initialIndex = 0});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _selectedIndex;
  late final List<Widget> _views;
  bool _navEnabled = true;
  final ValueNotifier<bool> _dashboardActive = ValueNotifier(true);

  final GlobalKey _menuButtonKey = GlobalKey();

  bool _isIpadLike(BuildContext context) {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    return MediaQuery.of(context).size.shortestSide >= 600;
  }

  Future<void> _handleMenuSelection(String route) async {
    switch (route) {
      case '/editor':
        setState(() {
          editorRefreshTrigger.value++;
          _selectedIndex = 3;
        });
        break;
      case '/profile':
        setState(() {
          _selectedIndex = 4;
        });
        break;
      case '/settings':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SettingsScreen(
              refreshTrigger: settingsRefreshTrigger,
            ),
          ),
        );
        break;
      case '/subscription':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SubscriptionScreen(),
          ),
        );
        break;
      case '/help':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HelpScreen(),
          ),
        );
        break;
      case '/life-events':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const LifeEventsScreen(),
          ),
        );
        break;
      case '/interpreters':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const InterpretersScreen(),
          ),
        );
        break;
      case '/image-styles':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ImageStyleSelectionScreen(),
          ),
        );
        break;
      case '/login':
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        break;
      case 'logout':
        await performLogout(context);
        break;
    }
  }

  Future<void> _openHamburgerMenu() async {
    // Close keyboard first.
    FocusScope.of(context).unfocus();

    // iPad (iOS) sometimes immediately dismisses popup menus if we open the menu
    // in the same gesture cycle as the tap. A small delay avoids that.
    if (_isIpadLike(context)) {
      // Empirically: iPad needs a large delay to avoid the tap that opens the menu
      // also being treated as an "outside" tap that dismisses it immediately.
      await Future.delayed(const Duration(milliseconds: 400));
    }

    final buttonContext = _menuButtonKey.currentContext;
    if (buttonContext == null) return;

    final buttonBox = buttonContext.findRenderObject() as RenderBox?;
    if (buttonBox == null || !buttonBox.hasSize) return;

    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;

    final buttonRect = Rect.fromPoints(
      buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      buttonBox.localToGlobal(buttonBox.size.bottomRight(Offset.zero), ancestor: overlayBox),
    );

    final rawPosition = RelativeRect.fromRect(buttonRect, Offset.zero & overlayBox.size);
    final position = RelativeRect.fromLTRB(
      rawPosition.left,
      rawPosition.top + 30,
      rawPosition.right,
      rawPosition.bottom - 30,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.grey[850],
      items: const [
        PopupMenuItem(
          value: '/editor',
          child: Row(
            children: [
              Icon(Icons.archive_outlined, color: Colors.white),
              SizedBox(width: 8),
              Text('Hidden Dreams', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: '/profile',
          child: Row(
            children: [
              Icon(Icons.person_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Profile', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: '/settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, color: Colors.white),
              SizedBox(width: 8),
              Text('Settings', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: '/life-events',
          child: Row(
            children: [
              Icon(Icons.favorite_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Life Events', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: '/interpreters',
          child: Row(
            children: [
              Icon(Icons.psychology, color: Colors.white),
              SizedBox(width: 8),
              Text('Dream Interpreters', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: '/image-styles',
          child: Row(
            children: [
              Icon(Icons.palette_outlined, color: Colors.white),
              SizedBox(width: 8),
              Text('Image Styles', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: '/subscription',
          child: Row(
            children: [
              Icon(Icons.star_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Subscription', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: '/help',
          child: Row(
            children: [
              Icon(Icons.help_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Help', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.white),
              SizedBox(width: 8),
              Text('Logout', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );

    if (selected != null && mounted) {
      await _handleMenuSelection(selected);
    }
  }


  Widget _getTitleForIndex(int index) {
    String title;
    switch (index) {
      case 0:
        title = "Dreamr ✨";
        break;
      case 1:
        title = "Dreamr ✨ Journal ✍️";
        break;
      case 2:
        title = "Dreamr ✨ Gallery";
        break;
      // case 3:
      //   title = "Dreamr ✨ Help";
      //   break;
      // case 3:
      //   title = "Dreamr ✨ Manage Journal";
      //   break;
      // case 4:
      //   title = "Dreamr ✨ Profile";
      //   break;
      default:
        title = "Dreamr";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          "Your personal AI-powered dream analysis",
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Color(0xFFD1B2FF),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;

    _views = [
      // DashboardScreen(refreshTrigger: dreamEntryRefreshTrigger), // index 0
      DashboardScreen(
        refreshTrigger: dreamEntryRefreshTrigger,
        tabActiveNotifier: _dashboardActive,
        offlineNotifier: isOfflineNotifier,
        onAnalyzingChange: (bool analyzing) {
          setState(() {
            _navEnabled = !analyzing;
          });
        },
      ),
      DreamJournalScreen(refreshTrigger: journalRefreshTrigger), // index 1
      DreamGalleryScreen(refreshTrigger: galleryRefreshTrigger), // index 2
      // HelpScreen(refreshTrigger: profileRefreshTrigger), // index 3
      DreamJournalEditorScreen(refreshTrigger: editorRefreshTrigger), // index 3
      ProfileScreen(
        refreshTrigger: profileRefreshTrigger,
        onDone: () {
          setState(() {
            _selectedIndex = 1;
          });
          // _loadUserName();
        },
      ),
      InsightsScreen(refreshTrigger: insightsRefreshTrigger), // index 5
    ];
  }

  @override
  void dispose() {
    _dashboardActive.dispose();
    super.dispose();
  }

  // Bottom-nav positions don't map 1:1 to view indices anymore:
  // nav slots are [Add Dream, Journal, Gallery, Insights] but views are
  // [Add Dream(0), Journal(1), Gallery(2), HiddenEditor(3), Profile(4), Insights(5)].
  int _viewIndexToNavIndex(int viewIndex) {
    if (viewIndex == 5) return 3; // Insights
    if (viewIndex == 3) return 1; // Hidden editor highlights Journal
    return viewIndex.clamp(0, 2);
  }

  void _onBottomNavTapped(int navIndex) {
    // force close keyboard
    FocusScope.of(context).unfocus();

    final subscriptionModel = Provider.of<SubscriptionModel>(context, listen: false);

    int viewIndex;
    switch (navIndex) {
      case 0:
        viewIndex = 0;
        dreamEntryRefreshTrigger.value++;
        break;
      case 1:
        viewIndex = 1;
        journalRefreshTrigger.value++;
        break;
      case 2:
        viewIndex = 2;
        galleryRefreshTrigger.value++;
        break;
      case 3:
        viewIndex = 5;
        insightsRefreshTrigger.value++;
        break;
      default:
        viewIndex = navIndex;
    }

    // Force a refresh of subscription data to ensure buttons are up-to-date
    subscriptionModel.refresh();

    // Close journal search when leaving the journal tab.
    if (viewIndex != 1) journalSearchActive.value = false;

    _dashboardActive.value = (viewIndex == 0);
    setState(() {
      _selectedIndex = viewIndex;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.purple950,
        elevation: 4,
        automaticallyImplyLeading: false,
        title: _getTitleForIndex(_selectedIndex),
        actions: [
          if (_selectedIndex == 1)
            ValueListenableBuilder<bool>(
              valueListenable: journalSearchActive,
              builder: (_, active, _) => IconButton(
                tooltip: active ? 'Close search' : 'Search dreams',
                icon: Icon(active ? Icons.close : Icons.search, color: Colors.white),
                onPressed: () => journalSearchActive.value = !active,
              ),
            ),
          IconButton(
            key: _menuButtonKey,
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: _openHamburgerMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: isOfflineNotifier,
            builder: (_, offline, _) {
              if (!offline) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.red.shade800,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'No internet connection',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _views,
            ),
          ),
        ],
      ),
      bottomNavigationBar: (_selectedIndex == 4 || !_navEnabled)
    ? null // hide nav on profile page OR when analyzing
    : BottomNavigationBar(
        currentIndex: _viewIndexToNavIndex(_selectedIndex),
        onTap: _onBottomNavTapped,
        unselectedItemColor: Colors.white70,
        selectedItemColor: Colors.white,
        backgroundColor: AppColors.purple950,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        showSelectedLabels: true,
        elevation: 8,
        items: [
          _buildNavItem(
            icon: Icons.nights_stay_rounded,
            label: 'Add Dream',
            index: 0,
          ),
          _buildNavItem(
            icon: Icons.auto_stories_rounded,
            label: 'Journal',
            index: 1,
          ),
          _buildNavItem(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            index: 2,
          ),
          _buildNavItem(
            icon: Icons.auto_awesome,
            label: 'Insights',
            index: 3,
          ),
        ],
      ),
    );
  }
  
  // Custom navigation item with dynamic size based on selection state
  BottomNavigationBarItem _buildNavItem({
    required IconData icon, 
    required String label, 
    required int index
  }) {
    // Get CURRENT subscription data directly from the provider
    final subscriptionModel = Provider.of<SubscriptionModel>(context, listen: true);
    
    // Calculate current nav index for comparison (views and nav slots aren't 1:1)
    final currentIdx = _viewIndexToNavIndex(_selectedIndex);
    final isSelected = currentIdx == index;
    
    // Only enforce out-of-credits state once subscription info is loaded.
    final bool isPro = subscriptionModel.loaded ? subscriptionModel.status.isActive : false;
    final int totalCredits = subscriptionModel.loaded
        ? subscriptionModel.status.totalCredits
        : 1; // assume credits available until loaded

    // Check if this is the New Dream button and user is out of credits
    final bool isOutOfCredits = index == 0 && subscriptionModel.loaded &&
        !isPro && totalCredits <= 0;

    // For debugging
    if (index == 0) {
      debugPrint('NEW DREAM BUTTON: isOutOfCredits=$isOutOfCredits, isPro=$isPro, totalCredits=$totalCredits');
    }
    
    if (isOutOfCredits && index == 0) {
      // Special treatment for disabled New Dream button
      return BottomNavigationBarItem(
        icon: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                // color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(15),
                // border: Border.all(color: Colors.red, width: 2),
              ),
              child: const Icon(Icons.sentiment_dissatisfied, 
                size: 20.0, 
                color: Colors.redAccent),
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              child: Icon(
                icon,
                size: 20.0,
                color: Colors.white70.withValues(alpha:0.0), // Faded icon behind lock
              ),
            ),
          ],
        ),
        activeIcon: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade300, width: 2),
              ),
              child: const Icon(Icons.lock, size: 20.0, color: Colors.white),
            ),
            Positioned(
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'UPGRADE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        label: 'No dream credits',
      );
    }
    
    // Default navigation item for all other cases
    return BottomNavigationBarItem(
      icon: Container(
        margin: const EdgeInsets.only(bottom: 3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: Icon(
            icon,
            size: isSelected ? 25.0 : 20.0, // Selected icon is larger
          ),
        ),
      ),
      activeIcon: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.purple800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          size: 25.0,
          color: Colors.white,
        ),
      ),
      label: label,
    );
  }
}

