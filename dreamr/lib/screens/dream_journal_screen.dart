// screens/dream_journal_screen.dart
// ignore_for_file: unused_field

import 'dart:async';
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

  int? _freeCredits;
  int? _purchasedCredits;
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
  
  // Tone filter
  String? _activeToneFilter;

  // Search filter
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Visibility preferences
  bool _showStatsSection = true; // Controls if stats section is shown at all
  bool _showCalendarSection = false; // Controls if calendar section is shown at all


  // Load visibility preferences from SharedPreferences
  Future<void> _loadVisibilityPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _showStatsSection = prefs.getBool('show_dream_stats') ?? true;
        _showCalendarSection = prefs.getBool('show_dream_calendar') ?? false;
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

    // React to AppBar search toggle.
    journalSearchActive.addListener(_onSearchToggled);
  }

  void _onSearchToggled() {
    final active = journalSearchActive.value;
    if (active) {
      // The TextField is autofocus, but request focus explicitly in case it
      // was previously dismissed while the field remained mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && journalSearchActive.value) _searchFocus.requestFocus();
      });
    } else {
      // Clear query when search is closed so results return to full list.
      _searchController.clear();
      _searchDebounce?.cancel();
      if (mounted) setState(() => _searchQuery = '');
      _searchFocus.unfocus();
    }
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim().toLowerCase());
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

    // Read cached subscription status first so stats show correctly offline
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool('sub_is_active');
      if (cached != null && mounted) {
        setState(() => _isPro = cached);
      }
    } catch (_) {}

    try {
      final status = await ApiService.getSubscriptionStatus();

      setState(() {
        _isPro = status.isActive;
        _freeCredits = status.freeCredits;
        _purchasedCredits = status.purchasedCredits;
        _nextReset = status.nextReset;
        _quotaLoading = false;
      });
    } catch (e) {
      setState(() {
        _quotaLoading = false;
        // Keep _isPro from cache; only clear loading flag
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
    // Always start from the raw unfiltered list so stacked filters don't compound
    var dreams = _journalKey.currentState?.getRawDreams() ?? [];

    if (_selectedDay != null) {
      dreams = dreams.where((dream) {
        final dreamDate = DateTime(dream.createdAt.year, dream.createdAt.month, dream.createdAt.day);
        final selectedDate = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
        return dreamDate.isAtSameMomentAs(selectedDate);
      }).toList();
    }

    if (_activeToneFilter != null) {
      dreams = dreams.where((d) => d.tone.trim().toLowerCase() == _activeToneFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      dreams = dreams.where((d) {
        final hay = '${d.text}\n${d.summary}\n${d.analysis}\n${d.notes}'.toLowerCase();
        return hay.contains(_searchQuery);
      }).toList();
    }

    return dreams;
  }

  bool get _anyFilterActive =>
      _selectedDay != null || _activeToneFilter != null || _searchQuery.isNotEmpty;

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
  
  Widget _buildSearchField() {
    final hasQuery = _searchQuery.isNotEmpty;
    final matchCount = hasQuery ? getFilteredDreams().length : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 6, 5, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.black.withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.purple400.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search dreams…',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (hasQuery)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.cancel, color: Colors.white54, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      _searchController.clear();
                      _searchDebounce?.cancel();
                      setState(() => _searchQuery = '');
                    },
                  ),
              ],
            ),
          ),
          if (hasQuery)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                matchCount == 0
                    ? 'No matches'
                    : '$matchCount ${matchCount == 1 ? "match" : "matches"}',
                style: const TextStyle(color: Colors.white60, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
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
      final percentage = _dreamCount > 0 ? entry.value / _dreamCount : 0.0;
      final color = _getMoodColor(entry.key);
      final isSelected = _activeToneFilter == entry.key;

      return GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _activeToneFilter = null;
              _journalKey.currentState?.refresh();
            } else {
              _activeToneFilter = entry.key;
              _statsExpanded = false; // auto-close stats card
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: color.withValues(alpha: 0.5), width: 1) : null,
          ),
          child: Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                entry.key,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 8),
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
              Text(
                "${entry.value}",
                style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 4),
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: isSelected ? color : Colors.white24,
              ),
            ],
          ),
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
    journalSearchActive.removeListener(_onSearchToggled);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
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
            // Animated search field — slides down when AppBar search icon is tapped.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              child: journalSearchActive.value
                  ? _buildSearchField()
                  : const SizedBox.shrink(),
            ),

            // Stats section - only show if preference is enabled
            if (_showStatsSection)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),            // dreams logged/stats size
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
                    color: AppColors.black.withAlpha(200),                           // Credits/Dreams Logged Background
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
                          Text.rich(
                                TextSpan(
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
                                        text: "✨ Dreamr Credits: ",
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal),
                                      ),
                                      TextSpan(
                                        text: "${(_freeCredits ?? 0) + (_purchasedCredits ?? 0)}",
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
                                Text.rich(
                                  TextSpan(
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
                              Text.rich(
                                TextSpan(
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ElevatedButton.icon(
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
                                ],
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
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 5),           // Calendar size
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
                            fontWeight: FontWeight.normal,
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


            // Active tone filter chip
            if (_activeToneFilter != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.purple950.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _activeToneFilter!,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() => _activeToneFilter = null);
                              _journalKey.currentState?.refresh();
                            },
                            child: const Icon(Icons.close, size: 14, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  filteredDreams: _anyFilterActive ? filteredDreams : null,
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