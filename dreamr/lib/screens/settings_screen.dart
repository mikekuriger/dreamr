// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  final VoidCallback? onDone;
  const SettingsScreen({super.key, required this.refreshTrigger, this.onDone});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _enableAudio = false;
  bool _enableNotifications = false;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 8, minute: 0);
  bool _showDreamStats = true;  // New preference
  bool _showDreamCalendar = true;  // New preference

  bool _loading = true;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final enabled = await _notificationService.getNotificationSetting();
      final time = await _notificationService.getNotificationTime();
      
      // This would come from API in a real app, but for now we're just using shared prefs
      final prefs = await SharedPreferences.getInstance();
      final audioEnabled = prefs.getBool('enable_audio') ?? false;
      final showDreamStats = prefs.getBool('show_dream_stats') ?? true;
      final showDreamCalendar = prefs.getBool('show_dream_calendar') ?? true;
      
      setState(() {
        _enableNotifications = enabled;
        _notificationTime = time;
        _enableAudio = audioEnabled;
        _showDreamStats = showDreamStats;
        _showDreamCalendar = showDreamCalendar;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load settings: $e');
      setState(() => _loading = false);
    }
  }

  // Save dream stats visibility setting
  Future<void> _saveDreamStatsVisibility(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_dream_stats', value);
      widget.refreshTrigger.value++;
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dream stats visibility setting saved'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to save dream stats visibility setting: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Failed to save dream stats visibility setting')),
      );
    }
  }

  // Save dream calendar visibility setting
  Future<void> _saveDreamCalendarVisibility(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_dream_calendar', value);
      widget.refreshTrigger.value++;
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Dream calendar visibility setting saved'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to save dream calendar visibility setting: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Failed to save dream calendar visibility setting')),
      );
    }
  }

  // Save a specific setting immediately
  Future<void> _saveAudioSetting(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enable_audio', value);
      widget.refreshTrigger.value++;
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Audio setting saved'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to save audio setting: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Failed to save audio setting')),
      );
    }
  }

  // Save notification settings immediately
  Future<void> _saveNotificationSettings(bool value) async {
    try {
      await _notificationService.toggleNotifications(value);
      widget.refreshTrigger.value++;
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Notification setting saved'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to save notification setting: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Failed to save notification setting')),
      );
    }
  }

  // Save notification time immediately
  Future<void> _saveNotificationTime(TimeOfDay time) async {
    try {
      await _notificationService.setNotificationTime(time);
      widget.refreshTrigger.value++;
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Notification time saved'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to save notification time: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Failed to save notification time')),
      );
    }
  }

  Widget _buildLoadingWidget() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildSettingsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Settings card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.purple950,        // Settings card background color
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF82D9FF), // pick your border color
                width: .5,  
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromARGB(255, 173, 114, 255),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'User Preferences',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Audio toggle
                SwitchListTile(
                  title: Text(
                    _enableAudio ? "Audio Enabled" : "Audio Disabled",
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    "Play voice prompts when recording dreams",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  value: _enableAudio,
                  onChanged: (val) {
                    setState(() => _enableAudio = val);
                    _saveAudioSetting(val);
                  },
                  activeThumbColor: Colors.white,
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.white30,
                ),
                
                // Notification toggle
                SwitchListTile(
                  title: Text(
                    _enableNotifications ? "Notifications Enabled" : "Notifications Disabled",
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    "Get morning reminders to record your dreams and credit updates",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  value: _enableNotifications,
                  onChanged: (val) {
                    setState(() => _enableNotifications = val);
                    _saveNotificationSettings(val);
                  },
                  activeThumbColor: Colors.white,
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.white30,
                ),
                
                // Notification time picker
                if (_enableNotifications) ...[
                  ListTile(
                    title: const Text(
                      "Daily Reminder Time",
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      "Daily reminder at ${_notificationTime.format(context)}",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.access_time, color: Colors.white70),
                    onTap: () async {
                      final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime: _notificationTime,
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color.fromARGB(255, 133, 104, 249),
                                // primary: Colors.deepPurple,
                                surface: Colors.black87,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null && picked != _notificationTime) {
                        setState(() {
                          _notificationTime = picked;
                        });
                        _saveNotificationTime(picked);
                      }
                    },
                  ),

                  // Dream Journal Stats Visibility toggle
                  SwitchListTile(
                    title: Text(
                      _showDreamStats ? "Dream Stats Visible" : "Dream Stats Hidden",
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      "Show statistics section in Dream Journal",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    value: _showDreamStats,
                    onChanged: (val) {
                      setState(() => _showDreamStats = val);
                      _saveDreamStatsVisibility(val);
                    },
                    activeThumbColor: Colors.white,
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.white30,
                  ),
                  
                  // Dream Journal Calendar Visibility toggle
                  SwitchListTile(
                    title: Text(
                      _showDreamCalendar ? "Dream Calendar Visible" : "Dream Calendar Hidden",
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      "Show calendar section in Dream Journal",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    value: _showDreamCalendar,
                    onChanged: (val) {
                      setState(() => _showDreamCalendar = val);
                      _saveDreamCalendarVisibility(val);
                    },
                    activeThumbColor: Colors.white,
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.white30,
                  ),

                ],
              ],
            ),
          ),
          
          // Test Notifications card
          // Container(
          //   width: double.infinity,
          //   padding: const EdgeInsets.all(16),
          //   margin: const EdgeInsets.only(bottom: 20),
          //   decoration: BoxDecoration(
          //     color: AppColors.purple950,
          //     borderRadius: BorderRadius.circular(16),
          //     boxShadow: [
          //       BoxShadow(
          //         color: Colors.black.withOpacity(0.2),
          //         blurRadius: 8,
          //         offset: const Offset(0, 4),
          //       ),
          //     ],
          //   ),
          //   child: Column(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       const Row(
          //         children: [
          //           Icon(Icons.notifications_active, color: Colors.white, size: 24),
          //           SizedBox(width: 8),
          //           Text(
          //             'Test Notifications',
          //             style: TextStyle(
          //               color: Colors.white,
          //               fontSize: 16,
          //               fontWeight: FontWeight.bold,
          //             ),
          //           ),
          //         ],
          //       ),
          //       const SizedBox(height: 12),
          //       Text(
          //         'Send test notification immediately.',
          //         style: const TextStyle(color: Colors.white70, fontSize: 12),
          //       ),
          //       const SizedBox(height: 12),
          //       // Only the Daily test button remains
          //       SizedBox(
          //         width: double.infinity,
          //         child: ElevatedButton.icon(
          //           style: ElevatedButton.styleFrom(
          //             backgroundColor: Colors.deepPurpleAccent,
          //             foregroundColor: Colors.white,
          //           ),
          //           icon: const Icon(Icons.today),
          //           label: const Text('Send Daily Test Now'),
          //           onPressed: () async {
          //             try {
          //               await _notificationService.sendDailyTestNow();
          //               if (!mounted) return;
          //               ScaffoldMessenger.of(context).showSnackBar(
          //                 const SnackBar(content: Text('✅ Sent daily test notification')),
          //               );
          //             } catch (e) {
          //               debugPrint('❌ Failed to send daily test: $e');
          //               if (!mounted) return;
          //               ScaffoldMessenger.of(context).showSnackBar(
          //                 const SnackBar(content: Text('❌ Failed to send daily test notification')),
          //               );
          //             }
          //           },
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.purple900,     // Settings Screen background color
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Dreamr ✨ Settings",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "Customize your app experience",
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Color(0xFFD1B2FF),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.purple950,     // AppBar background color
        foregroundColor: Colors.white,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _loading ? _buildLoadingWidget() : _buildSettingsContent(),
    );
  }
}