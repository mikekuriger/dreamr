// services/purchase_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:dreamr/services/api_service.dart';

/// Service for handling in-app purchases and subscriptions
class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
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
      return false;
    }

    try {
      _purchasePending = true;
      
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: null,
      );

      // Start the purchase flow (subscriptions are non-consumable on both platforms)
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      
      return true;
    } catch (e) {
      _error = 'Failed to purchase: $e';
      _purchasePending = false;
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    try {
      if (Platform.isIOS) {
        await InAppPurchase.instance.restorePurchases();
      }
      return true;
    } catch (e) {
      _error = 'Failed to restore purchases: $e';
      return false;
    }
  }

  /// Listen to purchase updates
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
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
      // Extract receipt data based on platform
      String? receipt;
      String? productId = purchaseDetails.productID;
      
      if (Platform.isIOS) {
        // Use the correct method for iOS receipt retrieval
        // The receipt is already available in the verification data
        receipt = purchaseDetails.verificationData.localVerificationData;
      } else if (Platform.isAndroid) {
        receipt = purchaseDetails.verificationData.serverVerificationData;
      }
      
      if (receipt != null && productId != null) {
        // Send to backend for verification
        final provider = Platform.isIOS
            ? 'apple'
            : (Platform.isAndroid ? 'google' : null);

        await ApiService.initiateSubscription(
          productId,
          paymentProvider: provider,
          receiptData: receipt,
        );
      }
    } catch (e) {
      _error = 'Failed to verify purchase: $e';
    }
  }

  /// Dispose of resources
  void dispose() {
    _subscription?.cancel();
  }
}