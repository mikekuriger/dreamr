// screens/image_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/widgets/dream_image.dart';
import 'package:dreamr/screens/dream_detail_screen.dart';
import 'package:dreamr/services/image_store.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mime/mime.dart';
import 'dart:io';
import 'package:dreamr/services/dio_client.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<Dream> dreams;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.dreams,
    required this.initialIndex,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _controller;
  late int _currentIndex;
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: _currentIndex);
  }

  // Compute origin rect for share sheets (iPad/macOS need an anchor).
  Rect _originFromKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return const Rect.fromLTWH(100, 100, 1, 1);
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) {
      return const Rect.fromLTWH(100, 100, 1, 1);
    }
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  String _buildShareText(Dream dream) {
    final userText = dream.text.trim();
    final summary = dream.summary.trim();
    final parts = <String>[];

    if (summary.isNotEmpty) parts.add(summary);
    if (userText.isNotEmpty) parts.add(userText);

    return parts.join('\n\n-- Dream Details\n\n');
  }

  Future<File?> _resolveImageFileForShare(Dream dream) async {
    if (dream.imageFile == null || dream.imageFile!.isEmpty) return null;

    final hit = await ImageStore.localIfExists(
      dream.id,
      DreamImageKind.file,
      dream.imageFile!,
    );
    if (hit != null) return hit;

    try {
      return await ImageStore.download(
        dream.id,
        DreamImageKind.file,
        dream.imageFile!,
        dio: DioClient.dio,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareDreamImage({
    required Dream dream,
    required Rect origin,
    required bool includeText,
  }) async {
    final file = await _resolveImageFileForShare(dream);
    final shareText = includeText ? _buildShareText(dream) : '';

    if (file == null || !await file.exists()) {
      if (shareText.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(text: shareText, sharePositionOrigin: origin),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image not available to share')),
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: lookupMimeType(file.path) ?? 'image/jpeg',
          ),
        ],
        text: shareText.isNotEmpty ? shareText : null,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _showShareOptions(Dream dream) async {
    final origin = _originFromKey(_shareButtonKey);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image, color: Colors.white),
                title: const Text(
                  'Share image only',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _shareDreamImage(
                    dream: dream,
                    origin: origin,
                    includeText: false,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.white),
                title: const Text(
                  'Share dream + image',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _shareDreamImage(
                    dream: dream,
                    origin: origin,
                    includeText: true,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.dreams.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final dream = widget.dreams[index];
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                InteractiveViewer(
                  child: DreamImage(
                    dreamId: dream.id,
                    url: dream.imageFile,
                    kind: DreamImageKind.file,
                    fit: BoxFit.contain,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height * 0.6,
                    placeholder: const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: const Center(
                      child: Icon(Icons.broken_image, size: 40, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    dream.summary,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32), // Add bottom padding so text doesn’t hit edge
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
  // Open dream button            
              ElevatedButton.icon(
                onPressed: () {
                  final dream = widget.dreams[_currentIndex];
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DreamDetailScreen(dream: dream),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open dream'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 75, 3, 143),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
  // Share button
              ElevatedButton(
                key: _shareButtonKey,
                onPressed: () => _showShareOptions(
                  widget.dreams[_currentIndex],
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 75, 3, 143),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(10), // tweak size if needed
                ),
                child: const Icon(Icons.share),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
