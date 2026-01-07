// screens/subscription_screen.dart
// import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/models/subscription.dart';
import 'package:dreamr/state/subscription_model.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class SubscriptionScreen extends StatefulWidget {
  final VoidCallback? onDone;

  const SubscriptionScreen({super.key, this.onDone});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with WidgetsBindingObserver {
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    // Start observing app lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Refresh subscription data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionModel>().refresh();
    });
  }

  @override
  void dispose() {
    // Stop observing lifecycle
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
  String _formatPrice(double price, String period) {
    final formatter = NumberFormat.currency(symbol: '\$');
    return '${formatter.format(price)}/${period.toLowerCase()}';
  }

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
      backgroundColor: AppColors.purple950,
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
              "Unlock all features with a premium plan",
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
                  // Keep the header/first card as-is
                  _buildCurrentSubscription(model.status),
                  const SizedBox(height: 12),

                  // Keep restore purchases
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

                  const SizedBox(height: 8),

                  if (featureCards.isNotEmpty) ...[
                    _buildProFeaturesSection(featureCards),
                    const SizedBox(height: 18),
                  ],

                  // const Text(
                  //   'Choose your plan',
                  //   style: TextStyle(
                  //     color: Colors.white,
                  //     fontSize: 20,
                  //     fontWeight: FontWeight.bold,
                  //   ),
                  // ),
                  // const SizedBox(height: 12),

                  if (proYearly != null)
                    _buildPlanOptionCard(proYearly, model.status),

                  if (proMonthly != null)
                    _buildPlanOptionCard(proMonthly, model.status),

                  if (proYearly == null && proMonthly == null)
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
      case 'unlimited_images':
        return Icons.auto_awesome;
      case 'premium_themes':
        return Icons.palette;
      case 'cloud_sync':
        return Icons.cloud_done;
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
            Icon(Icons.workspace_premium, color: Colors.amber, size: 22),
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
                    color: AppColors.purple850,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color.fromARGB(140, 130, 217, 255),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    _iconForFeatureKey(c.key),
                    color: const Color.fromARGB(255, 130, 217, 255),
                    size: 18,
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

  Widget _buildPlanOptionCard(
      SubscriptionPlan? plan, SubscriptionStatus currentStatus) {
    if (plan == null) return const SizedBox.shrink();

    final isCurrentPlan = currentStatus.tier == plan.id && currentStatus.isActive;
    final disableSubscribe = currentStatus.isActive && currentStatus.tier != 'free';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.purple950,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentPlan
              ? const Color.fromARGB(255, 130, 217, 255)
              : const Color.fromARGB(255, 203, 130, 255),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 130, 217, 255)
                .withValues(alpha: 0.7),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCurrentPlan ? AppColors.purple850 : AppColors.purple800,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatPrice(plan.price, plan.period),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: disableSubscribe || _loading
                        ? null
                        : () => _subscribe(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: Colors.grey.shade700,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isCurrentPlan ? 'Current Plan' : 'Subscribe',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
