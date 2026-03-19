// state/dream_list_model.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/repository/dream_repository.dart';

class DreamListModel extends ChangeNotifier {
  final DreamRepository repo;
  final bool includeHidden;

  List<Dream> _dreams = [];
  List<Dream> get dreams => _dreams;

  StreamSubscription<List<Dream>>? _sub;
  bool _loading = false;
  bool get loading => _loading;

  DreamListModel({required this.repo, this.includeHidden = false});

  Future<void> init() async {
    _sub = repo.stream.listen((list) {
      _dreams = list;
      notifyListeners();
    });
    await repo.loadLocal(includeHidden: includeHidden);
    unawaited(refresh()); // kick remote sync
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true; notifyListeners();
    try {
      await repo.syncFromServer(includeHidden: includeHidden, prefetchImages: true);
    } catch (_) {
      // Offline or server error — local data already loaded, nothing more to do
    } finally {
      _loading = false; notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
