// screens/dream_journal_screen.dart
// ignore_for_file: unused_field

import 'package:dreamr/widgets/main_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/widgets/dream_journal_widget.dart';
import 'package:dreamr/constants.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/theme/colors.dart';

// Custom enum to replace missing CalendarFormat
enum CalendarFormat { month, week }

class DreamJournalScreen extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  const DreamJournalScreen({super.key, required this.refreshTrigger});

  @override
  State<DreamJournalScreen> createState() => _DreamJournalScreenState();
}

class _DreamJournalScreenState extends State<DreamJournalScreen> {
  bool _statsExpanded = false;
  Map<String, int> _toneCounts = {};

  // state fields
  int _dreamCount = 0;
  String _mostCommonTone = '';
  // int _longestWordCount = 0;

  int? _textRemainingWeek;
  int? _imageRemainingLifetime;
  DateTime? _nextReset;
  bool _quotaLoading = false;
  String? _quotaError;
  bool? _isPro; // null = loading
  
  // Calendar state
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _showCalendar = false; // Collapsed by default
  Map<DateTime, List<Dream>> _dreamsByDate = {};
  
  // Visibility preferences
  bool _showStatsSection = true; // Controls if stats section is shown at all
  bool _showCalendarSection = true; // Controls if calendar section is shown at all


  // Load visibility preferences from SharedPreferences
  Future<void> _loadVisibilityPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showStatsSection = prefs.getBool('show_dream_stats') ?? true;
        _showCalendarSection = prefs.getBool('show_dream_calendar') ?? true;
      });
    } catch (e) {
      debugPrint('❌ Failed to load visibility preferences: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    // Load visibility preferences
    _loadVisibilityPreferences();

    // Initial load after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshStats();
    });

    // ✅ Listen for bottom nav tab refresh
    widget.refreshTrigger.addListener(_refreshJournal);

    // Refresh journal if a new dream was added
    dreamDataChanged.addListener(() {
      if (dreamDataChanged.value == true) {
        _refreshJournal();
        _refreshStats();
        // _loadStats();
        // await _loadQuota();
        dreamDataChanged.value = false;
      }
    });
  }

  final GlobalKey<DreamJournalWidgetState> _journalKey = GlobalKey();

  void _refreshJournal() {
    _journalKey.currentState?.refresh();

    // 👇 collapse stats box whenever this screen is triggered to refresh
    setState(() {
      _statsExpanded = false;
    });
  }

  void _loadStats() {
    final dreams = _journalKey.currentState?.getDreams() ?? [];

    setState(() {
      _dreamCount = dreams.length;

      final toneMap = <String, int>{};
      // int maxWords = 0;

      for (var d in dreams) {
        final tone = d.tone.trim().toLowerCase();
        if (tone.isNotEmpty) {
          toneMap[tone] = (toneMap[tone] ?? 0) + 1;
        }
      }

      _toneCounts = toneMap;
      
      final mostCommon = toneMap.entries.fold<MapEntry<String, int>?>(null, (prev, entry) {
        return (prev == null || entry.value > prev.value) ? entry : prev;
      });

      _mostCommonTone = mostCommon?.key ?? 'N/A';
    });
  }

  Future<void> _loadQuota() async {
    setState(() {
      _quotaLoading = true;
      _quotaError = null;
    });

    try {
      final status = await ApiService.getSubscriptionStatus();

      setState(() {
        _isPro = status.isActive;
        _textRemainingWeek = status.textRemainingWeek;            // null for paid
        _imageRemainingLifetime = status.imageRemainingLifetime;  // null for paid
        _nextReset = status.nextReset;                            // null for paid
        _quotaLoading = false;
      });
    } catch (e) {
      setState(() {
        _quotaLoading = false;
        _quotaError = 'Failed to load quota';
      });
    }
  }

  // Organize dreams by date for calendar
  void _organizeDreamsByDate() {
    final dreams = _journalKey.currentState?.getDreams() ?? [];
    final Map<DateTime, List<Dream>> dreamsByDate = {};

    for (final dream in dreams) {
      // Create date key with just year, month, day (no time)
      final date = DateTime(
        dream.createdAt.year,
        dream.createdAt.month,
        dream.createdAt.day,
      );

      if (dreamsByDate[date] == null) {
        dreamsByDate[date] = [];
      }
      dreamsByDate[date]!.add(dream);
    }

    setState(() {
      _dreamsByDate = dreamsByDate;
    });
  }

  Future<void> _refreshStats() async {
    _loadStats();          // local aggregates
    await _loadQuota();    // network
    _organizeDreamsByDate(); // For calendar
  }

  // Helper for calendar - check if two dates are the same day
  bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return false;
    }
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // Get filtered dreams for the selected date
  List<Dream> getFilteredDreams() {
    final allDreams = _journalKey.currentState?.getDreams() ?? [];
    
    if (_selectedDay == null) {
      return allDreams; // Return all dreams if no date is selected
    }
    
    // Filter dreams for the selected day
    return allDreams.where((dream) {
      final dreamDate = DateTime(
        dream.createdAt.year, 
        dream.createdAt.month, 
        dream.createdAt.day
      );
      
      final selectedDate = DateTime(
        _selectedDay!.year, 
        _selectedDay!.month, 
        _selectedDay!.day
      );
      
      return dreamDate.isAtSameMomentAs(selectedDate);
    }).toList();
  }

  // Check if a specific day has dreams
  bool hasDreamsOnDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _dreamsByDate.containsKey(normalizedDay) && 
           _dreamsByDate[normalizedDay]!.isNotEmpty;
  }

  // Get number of dreams for a specific day
  int dreamCountForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _dreamsByDate[normalizedDay]?.length ?? 0;
  }
  
  // Generate a consistent color for each mood
  Color _getMoodColor(String mood) {
    // App's predefined moods with their colors
    // Using text colors for dark backgrounds to ensure visibility
    final Map<String, Color> predefinedMoods = {
      'peaceful / gentle': Colors.blue.shade100,
      'epic / heroic': Colors.orange.shade100,
      'whimsical / surreal': Colors.purple.shade100,
      'nightmarish / dark': Colors.orange.shade200,
      'romantic / nostalgic': Colors.pink.shade100,
      'ancient / mythic': Colors.brown.shade100,
      'futuristic / uncanny': Colors.teal.shade100,
      'elegant / ornate': Colors.indigo.shade100,
    };
    
    // Normalize the mood string for comparison
    final normalizedMood = mood.toLowerCase().trim();
    
    // Check for exact matches first
    if (predefinedMoods.containsKey(normalizedMood)) {
      return predefinedMoods[normalizedMood]!;
    }
    
    // Check for partial matches (e.g., if mood contains "peaceful" or "gentle")
    for (final entry in predefinedMoods.entries) {
      final keywords = entry.key.split('/').map((k) => k.trim().toLowerCase());
      if (keywords.any((keyword) => normalizedMood.contains(keyword))) {
        return entry.value;
      }
    }
    
    // Otherwise generate a color based on the mood string
    // Use a simple hash function to ensure the same mood always gets the same color
    int hash = 0;
    for (int i = 0; i < mood.length; i++) {
      hash = mood.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    // Use the hash to generate a hue value between 0 and 360
    final hue = (hash % 360).abs().toDouble();
    
    // Create a color with the hue and fixed saturation/brightness
    // Using HSV color model for more vibrant colors
    return HSVColor.fromAHSV(1.0, hue, 0.7, 0.9).toColor();
  }
  
  // Build sorted mood bars
  List<Widget> _buildSortedMoodBars() {
    if (_toneCounts.isEmpty) {
      return [const Text('No dream data available', style: TextStyle(color: Colors.white70))];
    }
    
    // Sort entries by count (descending)
    final sortedEntries = _toneCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Create a list of mood bar widgets
    return sortedEntries.map((entry) {
      // Calculate percentage for the progress bar
      final percentage = _dreamCount > 0 
          ? entry.value / _dreamCount 
          : 0.0;
      
      // Generate a color based on the mood name
      final color = _getMoodColor(entry.key);
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            // Color indicator
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            // Mood name
            Text(
              entry.key,
              style: const TextStyle(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 8),
            // Progress bar
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Count only (no percentage)
            Text(
              "${entry.value}",
              style: const TextStyle(
                color: Colors.yellow,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // Build compact calendar
  Widget _buildCalendar() {
    // Get current month info
    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final lastDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    
    // Calculate days from previous month to show
    final firstWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday, 1 = Monday, etc.
    
    // Generate dates for the grid
    final List<DateTime> calendarDates = [];
    
    // Add days from previous month
    for (var i = 0; i < firstWeekday; i++) {
      calendarDates.add(firstDayOfMonth.subtract(Duration(days: firstWeekday - i)));
    }
    
    // Add days from current month
    for (var i = 1; i <= lastDayOfMonth.day; i++) {
      calendarDates.add(DateTime(_focusedDay.year, _focusedDay.month, i));
    }
    
    // Add days from next month to complete the grid (to multiple of 7)
    final remainingDays = 7 - (calendarDates.length % 7);
    if (remainingDays < 7) {
      for (var i = 1; i <= remainingDays; i++) {
        calendarDates.add(DateTime(_focusedDay.year, _focusedDay.month + 1, i));
      }
    }
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with month name and navigation buttons - more compact
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 18,
              onPressed: () {
                setState(() {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                });
              },
            ),
            Text(
              DateFormat.yMMM().format(_focusedDay), // Shorter month format
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.white, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 18,
              onPressed: () {
                setState(() {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                });
              },
            ),
          ],
        ),
        
        // Days of week headers - more compact
        Padding(
          padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              Text('S', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('M', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('T', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('W', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('T', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('F', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('S', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        
        // Calendar grid - more compact
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.0,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            mainAxisExtent: 28, // Fixed smaller height
          ),
          itemCount: calendarDates.length,
          itemBuilder: (context, index) {
            final date = calendarDates[index];
            final isThisMonth = date.month == _focusedDay.month;
            final isToday = isSameDay(date, DateTime.now());
            final isSelected = isSameDay(date, _selectedDay);
            final hasDreams = hasDreamsOnDay(date);
            final dreamCount = dreamCountForDay(date);
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  // Toggle selection if the same day is tapped
                  if (isSameDay(date, _selectedDay)) {
                    _selectedDay = null;
                  } else {
                    _selectedDay = date;
                  }
                  // Force refresh the dream list when a date is selected
                  _journalKey.currentState?.refresh();
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected 
                    ? Colors.deepPurple 
                    : isToday 
                      ? Colors.deepPurple.shade100.withValues(alpha: 0.3) 
                      : null,
                  borderRadius: BorderRadius.circular(4), // Smaller radius
                  border: hasDreams 
                    ? Border.all(color: Colors.deepPurple.shade300, width: 1) // Thinner border
                    : null,
                ),
                child: Stack(
                  children: [
                    // Day number
                    Center(
                      child: Text(
                        date.day.toString(),
                        style: TextStyle(
                          fontSize: 12, // Smaller font
                          color: isThisMonth 
                            ? isSelected 
                              ? Colors.white 
                              : [DateTime.saturday, DateTime.sunday].contains(date.weekday) 
                                ? Colors.grey.shade400 
                                : Colors.white
                            : Colors.grey.shade700,
                          fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    
                    // Dream indicators - more compact
                    if (hasDreams)
                      Positioned(
                        bottom: 2, // Move up slightly
                        right: 0,
                        left: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                                for (var i = 0; i < (dreamCount < 3 ? dreamCount : 3); i++)
                              Container(
                                width: 4, // Smaller dots
                                height: 4, // Smaller dots
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade300,
                                  shape: BoxShape.circle,
                                ),
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                              ),
                            if (dreamCount > 3)
                              Text(
                                '+${dreamCount - 3}',
                                style: TextStyle(
                                  color: Colors.deepPurple.shade200,
                                  fontSize: 6, // Smaller text
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.refreshTrigger.removeListener(_refreshJournal);
    dreamDataChanged.removeListener(_refreshJournal);  // if you want to clean that too
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _refreshJournal();
        // _loadStats();
        // await _loadQuota();
        _refreshStats();
        _loadVisibilityPreferences(); // Reload preferences
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(4),  // side spacing
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Stats section - only show if preference is enabled
            if (_showStatsSection)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _statsExpanded = !_statsExpanded;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: double.infinity,
                  padding: const EdgeInsets.all(12), // height of stat box
                  decoration: BoxDecoration(
                    // color: const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.4),
                    color: AppColors.black.withAlpha(200),                           // Credits Background
                    // color: AppColors.purple950, // Dark purple background
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color.fromARGB(255, 255, 230, 7),
                      // color: const Color.fromARGB(255, 170, 153, 1),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromARGB(255, 130, 217, 255).withValues(alpha: 0.5), // Shadow color with opacity
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // header row with title and arrow
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                           RichText(
                                text: TextSpan(
                                  children: [
                                    if (_isPro == null) ...[
                                      const TextSpan(text: " ", style: TextStyle(color: Colors.white)),
                                    ] else if (_isPro!) ...[
                                      const TextSpan(
                                        text: "✨ Dreams Logged: ",
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.normal),
                                      ),
                                      TextSpan(
                                        text: '$_dreamCount',
                                        style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold),
                                      ),
                                    ] else ...[
                                      TextSpan(
                                        text: "✨ Dream Credits: ",
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal),
                                      ),
                                      TextSpan(
                                        text: "${_textRemainingWeek ?? 0}",
                                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                      ),
                                      TextSpan(
                                        text: "  🔮 Image Credits: ",
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal),
                                      ),
                                      TextSpan(
                                        text: "${_imageRemainingLifetime ?? 0}",
                                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          Icon(
                            _statsExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white, // ✅ white icon
                          ),
                        ],
                      ),

                      // expanding section
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 300),
                        crossFadeState: _statsExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: const SizedBox.shrink(),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                  // Show this for free accounts only (hide for pro)      
                              if (_isPro == false) ...[   
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: "Dreams Logged: ",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.normal,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '$_dreamCount',
                                        style: const TextStyle(
                                          color: Colors.yellow,
                                          fontWeight: FontWeight.bold,
                                          // fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              RichText(
                                text: TextSpan(
                                  children: [
                                    const TextSpan(
                                      text: "Most Common Dream: ",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.normal,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    TextSpan(
                                      text: _mostCommonTone,
                                      style: const TextStyle(
                                        color: Colors.yellow,
                                        fontWeight: FontWeight.bold,
                                        // fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              if (_toneCounts.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                // const Text(
                                //   "All Moods:",
                                //   style: TextStyle(
                                //     color: Colors.white,
                                //     fontWeight: FontWeight.bold,
                                //   ),
                                // ),
                                Row(
                                  children: [
                                    const Expanded(child: Divider(thickness: 1, color: Colors.white24)),
                                    const SizedBox(width: 8),
                                    const Text('✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    const Expanded(child: Divider(thickness: 1, color: Colors.white24)),
                                  ],
                                ),
                                // const Divider(
                                //   height: 24,                  // vertical space
                                //   thickness: 1,
                                //   color: Colors.white24,       // subtle on dark bg
                                // ),
                                // const SizedBox(height: 8),
                                
                                // Progress bars for each mood - more compact layout and sorted by count
                                ..._buildSortedMoodBars(),
                              ],

                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.edit_note),
                                  label: const Text("Add a New Dream"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.deepPurple.shade600,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const MainScaffold(initialIndex: 0),
                                      ),
                                    );
                                  },
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
            
            // Calendar section - only show if preference is enabled
            if (_showCalendarSection)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12),  // calendar box height
              decoration: BoxDecoration(
                color: AppColors.black.withAlpha(200),                                // Calendar background
                // color: AppColors.purple950, // Dark purple background
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.deepPurple.shade300,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(255, 130, 217, 255).withValues(alpha: 0.5), // Shadow color with opacity
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Calendar header with expandable toggle
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        // Toggle calendar content visibility
                        _showCalendar = !_showCalendar;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "✨ Dream Calendar", 
                          style: TextStyle(
                            fontSize: 14, 
                            // fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Icon(
                          _showCalendar ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  
                  // Calendar content - only show when expanded
                  if (_showCalendar) ...[
                    const SizedBox(height: 8), // Space after header
                    _buildCalendar(),
                  
                    // Show selected date indicator and clear button - smaller version
                    if (_selectedDay != null) 
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.deepPurple.shade200, width: 0.5),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Date: ${DateFormat('MMM d, y').format(_selectedDay!)}", // Shorter date format
                                style: TextStyle(
                                  color: Colors.white, 
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                minimumSize: Size(0, 24),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedDay = null;
                                  // Refresh dream list when filter is cleared
                                  _journalKey.currentState?.refresh();
                                });
                              },
                              child: Text(
                                "Clear", 
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.deepPurple.shade100,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

 // Divider
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4), // 8px above + 8px below
              child: Divider(
                color: Colors.yellow.withValues(alpha: 0.75),
                thickness: 1,
                indent: 16,
                endIndent: 16,
              ),
            ),


            // Dream list with filtered dreams
            Builder(
              builder: (context) {
                final filteredDreams = getFilteredDreams();
                
                // Show message if no dreams match the selected date
                if (_selectedDay != null && filteredDreams.isEmpty) {
                  return Container(
                    margin: const EdgeInsets.only(top: 20, bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'No dreams recorded on ${DateFormat('EEE, MMM d, y').format(_selectedDay!)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear Date Filter'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade300,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedDay = null;
                            });
                          },
                        ),
                      ],
                    ),
                  );
                }
                
                // Show dream list with filtered dreams if available
                return DreamJournalWidget(
                  key: _journalKey,
                  onDreamsLoaded: _refreshStats,
                  filteredDreams: _selectedDay != null ? filteredDreams : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Helper function
int min(int a, int b) {
  return a < b ? a : b;
}