// screens/dream_gallery_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/screens/image_viewer_screen.dart';
import 'package:dreamr/constants.dart';
import 'package:dreamr/widgets/dream_image.dart';
import 'package:dreamr/services/image_store.dart';



class DreamGalleryScreen extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  const DreamGalleryScreen({super.key, required this.refreshTrigger});

  @override
  State<DreamGalleryScreen> createState() => _DreamGalleryScreenState();
}

class _DreamGalleryScreenState extends State<DreamGalleryScreen> {
  List<Dream> _dreams = [];            // all dreams
  bool _loading = true;
  
  @override
  void initState() {
    super.initState();

    // Initial load
    _loadDreams();

    // Refresh every time index changes
    widget.refreshTrigger.addListener(() {
      _loadDreams(); 
    });

    // Listen for changes to dream data
    dreamDataChanged.addListener(_handleDreamDataChanged);
  }

  void _handleDreamDataChanged() {
    if (dreamDataChanged.value) {
      _loadDreams(); // 👈 Refresh gallery
      dreamDataChanged.value = false;
    }
  }

  @override
  void dispose() {
    dreamDataChanged.removeListener(_handleDreamDataChanged);
    widget.refreshTrigger.removeListener(_loadDreams);  // if you used addListener inline above
    super.dispose();
  }
  
  Future<void> _loadDreams() async {
    setState(() {
      _loading = true;
    });

    final dreams = await ApiService.fetchGallery();

    setState(() {
      _dreams = dreams;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        itemCount: _dreams.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          final dream = _dreams[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ImageViewerScreen(
                          dreams: _dreams,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                      child: DreamImage(
                        dreamId: dream.id,
                        url: dream.imageFile ?? '',
                        kind: DreamImageKind.file,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          color: Colors.grey[300],
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        error: Container(
                          color: Colors.grey[300],
                          child: const Center(child: Icon(Icons.broken_image, size: 40)),
                        ),
                      ),
                    // child: Image.network(
                    //   dream.imageFile ?? '',
                    //   width: double.infinity,
                    //   fit: BoxFit.cover,
                    //   errorBuilder: (context, error, stackTrace) =>
                    //       const Center(child: Icon(Icons.broken_image, size: 40)),
                    // ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
