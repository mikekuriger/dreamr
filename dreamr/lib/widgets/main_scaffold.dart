// widgets/main_scaffold.dart
// import 'package:dreamr/services/api_service.dart';
import 'package:flutter/material.dart';
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
  
  // Subscription state
  bool _isPro = false;
  int? _textRemainingWeek;
  bool _subscriptionLoaded = false;

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

  // Load subscription data from provider
  void _loadSubscriptionData() {
    final subscriptionModel = Provider.of<SubscriptionModel>(context, listen: false);
    if (subscriptionModel.loaded) {
      setState(() {
        _isPro = subscriptionModel.status.isActive;
        _textRemainingWeek = subscriptionModel.status.textRemainingWeek;
        _subscriptionLoaded = true;
      });
      
      // Debug print to verify data is loading correctly
      debugPrint('MainScaffold: Loaded subscription data - isPro: $_isPro, textRemainingWeek: $_textRemainingWeek');
    } else {
      // If not loaded yet, try again after a delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _loadSubscriptionData();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure subscription data is loaded and up-to-date
    _loadSubscriptionData();
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    
    // Initial load will be handled by didChangeDependencies
    // which is called right after initState
    
    _views = [
      // DashboardScreen(refreshTrigger: dreamEntryRefreshTrigger), // index 0
      DashboardScreen(
        refreshTrigger: dreamEntryRefreshTrigger,
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
    ];
  }

  void _onBottomNavTapped(int index) {
    // force close keyboard
    FocusScope.of(context).unfocus();

    // Get latest subscription data directly from the provider
    final subscriptionModel = Provider.of<SubscriptionModel>(context, listen: false);
    final bool isPro = subscriptionModel.loaded ? subscriptionModel.status.isActive : _isPro;
    final int? textRemainingWeek = subscriptionModel.loaded ? subscriptionModel.status.textRemainingWeek : _textRemainingWeek;
    
    // Check if user is out of credits and trying to create new dream
    final bool isOutOfCredits = !isPro && (textRemainingWeek ?? 0) <= 0;
    
    // if (index == 0 && isOutOfCredits) {
    //   // Redirect to subscription screen instead
    //   Navigator.push(
    //     context, 
    //     MaterialPageRoute(
    //       // builder: (context) => const SubscriptionScreen(),
    //       builder: (context) => const SubscriptionScreen(),
    //     ),
    //   );
    //   return;
    // }

    // Trigger refresh logic based on index
    switch (index) {
      case 0:
        dreamEntryRefreshTrigger.value++;
        break;
      case 1:
        journalRefreshTrigger.value++;
        break;
      case 2:
        galleryRefreshTrigger.value++;
        break;
      // case 3:
      //   helpRefreshTrigger.value++;
      //   break;
      case 3:
        editorRefreshTrigger.value++;
        break;
      case 4:
        profileRefreshTrigger.value++;
        break;
    }
    
    // Force a refresh of subscription data to ensure buttons are up-to-date
    subscriptionModel.refresh();
    
    setState(() {
      _selectedIndex = index;
    });
  }


  @override
  Widget build(BuildContext context) {
    // Listen for subscription changes
    final subscriptionModel = Provider.of<SubscriptionModel>(context);
    if (_subscriptionLoaded && subscriptionModel.loaded) {
      final newIsPro = subscriptionModel.status.isActive;
      final newTextRemainingWeek = subscriptionModel.status.textRemainingWeek;
      
      if (newIsPro != _isPro || newTextRemainingWeek != _textRemainingWeek) {
        // Update state if changed
        Future.microtask(() {
          if (mounted) {
            setState(() {
              _isPro = newIsPro;
              _textRemainingWeek = newTextRemainingWeek;
            });
          }
        });
      }
    }
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.purple950,
        elevation: 4,
        automaticallyImplyLeading: false,
        title: _getTitleForIndex(_selectedIndex),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, color: Colors.white),
            color: Colors.grey[850],
            // color: AppColors.purple900,
            onSelected: (String route) async {
              // ✅ force keyboard to close when selecting from menu
              FocusScope.of(context).unfocus();
              
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
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: '/editor',
                child: Row(
                  children: [
                    Icon(Icons.visibility_off_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Hide/Delete', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '/profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Profile', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '/settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Settings', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '/life-events',
                child: Row(
                  children: [
                    Icon(Icons.favorite_outline, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Life Events', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '/interpreters',
                child: Row(
                  children: [
                    Icon(Icons.psychology, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Dream Interpreters', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '/image-styles',
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Image Styles', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '/subscription',
                child: Row(
                  children: [
                    Icon(Icons.star_outline, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Subscription', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '/help',
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Help', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
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
          ),
        ],
      ),
      // body: widget.body,
      body: IndexedStack(
        index: _selectedIndex,
        children: _views,
      ),
      bottomNavigationBar: (_selectedIndex == 4 || !_navEnabled)
    ? null // hide nav on profile page OR when analyzing
    : BottomNavigationBar(
        currentIndex: (_selectedIndex == 3) ? 1 : _selectedIndex.clamp(0, 2),
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
            // icon: Icons.psychology_alt,
            icon: Icons.nights_stay_rounded,
            // icon: Icons.nightlight,
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
    
    // Calculate current index for comparison (handle the special case for index 3)
    final currentIdx = (_selectedIndex == 3) ? 1 : _selectedIndex.clamp(0, 2);
    final isSelected = currentIdx == index;
    
    // Always use LATEST subscription data directly from the model
    final bool isPro = subscriptionModel.loaded ? subscriptionModel.status.isActive : _isPro;
    final int? textRemainingWeek = subscriptionModel.loaded ? subscriptionModel.status.textRemainingWeek : _textRemainingWeek;
    
    // Check if this is the New Dream button and user is out of credits
    final bool isOutOfCredits = index == 0 && !isPro && (textRemainingWeek ?? 0) <= 0;
    
    // For debugging
    if (index == 0) {
      debugPrint('NEW DREAM BUTTON: isOutOfCredits=$isOutOfCredits, isPro=$isPro, textRemainingWeek=$textRemainingWeek');
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

