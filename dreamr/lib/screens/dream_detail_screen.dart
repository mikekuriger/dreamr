// screens/dream_detail_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/widgets/dream_journal_widget.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/services/image_store.dart';
import 'package:dreamr/services/dio_client.dart';

class DreamDetailScreen extends StatefulWidget {
  final Dream dream;
  /// When true, we wait for the dream image to be fetched/cached before
  /// showing the page so that image + text appear together.
  final bool prefetchImage;

  const DreamDetailScreen({
    super.key,
    required this.dream,
    this.prefetchImage = false,
  });

  @override
  State<DreamDetailScreen> createState() => _DreamDetailScreenState();
}

class _DreamDetailScreenState extends State<DreamDetailScreen> {
  late final Future<void> _prefetchFuture;

  @override
  void initState() {
    super.initState();
    if (widget.prefetchImage &&
        widget.dream.imageFile != null &&
        widget.dream.imageFile!.isNotEmpty) {
      _prefetchFuture = _prefetchDreamImageFile(widget.dream).then((_) {});
    } else {
      _prefetchFuture = Future.value();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget buildScaffold(Widget bodyChild) {
      return Scaffold(
        backgroundColor: AppColors.purple900,
        appBar: AppBar(
          backgroundColor: AppColors.purple950,
          foregroundColor: Colors.white,
          elevation: 4,
          title: const Text(
            'My Dream ✨',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: bodyChild,
        ),
      );
    }

    // If we're not prefetching (e.g. opened from the image viewer),
    // keep the original behavior and show the page immediately.
    if (!widget.prefetchImage ||
        widget.dream.imageFile == null ||
        widget.dream.imageFile!.isEmpty) {
      return buildScaffold(
        DreamJournalWidget(
          filteredDreams: [widget.dream],
          autoExpandSingle: true,
          embeddedInScrollView: false,
        ),
      );
    }

    // For the journal flow (prefetchImage == true), wait until the
    // image fetch attempt completes so everything appears at once.
    return FutureBuilder<void>(
      future: _prefetchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return buildScaffold(
            const Center(child: CircularProgressIndicator()),
          );
        }

        return buildScaffold(
          DreamJournalWidget(
            filteredDreams: [widget.dream],
            autoExpandSingle: true,
            embeddedInScrollView: false,
          ),
        );
      },
    );
  }
}

Future<File?> _prefetchDreamImageFile(Dream dream) async {
  final url = dream.imageFile;
  if (url == null || url.isEmpty) return null;

  // 1) Try local cache first.
  final hit = await ImageStore.localIfExists(dream.id, DreamImageKind.file, url);
  if (hit != null) return hit;

  // 2) Download once if missing.
  try {
    final file = await ImageStore.download(
      dream.id,
      DreamImageKind.file,
      url,
      dio: DioClient.dio,
    );
    return file;
  } catch (_) {
    return null;
  }
}
