// screens/life_events_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/widgets/life_event_widget.dart';
import 'package:dreamr/repository/life_event_repository.dart';
import 'package:dreamr/theme/colors.dart';

class LifeEventsScreen extends StatefulWidget {
  final VoidCallback? onDone;
  
  const LifeEventsScreen({super.key, this.onDone});

  @override
  State<LifeEventsScreen> createState() => _LifeEventsScreenState();
}

class _LifeEventsScreenState extends State<LifeEventsScreen> {
  bool _statsExpanded = true;
  int _eventCount = 0;
  final LifeEventRepository _repository = LifeEventRepository();

  final GlobalKey<LifeEventWidgetState> _eventsKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // Initial load after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
    });
  }

  void _refreshEvents() {
    _eventsKey.currentState?.refresh();
    _loadStats();
  }

  void _loadStats() {
    final events = _eventsKey.currentState?.getEvents() ?? [];
    setState(() {
      _eventCount = events.length;
    });
  }

  Future<void> _addNewEvent() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const LifeEventDialog(),
    );

    if (result != null) {
      setState(() => _statsExpanded = false); // Collapse stats to show progress

      debugPrint('Creating new life event: ${result['title']}');
      debugPrint('Date: ${result['occurredAt']}');
      debugPrint('Tags: ${result['tags']}');
      
      final lifeEvent = await _repository.createLifeEvent(
        occurredAt: result['occurredAt'],
        title: result['title'],
        details: result['details'],
        tags: result['tags'] as List<String>?,
      );
      
      if (lifeEvent == null) {
        // Handle API failure silently
        debugPrint('Failed to create life event: API call returned null');
        
        // Refresh anyway to ensure we're showing the latest from server
        _refreshEvents();
        return;
      }
      
      debugPrint('Successfully created life event with ID: ${lifeEvent.id}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Life event added'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      _refreshEvents();
    }
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.purple900,     //  Screen background color
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Dreamr ✨ Life Events",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "Track significant life events for dream interpretation",
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
            widget.onDone?.call();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshEvents();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.purple950,
                      // color: const Color.fromARGB(255, 0, 0, 0).withValues(alpha: 0.45),  // Semi-transparent black
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF82D9FF), // pick your border color
                        width: .5,                     // border width
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
                        // header row with title and arrow
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "✨ Summary",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(
                              _statsExpanded ? Icons.expand_less : Icons.expand_more,
                              color: Colors.white,
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
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: "Events Logged: ",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.normal,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '$_eventCount',
                                        style: const TextStyle(
                                          color: Colors.yellow,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.add_circle),
                                    label: const Text("Add Life Event"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.deepPurple.shade600,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _addNewEvent,
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
              LifeEventWidget(
                key: _eventsKey,
                onEventsLoaded: _loadStats,
              ),
            ],
          ),
        ),
      ),
    );
  }
}