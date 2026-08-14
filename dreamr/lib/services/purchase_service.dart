// services/purchase_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
// import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

/// Service for handling in-app purchases and subscriptions
class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final FacebookAppEvents _facebookEvents = FacebookAppEvents();
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _loading = true;
  String? _error;

  // Getters
  bool get isAvailable => _isAvailable;
  bool get purchasePending => _purchasePending;
  bool get loading => _loading;
  String? get error => _error;
  List<ProductDetails> get products => _products;

  // Product IDs for subscriptions
  static const Set<String> _kProductIds = {
    'dreamr_pro_monthly',
    'dreamr_pro_yearly',
  };

  /// Initialize the purchase service
  Future<void> initialize() async {
    // Set up the listener for purchase updates
    final purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _listenToPurchaseUpdated,
      onDone: () {
        _subscription?.cancel();
      },
      onError: (error) {
        _error = error.toString();
      },
    );

    // Check if store is available
    final isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      _isAvailable = false;
      _loading = false;
      _error = 'Store is not available';
      return;
    }

    // Load products
    await loadProducts();
  }

  /// Load available products from the store
  Future<void> loadProducts() async {
    try {
      _loading = true;
      _error = null;
      
      final ProductDetailsResponse response = 
          await _inAppPurchase.queryProductDetails(_kProductIds);

      // Debug aid: log what the store actually returned so we can spot ID mismatches
      debugPrint(
        'IAP: queried $_kProductIds -> found: '
        '${response.productDetails.map((p) => p.id).join(", ")} '
        'notFound: ${response.notFoundIDs.join(", ")}',
      );

      if (response.notFoundIDs.isNotEmpty) {
        _error = 'Some products were not found: ${response.notFoundIDs.join(", ")}';
      }
      
      _products = response.productDetails;
      _isAvailable = true;
      _loading = false;
    } catch (e) {
      _error = 'Failed to load products: $e';
      _loading = false;
    }
  }

  /// Purchase a subscription
  Future<bool> purchaseSubscription(ProductDetails product) async {
    if (_purchasePending) {
      debugPrint('IAP: purchase already pending, ignoring new request');
      return false;
    }

    if (!_isAvailable) {
      _error = 'Store is not available';
      debugPrint('IAP: store not available, cannot start purchase');
      return false;
    }

    try {
      _purchasePending = true;

      debugPrint(
        'IAP: starting purchase for product=${product.id} '
        'on ${Platform.isIOS ? "iOS" : (Platform.isAndroid ? "Android" : "other")}',
      );
      
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: null,
      );

      // Start the purchase flow (subscriptions are non-consumable on both platforms)
      // On both iOS and Android, this initiates the purchase UI.
      // The *actual* result comes back via purchaseStream -> _listenToPurchaseUpdated.
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);

      // At this point we only know the flow was started successfully.
      // We keep _purchasePending = true until we get a callback.
      return true;
    } catch (e) {
      // Failed to even start the flow
      _error = 'Failed to purchase: $e';
      debugPrint('IAP: error starting purchase: $e');

      _purchasePending = false;

      // On iOS, this very often means:
      // - user canceled, OR
      // - user already owns the subscription.
      if (Platform.isIOS) {
        debugPrint(
          'IAP(iOS): purchase did not start; attempting restorePurchases() '
          'to sync any existing subscriptions for this Apple ID.',
        );
        try {
          await restorePurchases();
        } catch (restoreError) {
          debugPrint('IAP(iOS): restorePurchases also failed: $restoreError');
        }
      }
      
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    try {
      if (!_isAvailable) {
        return false;
      }

      if (Platform.isIOS) {
        // iOS: this will trigger purchase updates for past purchases,
        // which flow through _listenToPurchaseUpdated -> _verifyPurchase.
        await InAppPurchase.instance.restorePurchases();
        return true;
      }

      if (Platform.isAndroid) {
        // Android: actively query past purchases via the platform addition
        // and feed them through the same verification path.
        final androidAddition =
            _inAppPurchase.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final response = await androidAddition.queryPastPurchases();

        debugPrint(
          'IAP: restorePurchases(android) found: ${response.pastPurchases
                  .map((p) => '${p.productID}:${p.status}')
                  .join(', ')}',
        );

        for (final pastPurchase in response.pastPurchases) {
          await _verifyPurchase(pastPurchase);
          if (pastPurchase.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(pastPurchase);
          }
        }

        return true;
      }

      // Other platforms: nothing to restore.
      return false;
    } catch (e) {
      _error = 'Failed to restore purchases: $e';
      debugPrint('IAP: restorePurchases error: $e');
      return false;
    }
  }

  /// Listen to purchase updates
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    debugPrint(
      'SUB LIST: ${purchaseDetailsList
              .map((p) => '${p.productID}:${p.status}')
              .join(', ')}',
    );
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
      } else {
        _purchasePending = false;
        
        if (purchaseDetails.status == PurchaseStatus.error) {
          _error = 'Error: ${purchaseDetails.error?.message}';
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                  purchaseDetails.status == PurchaseStatus.restored) {
          // Verify the purchase with the backend
          await _verifyPurchase(purchaseDetails);
        }
        
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  /// Verify the purchase with the backend
  Future<void> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    try {
      String? receipt;
      final String productId = purchaseDetails.productID;

      if (Platform.isIOS) {
        // For StoreKit 2, serverVerificationData is the signed JWS meant for
        // your server (localVerificationData is the *unverified* JSON —
        // fine for on-device use, but the backend can't cryptographically
        // check it came from Apple). Fixed Aug 2026: this used to read
        // localVerificationData, which silently sent unsigned data to the
        // backend for every purchase.
        receipt = purchaseDetails.verificationData.serverVerificationData;
        // Google Play purchase token – used with Google Play Developer API.
      } else if (Platform.isAndroid) {
        receipt = purchaseDetails.verificationData.serverVerificationData;
      }

      if (receipt != null) {
        final provider =
            Platform.isIOS ? 'apple' : (Platform.isAndroid ? 'google' : null);

        debugPrint(
          'IAP: sending to backend provider=$provider product=$productId '
          'receipt=${receipt.substring(0, 40)}...',
        );

        await ApiService.initiateSubscription(
          productId,
          paymentProvider: provider,
          receiptData: receipt,
        );

        // Log purchase to Facebook Ads
        final product = _products.firstWhere(
          (p) => p.id == productId,
          orElse: () => _products.first,
        );
        await _facebookEvents.logPurchase(
          amount: product.rawPrice,
          currency: product.currencyCode,
          parameters: {'content_id': productId},
        );
      } else {
        debugPrint(
          'IAP: missing receipt or productId for ${purchaseDetails.productID} '
          'on ${Platform.isIOS ? "iOS" : "Android"}',
        );
      }
    } catch (e) {
      _error = 'Failed to verify purchase: $e';
      debugPrint('IAP: _verifyPurchase error: $e');
    }
  }


  /// Dispose of resources
  void dispose() {
    _subscription?.cancel();
  }
}