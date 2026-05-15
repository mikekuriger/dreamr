// models/dream_insights.dart
import 'package:dreamr/models/dream.dart';

class SymbolHit {
  final String name;
  final String icon;
  final String meaning;
  final int count;
  final List<Dream> dreams;

  const SymbolHit({
    required this.name,
    required this.icon,
    required this.meaning,
    required this.count,
    required this.dreams,
  });
}

class ThemeWeight {
  final String label;
  final String emoji;
  final double weight;
  final List<Dream> dreams;

  const ThemeWeight({
    required this.label,
    required this.emoji,
    required this.weight,
    required this.dreams,
  });
}

class PatternFinding {
  final String headline;
  final String? detail;
  final List<Dream> dreams;

  const PatternFinding({
    required this.headline,
    this.detail,
    required this.dreams,
  });
}

class ToneSlice {
  final String label;
  final int count;
  final double percent;

  const ToneSlice({
    required this.label,
    required this.count,
    required this.percent,
  });
}

class DreamInsights {
  final int dreamCount;
  final int windowDays;
  final DateTime? earliest;
  final DateTime? latest;
  final List<SymbolHit> symbols;
  final List<ThemeWeight> themes;
  final List<PatternFinding> patterns;
  final List<ToneSlice> tones;

  const DreamInsights({
    required this.dreamCount,
    required this.windowDays,
    required this.earliest,
    required this.latest,
    required this.symbols,
    required this.themes,
    required this.patterns,
    required this.tones,
  });

  bool get isEmpty => dreamCount == 0;
}
