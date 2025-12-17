// widgets/dream_journal_editor_widget.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:dreamr/widgets/dream_image.dart';
import 'package:dreamr/services/image_store.dart'; // for DreamImageKind



class DreamJournalEditorWidget extends StatefulWidget {
  final VoidCallback? onDreamsLoaded;

  const DreamJournalEditorWidget({
    super.key,
    this.onDreamsLoaded,
  });

  @override
  State<DreamJournalEditorWidget> createState() => DreamJournalEditorWidgetState();
}

class ToneStyle {
  final Color background;
  final Color text;
  const ToneStyle(this.background, this.text);
}

class DreamJournalEditorWidgetState extends State<DreamJournalEditorWidget> {
  
  List<Dream> _dreams = [];
  List<Dream> getDreams() => _dreams;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDreams();
  }

  
  ToneStyle _getToneStyle(String tone) {
    final t = tone.toLowerCase().trim();
    switch (t) {
      case 'peaceful / gentle':
        return ToneStyle(Colors.blue.shade100, Colors.black87);
      case 'epic / heroic':
        return ToneStyle(Colors.orange.shade100, Colors.black87);
      case 'whimsical / surreal':
        return ToneStyle(Colors.purple.shade100, Colors.black87);
      case 'nightmarish / dark':
        // return ToneStyle(Colors.black, Colors.red.shade500);  // 👈 spooky red
        return ToneStyle(Colors.grey.shade900, Colors.orange.shade200);  // 👈 spooky red
      case 'romantic / nostalgic':
        return ToneStyle(Colors.pink.shade100, Colors.black87);
      case 'ancient / mythic':
        return ToneStyle(Colors.brown.shade100, Colors.black87);
      case 'futuristic / uncanny':
        return ToneStyle(Colors.teal.shade100, Colors.black87);
      case 'elegant / ornate':
        return ToneStyle(Colors.indigo.shade100, Colors.black87);
      default:
        return ToneStyle(Colors.grey.shade100, Colors.black87);
    }
  }

  Future<void> _loadDreams() async {
    try {
      final dreams = await ApiService.fetchAllDreams();
      setState(() {
        _dreams = dreams;
        _loading = false;
      });
      widget.onDreamsLoaded?.call();
    } catch (e) {
      // print("❌ Failed to fetch dreams: $e");
      setState(() {
        _loading = false;
      });
    }
  }

  void refresh() {
    setState(() => _loading = true);
    _loadDreams();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_dreams.isEmpty) return const Text("Your Dreams will appear here...");

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0), // remove side gap
      child: ListView.builder(
        padding: EdgeInsets.zero, 
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _dreams.length,
        itemBuilder: (context, index) {
          final dream = _dreams[index];
          final toneStyle = _getToneStyle(dream.tone);
          final formattedDate = DateFormat('EEE, MMM d, y').format(dream.createdAt.toLocal());

          return Padding(
            key: Key('dream-${dream.id}'), // Add unique key for proper widget reuse
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: toneStyle.background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (dream.imageTile != null && dream.imageTile!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                        child: DreamImage(
                          dreamId: dream.id,
                          url: dream.imageTile!,
                          kind: DreamImageKind.tile,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      // child: Image.network(
                      //   dream.imageTile!,
                      //   width: 48,
                      //   height: 48,
                      //   fit: BoxFit.cover,
                      // ),
                    ),
                  const SizedBox(width: 6),
                  // Date and summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattedDate,
                          style: TextStyle(fontSize: 12, color: toneStyle.text),
                        ),
                        Text(
                          dream.summary,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: toneStyle.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      dream.hidden ? Icons.visibility_off : Icons.visibility,
                      // color: const Color.fromARGB(255, 255, 255, 255),
                      color: toneStyle.text,
                    ),
                    onPressed: () async {
                      try {
                        final newHidden = await ApiService.toggleHiddenDream(dream.id);

                        setState(() {
                          _dreams = _dreams.map((d) {
                            return d.id == dream.id
                                ? d.copyWith(hidden: newHidden)
                                : d;
                          }).toList();
                        });
                      } catch (e) {
                        if (mounted) {
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.showSnackBar(
                            const SnackBar(content: Text('❌ Failed to update dream visibility')),
                          );
                        }
                      }
                    },
                  ),
                  IconButton(
                    // icon: const Icon(Icons.delete, color: Color.fromARGB(255, 0, 0, 0)),
                    icon: Icon(Icons.delete, color: toneStyle.text),
                    color: toneStyle.text,
                    tooltip: "Delete",
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Dream'),
                          content: const Text('Are you sure you want to delete this dream?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          await ApiService.deleteDream(dream.id);

                          if (!mounted) return; // check after the await
                          // final messenger = ScaffoldMessenger.of(context); // capture after await

                          setState(() {
                            _dreams.removeWhere((d) => d.id == dream.id);
                          });

                          // messenger.showSnackBar(
                          //   const SnackBar(content: Text('🗑️ Dream deleted')),
                          // );
                        } catch (e) {
                          if (!mounted) return;
                          final messenger = ScaffoldMessenger.of(context); // capture after await
                          messenger.showSnackBar(
                            const SnackBar(content: Text('❌ Failed to delete dream')),
                          );
                        }
                      }
                    }
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}
