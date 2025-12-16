// models/interpreter.dart
class Interpreter {
  final int id;
  final String slug;
  final String name;
  final String accessTier;
  final String cardBlurb;
  final List<String> cardBullets;
  final List<String> toneExamples;
  final String iconFile;

  Interpreter({
    required this.id,
    required this.slug,
    required this.name,
    required this.accessTier,
    required this.cardBlurb,
    required this.cardBullets,
    required this.toneExamples,
    required this.iconFile,
  });

  factory Interpreter.fromJson(Map<String, dynamic> json) {
    return Interpreter(
      id: json['id'] as int? ?? 0,
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Interpreter',
      accessTier: json['access_tier'] as String? ?? 'free',
      cardBlurb: json['card_blurb'] as String? ?? '',
      cardBullets: List<String>.from(json['card_bullets'] ?? []),
      toneExamples: List<String>.from(json['tone_examples'] ?? []),
      iconFile: json['icon'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'name': name,
      'access_tier': accessTier,
      'card_blurb': cardBlurb,
      'card_bullets': cardBullets,
      'tone_examples': toneExamples,
      'icon': iconFile,
    };
  }
}