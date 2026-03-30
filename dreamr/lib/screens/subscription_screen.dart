// screens/subscription_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/models/subscription.dart';
import 'package:dreamr/state/subscription_model.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionScreen extends StatefulWidget {
  final VoidCallback? onDone;

  const SubscriptionScreen({super.key, this.onDone});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with WidgetsBindingObserver {
  bool _loading = false;
  List<CreditPack> _creditPacks = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Map<String, ProductDetails> _storeProducts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionModel>().refresh();
      _initIAP();
    });
  }

  Future<void> _initIAP() async {
    final packs = await ApiService.fetchCreditPacks();
    if (!mounted) return;
    setState(() => _creditPacks = packs);

    final available = await InAppPurchase.instance.isAvailable();
    if (!available || !mounted) return;

    final ids = packs
        .where((p) => p.productId != null && p.productId!.isNotEmpty)
        .map((p) => p.productId!)
        .toSet();

    if (ids.isNotEmpty) {
      final response = await InAppPurchase.instance.queryProductDetails(ids);
      if (mounted) {
        setState(() {
          _storeProducts = {for (final pd in response.productDetails) pd.id: pd};
        });
      }
    }

    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) => debugPrint('IAP stream error: $e'),
    );
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Purchase failed: ${purchase.error?.message ?? "Unknown error"}')),
          );
        }
        await InAppPurchase.instance.completePurchase(purchase);
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final pack = _creditPacks.firstWhere((p) => p.productId == purchase.productID);
          final receipt = purchase.verificationData.serverVerificationData;
          await ApiService.deliverCreditPurchase(pack.id, receipt);
          if (mounted) await context.read<SubscriptionModel>().refresh();
        } catch (e) {
          debugPrint('Credit delivery failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Purchase recorded but credits could not be delivered. Please contact support.')),
            );
          }
        }
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (!mounted) return;

    // When returning from App Store / browser, refresh status
    if (state == AppLifecycleState.resumed) {
      debugPrint('SUB UI: app resumed, refreshing subscription status...');
      context.read<SubscriptionModel>().refresh();
    }
  }

  // Format currency based on price
  // Handle subscription purchase
  Future<void> _subscribe(SubscriptionPlan plan) async {
    debugPrint('SUB UI: subscribe tapped for plan=${plan.id}');

    setState(() => _loading = true);

    final model = context.read<SubscriptionModel>();

    try {
      final result = await model.subscribe(plan);

      if (result != null && result.containsKey('payment_url')) {
        final url = result['payment_url'] as String;
        final uri = Uri.parse(url);

        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open payment page')),
            );
          }
        }
      }

      await model.refresh();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 17, 19, 42),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Dreamr ✨ Subscription",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "Unlock all features with a subscription ",
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Color(0xFFD1B2FF),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.purple950,
        foregroundColor: Colors.white,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            widget.onDone?.call();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        top: false, // AppBar already handles top
        bottom: true, // respect bottom safe area
        child: Consumer<SubscriptionModel>(
          builder: (context, model, child) {
            if (model.loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (model.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error: ${model.error}',
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => model.refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final proYearly = _pickProPlan(model.plans, desiredPeriod: 'year');
            final proMonthly = _pickProPlan(model.plans, desiredPeriod: 'month');

            final featureCards = (proYearly?.featureCards.isNotEmpty == true)
                ? proYearly!.featureCards
                : (proMonthly?.featureCards.isNotEmpty == true)
                    ? proMonthly!.featureCards
                    : const <SubscriptionFeatureCard>[];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCurrentSubscription(model.status),
                  const SizedBox(height: 6),

                  Center(
                    child: TextButton(
                      onPressed: model.loading
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final success = await model.restorePurchases();
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'Purchases restored successfully'
                                        : 'Failed to restore purchases',
                                  ),
                                ),
                              );
                            },
                      child: Text(
                        'Restore Purchases',
                        style: TextStyle(
                          color: model.loading ? Colors.grey : Colors.amber,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),

                  if (_creditPacks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildCreditPacksSection(model.status),
                  ],

                  const SizedBox(height: 48),
                  const Divider(color: Colors.white24, thickness: 1),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.workspace_premium, color: Color.fromARGB(255, 203, 130, 255), size: 28),
                      SizedBox(width: 8),
                      Text(
                        'Pro Subscription',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Unlimited dreams, image generation, discussion, and more.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  if (proYearly != null || proMonthly != null)
                    _buildSubscriptionRow(proMonthly, proYearly, model.status)
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No Pro subscription plans available at the moment.',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  if (featureCards.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _buildProFeaturesSection(featureCards),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => launchUrl(Uri.parse(
                    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/')),
                child: const Text(
                  'Terms of Use',
                  style: TextStyle(
                    color: Color.fromARGB(255, 122, 209, 255),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '|',
                style: TextStyle(
                  color: Color.fromARGB(200, 122, 209, 255),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => launchUrl(Uri.parse(
                    'https://dreamr-us-west-01.zentha.me/static/privacy.html')),
                child: const Text(
                  'Privacy Policy',
                  style: TextStyle(
                    color: Color.fromARGB(255, 122, 209, 255),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SubscriptionPlan? _pickProPlan(List<SubscriptionPlan> plans,
      {required String desiredPeriod}) {
    final needle = desiredPeriod.toLowerCase();

    SubscriptionPlan? best;

    for (final p in plans) {
      final id = p.id.toLowerCase();
      final period = p.period.toLowerCase();

      // avoid trial plan(s)
      if (id.contains('trial')) continue;

      final isPro = id.contains('pro');
      final matchesPeriod = id.contains(needle) || period.contains(needle);

      if (isPro && matchesPeriod) {
        best = p;
        break;
      }
    }

    return best;
  }

  IconData _iconForFeatureKey(String key) {
    switch (key) {
      case 'unlimited_analysis':
        return Icons.psychology;
      case 'dream_statistics':
        return Icons.bar_chart;
      case 'priority_support':
        return Icons.support_agent;
      case 'followup_questions':
        return Icons.contact_support;
      case 'life_events':
        return Icons.favorite;
      case 'sharing':
        return Icons.share;
      case 'image_styles':
        return Icons.auto_awesome;
      case 'dream_visuals':
        return Icons.palette;
      case 'interpreter_personas':
        return Icons.face;
      case 'color_coded_journal':
        return Icons.edit_note_sharp;
      default:
        return Icons.star;
    }
  }

  Widget _buildProFeaturesSection(List<SubscriptionFeatureCard> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.workspace_premium, color: Colors.amber, size: 32),
            SizedBox(width: 8),
            Text(
              'Dreamr Pro Features',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // const Text(
        //   'Everything included with Pro (monthly and yearly):',
        //   style: TextStyle(
        //     color: Colors.white70,
        //     fontSize: 12,
        //   ),
        // ),
        const SizedBox(height: 12),
        ...cards.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 17, 0, 87),
                    // color: AppColors.purple850,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color.fromARGB(90, 130, 217, 255),
                      width: .5,
                    ),
                  ),
                  child: Icon(
                    _iconForFeatureKey(c.key),
                    color: const Color.fromARGB(255, 130, 217, 255),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.description,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionRow(
      SubscriptionPlan? monthly, SubscriptionPlan? yearly, SubscriptionStatus currentStatus) {
    // Calculate yearly savings vs paying monthly
    String yearlyBanner = 'Best Value';
    if (monthly != null && yearly != null && monthly.price > 0) {
      final fullYearCost = monthly.price * 12;
      final savingsPct = ((fullYearCost - yearly.price) / fullYearCost * 100).round();
      if (savingsPct > 0) yearlyBanner = 'Save $savingsPct%';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (monthly != null) ...[
          Expanded(child: SizedBox(height: 176, child: _buildSubscriptionCard(monthly, currentStatus, topLabel: 'Monthly'))),
        ],
        if (monthly != null && yearly != null) const SizedBox(width: 8),
        if (yearly != null) ...[
          Expanded(child: SizedBox(height: 176, child: _buildSubscriptionCard(yearly, currentStatus, topLabel: yearlyBanner))),
        ],
      ],
    );
  }

  Widget _buildSubscriptionCard(
      SubscriptionPlan plan, SubscriptionStatus currentStatus, {required String topLabel}) {
    final isCurrentPlan = currentStatus.tier == plan.id && currentStatus.isActive;
    final disableSubscribe = currentStatus.isActive && currentStatus.tier != 'free';
    final borderColor = isCurrentPlan
        ? const Color.fromARGB(255, 130, 217, 255)
        : const Color.fromARGB(255, 203, 130, 255);
    final periodLabel = plan.period.toLowerCase().contains('year') ? 'per year' : 'per month';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.purple950,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.purple800,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Text(
                isCurrentPlan ? 'Current Plan' : topLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            // Middle: price
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '\$${plan.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    periodLabel,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Bottom: subscribe button
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (disableSubscribe || _loading) ? null : () => _subscribe(plan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isCurrentPlan ? 'Active' : 'Subscribe',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildCreditPacksSection(SubscriptionStatus status) {
    final totalCredits = status.totalCredits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.white24, thickness: 1),
        const SizedBox(height: 16),
        Row(
          children: const [
            Icon(Icons.bolt, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text(
              'One-Time Credits',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          // 'For occasional users. Credits allow you to analyze dreams without a subscription. Credits never expire.',
          'For occasional users. Credits never expire.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          '•  1 credit per dream  •  4 credits per image\nYou currently have $totalCredits credit${totalCredits == 1 ? '' : 's'} remaining ',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_creditPacks.isNotEmpty) _buildCreditPackRow(
          packs: _creditPacks,
          isPro: status.isActive && status.tier != 'free',
        ),
      ],
    );
  }

  Widget _buildCreditPackRow({required List<CreditPack> packs, required bool isPro}) {
    // Find the highest per-credit cost (the base/no-discount pack)
    final baseRate = packs.fold(0.0, (prev, p) {
      final rate = p.priceUsd / p.credits;
      return rate > prev ? rate : prev;
    });
    final midIndex = packs.length ~/ 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int i = 0; i < packs.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            flex: i == midIndex ? 5 : 4,
            child: SizedBox(
              height: i == midIndex ? 176 : 158,
              child: _buildCreditPackCard(
                packs[i],
                isPro: isPro,
                baseRate: baseRate,
                isPopular: i == midIndex,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCreditPackCard(CreditPack pack, {bool isPro = false, double baseRate = 0, bool isPopular = false}) {
    final ratePerCredit = pack.credits > 0 ? pack.priceUsd / pack.credits : 0.0;
    final isBase = baseRate <= 0 || (ratePerCredit - baseRate).abs() < 0.001;
    final savingsPct = isBase ? 0 : ((baseRate - ratePerCredit) / baseRate * 100).round();
    final topLabel = isPopular ? 'Most Popular' : (isBase ? 'Starter' : 'Save $savingsPct%');
    final price = _storeProducts[pack.productId]?.price ?? '\$${pack.priceUsd.toStringAsFixed(2)}';
    final borderWidth = isPopular ? 2.5 : 1.5;
    final borderAlpha = isPopular ? 1.0 : 0.6;
    final shadowAlpha = isPopular ? 0.5 : 0.3;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.purple950,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFB300).withValues(alpha: borderAlpha),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: shadowAlpha),
            blurRadius: isPopular ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top: amber banner with savings label
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFFFFB300),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Text(
                topLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            // Middle: credit count
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${pack.credits}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'credits',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Bottom: price button
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_loading || isPro) ? null : () => _buyCredits(pack),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB300),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    price,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Future<void> _buyCredits(CreditPack pack) async {
    final pd = _storeProducts[pack.productId];
    if (pd == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product not available. Please try again later.')),
      );
      return;
    }
    await InAppPurchase.instance.buyConsumable(purchaseParam: PurchaseParam(productDetails: pd));
  }

  // Build the current subscription status card
  Widget _buildCurrentSubscription(SubscriptionStatus status) {
    final bool isActive = status.isActive && status.tier != 'free';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.purple900
            : Colors.grey.shade800, // current subscription card color
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color.fromARGB(255, 130, 217, 255), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 130, 217, 255)
                .withValues(alpha: 0.7), // Shadow color with opacity
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isActive ? Icons.star : Icons.star_border,
                color: isActive ? Colors.amber : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                status.tier.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isActive
                ? 'Your subscription is active${status.expiryDate != null ? ' until ${DateFormat('MMM d, y').format(status.expiryDate!)}' : ''}'
                : 'You are currently on the free plan',
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontSize: 12,
            ),
          ),
          if (isActive) ...[
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text(
                //   status.autoRenew ? 'Auto-renews' : 'Does not auto-renew',
                //   style: TextStyle(
                //     color: status.autoRenew
                //         ? Colors.green.shade300
                //         : Colors.orange.shade300,
                //     fontSize: 14,
                //   ),
                // ),
                const SizedBox(height: 8),
                const Text(
                  'To change or cancel your subscription, manage it from the App Store / Google Play subscriptions page.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
