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
  final String description;
  final double weight;
  final List<Dream> dreams;

  const ThemeWeight({
    required this.label,
    required this.emoji,
    required this.description,
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

// =====================================================================
// AI-generated deep insights, fetched from /api/insights
// =====================================================================

class AiSymbol {
  final String name;
  final String meaning;
  final int appearsIn;

  const AiSymbol({required this.name, required this.meaning, required this.appearsIn});

  factory AiSymbol.fromJson(Map<String, dynamic> j) => AiSymbol(
        name: (j['name'] ?? '').toString(),
        meaning: (j['meaning'] ?? '').toString(),
        appearsIn: (j['appears_in'] is int) ? j['appears_in'] as int : int.tryParse('${j['appears_in']}') ?? 0,
      );
}

class AiThroughline {
  final String label;
  final String description;

  const AiThroughline({required this.label, required this.description});

  factory AiThroughline.fromJson(Map<String, dynamic> j) => AiThroughline(
        label: (j['label'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
      );
}

class AiPattern {
  final String headline;
  final String detail;

  const AiPattern({required this.headline, required this.detail});

  factory AiPattern.fromJson(Map<String, dynamic> j) => AiPattern(
        headline: (j['headline'] ?? '').toString(),
        detail: (j['detail'] ?? '').toString(),
      );
}

class DeepInsight {
  final int id;
  final DateTime generatedAt;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final int dreamCount;
  final String narrative;
  final List<AiSymbol> symbols;
  final List<AiThroughline> themes;
  final List<AiPattern> patterns;
  final List<String> questions;
  final String? model;
  final int promptVersion;

  const DeepInsight({
    required this.id,
    required this.generatedAt,
    required this.windowStart,
    required this.windowEnd,
    required this.dreamCount,
    required this.narrative,
    required this.symbols,
    required this.themes,
    required this.patterns,
    required this.questions,
    required this.model,
    required this.promptVersion,
  });

  factory DeepInsight.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return DeepInsight(
      id: (j['id'] is int) ? j['id'] as int : int.tryParse('${j['id']}') ?? 0,
      generatedAt: parse(j['generated_at']) ?? DateTime.now(),
      windowStart: parse(j['window_start']),
      windowEnd: parse(j['window_end']),
      dreamCount: (j['dream_count'] is int) ? j['dream_count'] as int : int.tryParse('${j['dream_count']}') ?? 0,
      narrative: (j['narrative'] ?? '').toString(),
      symbols: ((j['symbols'] as List?) ?? const [])
          .map((e) => AiSymbol.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      themes: ((j['themes'] as List?) ?? const [])
          .map((e) => AiThroughline.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      patterns: ((j['patterns'] as List?) ?? const [])
          .map((e) => AiPattern.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      questions: ((j['questions'] as List?) ?? const []).map((e) => e.toString()).toList(),
      model: j['model']?.toString(),
      promptVersion: (j['prompt_version'] is int) ? j['prompt_version'] as int : int.tryParse('${j['prompt_version']}') ?? 1,
    );
  }
}

/// Wraps the /api/insights response. Either locked (and tells the caller
/// how many more dreams are needed) or unlocked with an optional record.
class DeepInsightsResponse {
  final bool locked;
  final int? dreamsRequired;
  final int? current;
  final DeepInsight? insight;

  const DeepInsightsResponse({
    required this.locked,
    this.dreamsRequired,
    this.current,
    this.insight,
  });

  factory DeepInsightsResponse.fromJson(Map<String, dynamic> j) {
    final locked = j['locked'] == true;
    if (locked) {
      return DeepInsightsResponse(
        locked: true,
        dreamsRequired: (j['dreams_required'] is int) ? j['dreams_required'] as int : int.tryParse('${j['dreams_required']}'),
        current: (j['current'] is int) ? j['current'] as int : int.tryParse('${j['current']}'),
      );
    }
    final ins = j['insight'];
    return DeepInsightsResponse(
      locked: false,
      insight: ins is Map ? DeepInsight.fromJson(Map<String, dynamic>.from(ins)) : null,
    );
  }
}
