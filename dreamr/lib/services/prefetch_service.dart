// services/prefetch_service.dart
import 'package:dreamr/constants.dart';
import 'package:dreamr/screens/image_style_selection_screen.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/services/image_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PrefetchService {
  /// Fire-and-forget cache warm-up. Call after login without awaiting.
  static void warmUp() => _run();

  static Future<void> _run() async {
    final cache = DefaultCacheManager();

    Future<void> fetch(String url) async {
      try {
        final file = await cache.downloadFile(url);
        debugPrint('📦 Prefetch cached: ${file.file.path.split('/').last} <- $url');
      } catch (e) {
        debugPrint('❌ Prefetch failed: $url ($e)');
      }
    }

    Future<void> fetchStyles() async {
      await Future.wait(allStylePreviewUrls().map(fetch));
    }

    Future<void> fetchInterpreterIcons() async {
      try {
        final interpreters = await ApiService.fetchInterpreters();
        await Future.wait(
          interpreters
              .where((i) => i.iconFile.isNotEmpty)
              .map((i) => fetch(
                    i.iconFile.startsWith('http')
                        ? i.iconFile
                        : '${AppConfig.baseUrl}${i.iconFile}',
                  )),
        );
      } catch (_) {}
    }

    Future<void> fetchDreamImages() async {
      try {
        final dreams = await ApiService.fetchDreams();
        await Future.wait(dreams.map((d) async {
          try {
            if (d.imageFile != null && d.imageFile!.isNotEmpty) {
              final f = await ImageStore.download(d.id, DreamImageKind.file, d.imageFile!);
              debugPrint('📦 Prefetch dream file: ${f.path.split('/').last}');
            }
            if (d.imageTile != null && d.imageTile!.isNotEmpty) {
              final f = await ImageStore.download(d.id, DreamImageKind.tile, d.imageTile!);
              debugPrint('📦 Prefetch dream tile: ${f.path.split('/').last}');
            }
          } catch (_) {}
        }));
      } catch (_) {}
    }

    // Interpreter icons first — visible immediately on the dashboard
    await fetchInterpreterIcons();
    // Then styles + dreams in parallel (lower priority, larger downloads)
    await Future.wait([fetchStyles(), fetchDreamImages()]);
  }
}
