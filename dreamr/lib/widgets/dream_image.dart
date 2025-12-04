// widgets/dream_image.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dreamr/services/image_store.dart';
import 'package:dreamr/services/dio_client.dart';

class DreamImage extends StatefulWidget {
  final int dreamId;
  final String? url;                  // server URL (file or tile)
  final DreamImageKind kind;          // DreamImageKind.file | DreamImageKind.tile
  final double? width, height;
  final BoxFit fit;
  final Widget? placeholder;          // optional custom placeholder
  final Widget? error;                // optional error widget

  const DreamImage({
    super.key,
    required this.dreamId,
    required this.url,
    required this.kind,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  @override
  State<DreamImage> createState() => _DreamImageState();
}

class _DreamImageState extends State<DreamImage> {
  File? _file;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final url = widget.url;
    if (url == null || url.isEmpty) { setState(() { _loading = false; }); return; }

    // Try local
    final local = await ImageStore.localIfExists(widget.dreamId, widget.kind, url);
    if (!mounted) return;
    if (local != null) { setState(() { _file = local; _loading = false; }); return; }

    // Download once, then serve from disk forever
    try {
      final f = await ImageStore.download(widget.dreamId, widget.kind, url, dio: DioClient.dio);
      if (!mounted) return;
      setState(() { _file = f; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _file = null; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.placeholder ??
          SizedBox(
            width: widget.width, height: widget.height,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
    }
    if (_file != null) {
      return Image.file(
        _file!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      );
    }
    return widget.error ??
        Container(
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          color: Colors.black12,
          child: const Icon(Icons.broken_image),
        );
  }
}
