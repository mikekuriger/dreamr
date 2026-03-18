import 'package:flutter/material.dart';
import 'package:dreamr/widgets/dream_journal_editor_widget.dart';
import 'package:dreamr/constants.dart';

class DreamJournalEditorScreen extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  const DreamJournalEditorScreen({super.key, required this.refreshTrigger});

  @override
  State<DreamJournalEditorScreen> createState() => _DreamJournalEditorScreenState();
}

class _DreamJournalEditorScreenState extends State<DreamJournalEditorScreen> {
  bool _expanded = false;
  @override
  void initState() {
    super.initState();

    // ✅ Listen for bottom nav tab refresh
    widget.refreshTrigger.addListener(_refreshJournal);

    // Refresh journal if a new dream was added
    dreamDataChanged.addListener(() {
      if (dreamDataChanged.value == true) {
        _refreshJournal();
        dreamDataChanged.value = false;
      }
    });
  }

  final GlobalKey<DreamJournalEditorWidgetState> _journalKey = GlobalKey();
  
  void _refreshJournal() {
    _journalKey.currentState?.refresh();

    // 👇 collapse help box whenever this screen is triggered to refresh
      setState(() {
      _expanded = false;
    });
  }
  
  @override
  void dispose() {
    widget.refreshTrigger.removeListener(_refreshJournal);
    dreamDataChanged.removeListener(_refreshJournal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _refreshJournal();
      },
      child: SingleChildScrollView(
        // controller: _scrollController,
        padding: const EdgeInsets.all(4),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Hidden Dreams',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white, // ✅ make icon white
                          ),
                        ],
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 300),
                        crossFadeState: _expanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: const SizedBox.shrink(),
                        secondChild: const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            "These are dreams you’ve hidden from your main journal.\n"
                            "Tap the eye icon to unhide a dream.\n"
                            "Tap the trash icon to delete permanently — this can’t be undone.",
                            style: TextStyle(fontSize: 14, color: Colors.white70),
                          ),
                        ),
                      ),
                    ],
                  ),

                ),
              ),
            ),
            DreamJournalEditorWidget(
              key: _journalKey,
            ),
          ],
        ),
      ),
    );
  }
}
