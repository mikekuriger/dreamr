// screens/subscription_screen.dart
import 'dart:io';
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

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Refresh subscription data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionModel>().refresh();
    });
  }

  // Format currency based on price
  String _formatPrice(double price, String period) {
    final formatter = NumberFormat.currency(symbol: '\$');
    return '${formatter.format(price)}/${period.toLowerCase()}';
  }

  // Handle subscription purchase
  Future<void> _subscribe(SubscriptionPlan plan) async {
    // Log immediately when the user taps Subscribe so we know the button handler fired
    debugPrint('SUB UI: subscribe tapped for plan=${plan.id}');

    setState(() => _loading = true);
    
    try {
      final result = await context.read<SubscriptionModel>().subscribe(plan);
      
      if (result != null && result.containsKey('payment_url')) {
        final url = result['payment_url'] as String;
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open payment page')),
            );
          }
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Handle subscription cancellation
  Future<void> _cancelSubscription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
          'Are you sure you want to cancel your subscription? '
          'You will still have access until the end of your billing period.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      setState(() => _loading = true);
      
      try {
        final success = await context.read<SubscriptionModel>().cancelSubscription();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success 
                  ? 'Subscription cancelled successfully' 
                  : 'Failed to cancel subscription'
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.purple950,  // overall screen background color
      // backgroundColor: AppColors.purple900,  // overall screen background color
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
      body: Consumer<SubscriptionModel>(
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
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // Current subscription status
                  _buildCurrentSubscription(model.status),
                  
                  // Restore purchases button (iOS only)
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: model.loading ? null : () async {
                          final success = await model.restorePurchases();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success 
                                    ? 'Purchases restored successfully' 
                                    : 'Failed to restore purchases'
                                ),
                              ),
                            );
                          }
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
                  ],
                  
                  const SizedBox(height: 24),
                
                // Available plans
                const Text(
                  'Available Plans',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Plan cards (excluding free plans)
                ...model.plans
                    .where((plan) => plan.id != 'trial_5day')
                    .map((plan) => _buildPlanCard(plan, model.status)),
                
                // Show a message if no plans are available
                if (model.plans.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No subscription plans available at the moment.',
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
    );
  }

  // Build the current subscription status card
  Widget _buildCurrentSubscription(SubscriptionStatus status) {
    final bool isActive = status.isActive && status.tier != 'free';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? AppColors.purple800 : Colors.grey.shade800,  // current subscription card color
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
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
                'Current Plan: ${status.tier.toUpperCase()}',
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
              fontSize: 14,
            ),
          ),
          
          if (isActive) ...[
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  status.autoRenew ? 'Auto-renews' : 'Does not auto-renew',
                  style: TextStyle(
                    color: status.autoRenew ? Colors.green.shade300 : Colors.orange.shade300,
                    fontSize: 14,
                  ),
                ),
                
                ElevatedButton(
                  onPressed: _loading ? null : _cancelSubscription,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Build a subscription plan card
  Widget _buildPlanCard(SubscriptionPlan plan, SubscriptionStatus currentStatus) {
    final bool isCurrentPlan = currentStatus.tier == plan.id && currentStatus.isActive;
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isCurrentPlan ? const Color.fromARGB(255, 0, 0, 0) : AppColors.purple900,    // plan card color
        borderRadius: BorderRadius.circular(12),
        border: isCurrentPlan
            ? Border.all(color: Colors.amber, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCurrentPlan ? const Color.fromARGB(255, 196, 29, 0) : AppColors.purple800,   //plan header color
              // color: isCurrentPlan ? AppColors.purple800 : AppColors.purple850,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  plan.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
          
          // Plan details
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
                
                // Features list
                ...plan.features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
                
                const SizedBox(height: 16),
                
                // Subscribe button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan || _loading
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
}