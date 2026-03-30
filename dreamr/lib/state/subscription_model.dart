// state/subscription_model.dart
import 'package:flutter/foundation.dart';
import 'package:dreamr/models/subscription.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/services/purchase_service.dart';
// import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ChangeNotifier for managing subscription state throughout the app
class SubscriptionModel extends ChangeNotifier {
  final PurchaseService _purchaseService = PurchaseService();
  
  SubscriptionStatus? _status;
  List<SubscriptionPlan>? _plans;
  bool _loading = false;
  String? _error;

  /// Current subscription status
  SubscriptionStatus get status => _status ?? SubscriptionStatus.free();
  SubscriptionStatus? get statusOrNull => _status;
  bool get loaded => _status != null;

  /// Reset the subscription model state
  void reset() {
    _status = null;
    _plans = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
  
  /// Available subscription plans
  List<SubscriptionPlan> get plans => _plans ?? [];
  
  /// Whether subscription data is currently loading
  bool get loading => _loading;
  
  /// Any error that occurred during the last operation
  String? get error => _error;

  /// Initialize the subscription model
  Future<void> init() async {
    await _purchaseService.initialize();
    await refresh();
  }

  static const _kPrefIsActive = 'sub_is_active';
  static const _kPrefTier = 'sub_tier';
  static const _kPrefTextWeek = 'sub_text_week';

  Future<void> _saveToCache(SubscriptionStatus s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefIsActive, s.isActive);
    await prefs.setString(_kPrefTier, s.tier);
    await prefs.setInt(_kPrefTextWeek, s.freeCredits ?? 0);
    debugPrint('💾 Subscription cached: isActive=${s.isActive} tier=${s.tier}');
  }

  Future<SubscriptionStatus?> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kPrefIsActive)) return null;
    return SubscriptionStatus(
      isActive: prefs.getBool(_kPrefIsActive) ?? false,
      tier: prefs.getString(_kPrefTier) ?? 'free',
      freeCredits: prefs.getInt(_kPrefTextWeek),
      purchasedCredits: null,
      autoRenew: false,
      expiryDate: null,
      nextReset: null,
    );
  }

  /// Refresh subscription data from the server
  Future<void> refresh() async {
    if (_loading) return;

    // Load cached status immediately so UI is never empty while waiting
    if (_status == null) {
      final cached = await _loadFromCache();
      if (cached != null) {
        _status = cached;
        notifyListeners();
      }
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Load subscription status and plans in parallel
      final results = await Future.wait([
        ApiService.getSubscriptionStatus(),
        ApiService.getSubscriptionPlans(),
      ]);

      _status = results[0] as SubscriptionStatus;
      debugPrint('SUB: isActive=${_status?.isActive} tier=${_status?.tier} freeCredits=${_status?.freeCredits} purchased=${_status?.purchasedCredits}');
      await _saveToCache(_status!);

      // Free users should not retain pro-locked interpreter/style selections
      if (!_status!.isActive) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('selected_image_style');
        await prefs.remove('selected_interpreter_id');
        await prefs.remove('selected_interpreter_json');
        debugPrint('SUB: free user — cleared interpreter and image style prefs');
      }

      _plans = results[1] as List<SubscriptionPlan>;

      // Also refresh store products
      if (_purchaseService.isAvailable) {
        await _purchaseService.loadProducts();
      }
    } catch (e) {
      // Offline — keep cached status, just log the error
      debugPrint('ℹ️ Subscription refresh failed (offline?): $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Initiate a subscription purchase for a given plan
  Future<Map<String, dynamic>?> subscribe(SubscriptionPlan plan) async {
    if (_loading) return null;
    
    _loading = true;
    _error = null;
    notifyListeners();
    
    try {
      // First check if we can use in-app purchases
      if (_purchaseService.isAvailable) {
        // Prefer the store-specific productId from the plan; fall back to the plan id
        final targetId = plan.productId ?? plan.id;

        debugPrint('SUB: attempting purchase for plan=${plan.id} productId=$targetId');

        // Find matching product in store
        final storeProduct = _purchaseService.products.firstWhere(
          (product) => product.id == targetId,
          orElse: () {
            final available =
                _purchaseService.products.map((p) => p.id).join(', ');
            throw Exception(
              'Product not available in store (id=$targetId, store has: [$available])',
            );
          },
        );
        
        // Initiate purchase through store
        final success = await _purchaseService.purchaseSubscription(storeProduct);
        if (!success) {
          throw Exception('Purchase flow was not completed');
        }
        
        // Return empty map as the purchase is being processed asynchronously
        return {};
      } else {
        // Fallback to web/direct purchase flow (uses plan primary key on the backend)
        final result = await ApiService.initiateSubscription(plan.id);
        await refresh(); // Refresh status after subscribing
        return result;
      }
    } catch (e, st) {
      // Log detailed error so we can see exactly why the purchase failed
      debugPrint('SUB ERROR: Failed to initiate subscription for plan='
          '${plan.id} productId=${plan.productId ?? plan.id}: $e\n$st');

      _error = 'Failed to initiate subscription: $e';
      notifyListeners();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
  
  /// Restore previous purchases (iOS only)
  Future<bool> restorePurchases() async {
    if (_loading) return false;
    
    _loading = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await _purchaseService.restorePurchases();
      if (success) {
        await refresh(); // Refresh status after restoration
      }
      return success;
    } catch (e) {
      _error = 'Failed to restore purchases: $e';
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Cancel the current subscription
  Future<bool> cancelSubscription() async {
    if (_loading) return false;
    
    _loading = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await ApiService.cancelSubscription();
      if (success) {
        await refresh(); // Refresh status after cancellation
      }
      return success;
    } catch (e) {
      _error = 'Failed to cancel subscription: $e';
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Update payment method
  Future<bool> updatePaymentMethod(Map<String, dynamic> paymentDetails) async {
    if (_loading) return false;
    
    _loading = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await ApiService.updatePaymentMethod(paymentDetails);
      return success;
    } catch (e) {
      _error = 'Failed to update payment method: $e';
      notifyListeners();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Check if user has an active premium subscription
  // bool get isPremium => status.tier != 'free' && status.isActive;
  bool get isPremium => _status?.isActive ?? false;

  // bool get isPremium {
  //   final s = _status;
  //   if (s == null) return false;              // not loaded yet
  //   return s.isActive && s.tier != 'free';
  // }
}