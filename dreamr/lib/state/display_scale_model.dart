import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefKey = 'display_scale';

/// User-chosen UI scale multiplier applied on top of the system text scale.
/// Persisted to SharedPreferences.
class DisplayScaleModel extends ChangeNotifier {
  double _scale = 1.0;
  double get scale => _scale;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _scale = prefs.getDouble(_kPrefKey) ?? 1.0;
    notifyListeners();
  }

  Future<void> setScale(double value) async {
    if (_scale == value) return;
    _scale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefKey, value);
  }
}
