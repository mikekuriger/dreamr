// widgets/life_event_widget.dart
import 'package:dreamr/models/life_event.dart';
import 'package:dreamr/repository/life_event_repository.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LifeEventWidget extends StatefulWidget {
  final VoidCallback? onEventsLoaded;

  const LifeEventWidget({
    super.key,
    this.onEventsLoaded,
  });

  @override
  State<LifeEventWidget> createState() => LifeEventWidgetState();
}

class TagStyle {
  final Color background;
  final Color text;
  const TagStyle(this.background, this.text);
}

class LifeEventWidgetState extends State<LifeEventWidget> {
  List<LifeEvent> _events = [];
  List<LifeEvent> getEvents() => _events;

  final Map<int, bool> _expanded = {};
  bool _loading = true;
  final LifeEventRepository _repository = LifeEventRepository();

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  // Load a consistent color for each tag
  Color _getTagColor(String tag) {
    // Use a simple hash function to ensure the same tag always gets the same color
    int hash = 0;
    for (int i = 0; i < tag.length; i++) {
      hash = tag.codeUnitAt(i) + ((hash << 5) - hash);
    }
    
    // Use the hash to generate a hue value between 0 and 360
    final hue = (hash % 360).abs().toDouble();
    
    // Create a color with the hue and fixed saturation/brightness
    return HSVColor.fromAHSV(1.0, hue, 0.7, 0.9).toColor();
  }

  Future<void> _loadEvents() async {
    try {
      // Try to load local data first
      final events = await _repository.loadLocal();
      
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
      
      // If no local data, try to sync from server
      if (events.isEmpty) {
        try {
          await _repository.syncFromServer();
          // After syncing, load the updated data
          final updatedEvents = await _repository.loadLocal();
          if (mounted) {
            setState(() {
              _events = updatedEvents;
            });
          }
        } catch (syncErr) {
          debugPrint('Error syncing from server: $syncErr');
        }
      }
      
      widget.onEventsLoaded?.call();
    } catch (e) {
      debugPrint('Error loading life events: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void refresh() {
    if (!mounted) return;
    setState(() => _loading = true);
    
    _repository.syncFromServer().then((_) {
      return _repository.loadLocal();
    }).then((events) {
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
      widget.onEventsLoaded?.call();
    }).catchError((error) {
      debugPrint('Error refreshing life events: $error');
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  // Edit a life event
  Future<void> _editLifeEvent(LifeEvent event) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => LifeEventDialog(event: event),
    );

    if (result != null) {
      debugPrint('Updating life event: ${result['title']}');
      
      final updated = await _repository.updateLifeEvent(
        id: event.id,
        title: result['title'],
        occurredAt: result['occurredAt'],
        details: result['details'],
        tags: result['tags'],
      );
      
      if (updated == null) {
        debugPrint('Failed to update life event: API returned null');
      } else {
        debugPrint('Successfully updated life event with ID: ${updated.id}');
      }
      
      // Always refresh to ensure UI is consistent with server
      refresh();
    }
  }

  // Delete a life event
  Future<void> _deleteLifeEvent(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Life Event'),
        content: const Text(
          'Are you sure you want to delete this life event? This cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      debugPrint('Deleting life event with ID: $id');
      
      final success = await _repository.deleteLifeEvent(id);
      
      if (success) {
        debugPrint('Successfully deleted life event with ID: $id');
      } else {
        debugPrint('Failed to delete life event: API returned false');
      }
      
      // Always refresh to ensure UI is consistent with server
      refresh();
    }
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // if (_events.isEmpty) return const Text("Your Life Events will appear here...");
    if (_events.isEmpty) {
      return const Center(
        child: Text(
          "Your Life Events will appear here...",
          style: TextStyle(
            color: Colors.white70,   // or Colors.white
            fontSize: 14,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final isExpanded = _expanded[event.id] ?? false;
          
          final formattedDate = DateFormat('EEE, MMM d, y').format(event.occurredAt.toLocal());

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _expanded[event.id] = !isExpanded;
                      });
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedDate,
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                              if (event.tags != null && event.tags!.isNotEmpty)
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: event.tags!.map((tag) {
                                    final tagColor = _getTagColor(tag);
                                    return Chip(
                                      label: Text(tag),
                                      backgroundColor: tagColor.withValues(alpha: 0.2),
                                      labelStyle: TextStyle(color: tagColor.withValues(alpha: 0.8)),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      padding: EdgeInsets.zero,
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  
                  // Expanded content
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: isExpanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Divider
                              const Divider(
                                height: 20,
                                thickness: 1,
                              ),

                              // Event details
                              if (event.details != null && event.details!.isNotEmpty) ...[
                                const Text(
                                  "Details:",
                                  style: TextStyle(
                                    fontSize: 14, 
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  event.details!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Action buttons
                              Row(
                                children: [
                                  // Edit button
                                  ElevatedButton.icon(
                                    onPressed: () => _editLifeEvent(event),
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Edit'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(255, 75, 3, 143),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      elevation: 0,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Delete button
                                  ElevatedButton.icon(
                                    onPressed: () => _deleteLifeEvent(event.id),
                                    icon: const Icon(Icons.delete, size: 16),
                                    label: const Text('Delete'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      elevation: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Dialog for adding/editing life events
class LifeEventDialog extends StatefulWidget {
  final LifeEvent? event; // null for adding new, non-null for editing

  const LifeEventDialog({super.key, this.event});

  @override
  State<LifeEventDialog> createState() => _LifeEventDialogState();
}

class _LifeEventDialogState extends State<LifeEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  final _tagController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  List<String> _selectedTags = [];

  // Common tags to suggest
  final List<String> _suggestedTags = [
    'Family', 'Work', 'Health', 'Relationship', 'Travel', 
    'Education', 'Career', 'Home', 'Financial', 'Personal'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      _titleController.text = widget.event!.title;
      _detailsController.text = widget.event!.details ?? '';
      _selectedDate = widget.event!.occurredAt;
      _selectedTags = widget.event!.tags ?? [];
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_selectedTags.contains(tag)) {
      setState(() {
        _selectedTags.add(tag);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.event != null;
    
    return AlertDialog(
      title: Text(isEditing ? 'Edit Life Event' : 'Add Life Event'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title field
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Date picker
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                ),
              ),
              const SizedBox(height: 16),

              // Details field
              TextFormField(
                controller: _detailsController,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Tags field
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tagController,
                      decoration: const InputDecoration(
                        labelText: 'Add Tag',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    onPressed: _addTag,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Suggested tags
              Wrap(
                spacing: 8,
                children: _suggestedTags
                    .where((tag) => !_selectedTags.contains(tag))
                    .map((tag) => ActionChip(
                          label: Text(tag),
                          onPressed: () {
                            setState(() {
                              _selectedTags.add(tag);
                            });
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),

              // Selected tags
              if (_selectedTags.isNotEmpty) ...[
                const Text('Selected Tags:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _selectedTags
                      .map((tag) => Chip(
                            label: Text(tag),
                            onDeleted: () => _removeTag(tag),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop({
                'title': _titleController.text,
                'occurredAt': _selectedDate,
                'details': _detailsController.text,
                'tags': _selectedTags,
              });
            }
          },
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}