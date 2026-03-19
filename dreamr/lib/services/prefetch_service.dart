// services/prefetch_service.dart
import 'package:dreamr/constants.dart';
import 'package:dreamr/screens/image_style_selection_screen.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PrefetchService {
  /// Fire-and-forget cache warm-up. Call after login without awaiting.
  static void warmUp() => _run();

  static Future<void> _run() async {
    final cache = DefaultCacheManager();

    Future<void> fetch(String url) async {
      try { await cache.downloadFile(url); } catch (_) {}
    }

    // 1. Style preview images — URLs are fully predictable from hardcoded data
    await Future.wait(allStylePreviewUrls().map(fetch));

    // 2. Interpreter icons — fetch list from API then download each icon
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
}
