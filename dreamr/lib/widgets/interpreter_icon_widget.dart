// widgets/interpreter_icon_widget.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:dreamr/theme/colors.dart';

/// Displays a looping MP4 video if the URL ends in `.mp4`, otherwise a PNG.
/// Used for interpreter icons throughout the app.
class InterpreterIconWidget extends StatefulWidget {
  final String url;
  final double iconSize;

  const InterpreterIconWidget({
    super.key,
    required this.url,
    this.iconSize = 24,
  });

  @override
  State<InterpreterIconWidget> createState() => _InterpreterIconWidgetState();
}

class _InterpreterIconWidgetState extends State<InterpreterIconWidget> {
  VideoPlayerController? _controller;
  bool _videoReady = false;

  bool get _isVideo => widget.url.toLowerCase().endsWith('.mp4');

  @override
  void initState() {
    super.initState();
    if (_isVideo) _initVideo();
  }

  @override
  void didUpdateWidget(InterpreterIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _videoReady = false;
      if (_isVideo) _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() => _videoReady = true);
    } catch (e) {
      debugPrint('⚠️ Interpreter video init failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _placeholder() => Container(
        color: AppColors.purple950,
        child: Center(
          child: Icon(Icons.person, color: const Color(0xFF82D9FF), size: widget.iconSize),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isVideo) {
      if (_videoReady && _controller != null) {
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        );
      }
      return _placeholder();
    }

    return CachedNetworkImage(
      imageUrl: widget.url,
      fit: BoxFit.cover,
      placeholder: (context, _) => _placeholder(),
      errorWidget: (context, _, err) => _placeholder(),
    );
  }
}
