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

class _WelcomeTourScreenState extends State<WelcomeTourScreen> {
  DateTime? _birthday;
  String? _gender;
  bool _submitting = false;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// Load first name, birthdate, and gender from API.
  Future<void> _loadProfile() async {
    try {
      final data = await ApiService.getProfile();

      final birthStr = data['birthdate'];
      DateTime? birthdate =
          (birthStr != null && birthStr != '') ? DateTime.parse(birthStr) : null;

      final genderStr = data['gender'];
      String? gender =
          (genderStr is String && genderStr.isNotEmpty) ? genderStr : null;

      setState(() {
        _userName = data['first_name'] ?? '';
        _birthday = birthdate;
        _gender = gender;
      });
    } catch (e) {
      debugPrint('WelcomeTour: failed to load profile: $e');
    }
  }


  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 25, now.month, now.day);
    final first = DateTime(1900, 1, 1);
    final last = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );

    if (picked != null) {
      setState(() => _birthday = picked);
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

  /// Save profile ONLY: stay on this screen, no navigation, no markSeen.
  Future<void> _onSaveProfile() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await _updateProfileOnServer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Profile saved')),
        );
      }
    } catch (e) {
      debugPrint('WelcomeTour: failed to save profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Failed to save profile')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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

  /// Save birthday / gender to real profile via backend.
  Future<void> _updateProfileOnServer() async {
    // If user left everything blank, don't call the API.
    if (_birthday == null && (_gender == null || _gender!.isEmpty)) {
      return;
    }

    try {
      await ApiService.setProfile(
        firstName: _userName ?? '',
        gender: _gender ?? '',
        birthdate: _birthday,
      );
    } catch (e) {
      debugPrint('WelcomeTour: failed to save profile: $e');
      // Silent fail for first-login flow; user can fix from Profile page later.
    }
  }

  Widget _buildGenderChip(String value, String label) {
    final selected = _gender == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white,
        ),
      ),
      selected: selected,
      selectedColor: const Color.fromARGB(255, 0, 255, 13),
      backgroundColor: const Color.fromARGB(255, 46, 46, 46),
      onSelected: (on) {
        setState(() {
          _gender = on ? value : null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final birthdayText = _birthday == null
        ? 'Not set'
        : '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}';

    final String titleText = (_userName != null && _userName!.isNotEmpty)
        ? 'Welcome $_userName ✨'
        : 'Welcome to Dreamr ✨';

    return Scaffold(
      backgroundColor: AppColors.purple950,
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.purple950,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF82D9FF),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromARGB(255, 130, 217, 255)
                      .withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You may set your birthday and gender here. These details are optional, '
                  'but they help personalize your dream insights. '
                  'You can always edit them later in your profile.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 20),

                // Card-like body
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Birthday row
                      const Text(
                        'Birthday',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                birthdayText,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _submitting ? null : _pickBirthday,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.purple600,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: const Text('Set'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Gender
                      const Text(
                        'Gender',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildGenderChip('male', 'Male ♂'),
                          _buildGenderChip('female', 'Female ♀'),
                          _buildGenderChip('unspecified', 'Prefer not to say'),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Primary action (red): Save profile and continue
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _onSaveProfile,
                    style: ElevatedButton.styleFrom(
                      // backgroundColor: const Color.fromARGB(255, 255, 0, 0),
                      backgroundColor: AppColors.purple600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Save profile',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // Secondary actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // TextButton(
                    //   onPressed: _submitting ? null : _onSkip,
                    //   style: TextButton.styleFrom(
                    //     foregroundColor: const Color(0xFF82D9FF),
                    //   ),
                    //   child: const Text('Skip for now'),
                    // ),
                    TextButton(
                      onPressed: _submitting ? null : _onTakeTour,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF82D9FF),
                      ),
                      child: const Text('Take a quick tour'),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : _onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF82D9FF),
                      ),
                      child: const Text('Skip for now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}