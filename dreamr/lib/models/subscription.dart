// models/subscription.dart

/// A one-time purchasable credit pack
class CreditPack {
  final String id;
  final String name;
  final int credits;
  final double priceUsd;
  final String? productId; // App Store / Play Store product ID

  const CreditPack({
    required this.id,
    required this.name,
    required this.credits,
    required this.priceUsd,
    this.productId,
  });

  factory CreditPack.fromJson(Map<String, dynamic> json) {
    return CreditPack(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      credits: (json['credits'] as num?)?.toInt() ?? 0,
      priceUsd: (json['price_usd'] as num?)?.toDouble() ?? 0.0,
      productId: json['product_id'] as String?,
    );
  }
}

/// Represents a subscription plan in the app
class SubscriptionFeatureCard {
  final String key;
  final String title;
  final String description;

  const SubscriptionFeatureCard({
    required this.key,
    required this.title,
    required this.description,
  });

  factory SubscriptionFeatureCard.fromJson(Map<String, dynamic> json) {
    return SubscriptionFeatureCard(
      key: (json['key'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'title': title,
      'description': description,
    };
  }
}

/// Represents a subscription plan in the app
class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final String period; // 'monthly', 'yearly', etc.
  final List<String> features;
  final List<SubscriptionFeatureCard> featureCards;
  final String? productId; // Store/platform specific product ID

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.period,
    required this.features,
    required this.featureCards,
    this.productId,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    final rawFeatureCards = json['feature_cards'];

    return SubscriptionPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      period: json['period'] as String,
      features: rawFeatures is List
          ? rawFeatures.map((e) => e.toString()).toList()
          : const <String>[],
      featureCards: rawFeatureCards is List
          ? rawFeatureCards
              .whereType<Map>()
              .map((e) => SubscriptionFeatureCard.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList()
          : const <SubscriptionFeatureCard>[],
      productId: json['product_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'period': period,
      'features': features,
      'feature_cards': featureCards.map((e) => e.toJson()).toList(),
      'product_id': productId,
    };
  }
}

/// Represents the user's subscription status
class SubscriptionStatus {
  final String tier; // e.g. "free", "pro_yearly"
  final DateTime? expiryDate;
  final bool isActive;
  final bool autoRenew;
  // final String? paymentMethod;

  // Free-only fields. Null for paid.
  final int? freeCredits;
  final int? purchasedCredits;
  final DateTime? nextReset;

  int get totalCredits => (freeCredits ?? 0) + (purchasedCredits ?? 0);

  SubscriptionStatus({
    required this.tier,
    required this.isActive,
    required this.autoRenew,
    required this.expiryDate,
    required this.freeCredits,
    required this.purchasedCredits,
    required this.nextReset,
  });

  factory SubscriptionStatus.free() => SubscriptionStatus(
    tier: 'free',
    isActive: false,
    autoRenew: false,
    expiryDate: null,
    freeCredits: null,
    purchasedCredits: null,
    nextReset: null,
  );

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
    }

  static DateTime? _toDateTime(dynamic v) {
    if (v is String && v.isNotEmpty) {
      return DateTime.tryParse(v.replaceFirst('Z', '+00:00'));
    }
    return null;
  }

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      tier: (json['tier'] ?? 'free').toString(),
      isActive: json['is_active'] == true,
      autoRenew: json['auto_renew'] == true,
      expiryDate: _toDateTime(json['expiry_date']),
      freeCredits: _toInt(json['free_credits']),
      purchasedCredits: _toInt(json['purchased_credits']),
      nextReset: _toDateTime(json['next_reset_iso']),
    );
  }
}