// screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dreamr/services/api_service.dart';
// import 'package:dreamr/widgets/main_scaffold.dart';
import 'package:dreamr/screens/welcome_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dreamr/constants.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/state/subscription_model.dart';
import 'package:dreamr/services/notification_service.dart';
import 'package:dreamr/services/prefetch_service.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _storage = const FlutterSecureStorage();
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: kWebClientId,
    );
    _attemptAutoLogin();
  }

  void _attemptAutoLogin() async {
    try {
      final loginMethod = await _storage.read(key: 'login_method');

      if (loginMethod == 'google') {
        final token = await _storage.read(key: 'google_token');
        if (token != null) {
          try {
            // Try to sign in silently with Google
            final googleUser = await _googleSignIn.signInSilently();
            if (googleUser != null) {
              final googleAuth = await googleUser.authentication;
              final idToken = googleAuth.idToken;
              
              if (idToken != null) {
                // Authenticate with backend
                await ApiService.googleLogin(idToken);
                
                // Update stored token
                await _storage.write(key: 'google_token', value: idToken);
                
                // Initialize subscription state before navigating
                await _initializeSubscription();
                PrefetchService.warmUp();

                if (!mounted) return;
                await navigateToPostLoginDestination(context);
                return;
              }
            }
          } catch (e) {
            debugPrint('❌ Google auto-login failed: $e');
            // Fall through to next login method
          }
        }
      }

      final email = await _storage.read(key: 'email');
      final password = await _storage.read(key: 'password');
      if (email != null && password != null) {
        try {
          await ApiService.login(email, password);
          
          // Initialize subscription state before navigating
          await _initializeSubscription();
          PrefetchService.warmUp();

          // schedule notifications on successful login
          await _rescheduleNotifications();
          
          if (!mounted) return;
          await navigateToPostLoginDestination(context);
          return;
        } catch (e) {
          // Login failed, fall through to login screen
        }
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      // 🔥 this catches BAD_DECRYPT or any other secure storage read failure
      debugPrint('❌ Secure storage error: $e');
      await _storage.deleteAll(); // wipe corrupted entries
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  // Initialize subscription state
  Future<void> _initializeSubscription() async {
    try {
      // Get the subscription model from the provider
      final subscriptionModel = Provider.of<SubscriptionModel>(context, listen: false);
      
      // Initialize and refresh subscription data
      await subscriptionModel.refresh();
    } catch (e) {
      debugPrint('❌ Failed to initialize subscription: $e');
      // Continue anyway - subscription will be initialized later
    }
  }

  // Reschedule notifications on login
  Future<void> _rescheduleNotifications() async {
    try {
      // Try to personalize with profile first name
      final profile = await ApiService.getProfile(); // should return a Map
      final String? first = (() {
        final v = profile['first_name']?.toString().trim();
        return (v != null && v.isNotEmpty) ? v : null;
      })();

      // If you have usage stats, plug them here. Otherwise safe fallbacks:
      final int? streakDays = null;
      final DateTime? lastLogUtc = DateTime.now().toUtc();

      await NotificationService().rescheduleAllOnLogin(
        displayName: first,
        streakDays: streakDays,
        lastLogUtc: lastLogUtc,
        dailyTime: const TimeOfDay(hour: 8, minute: 0),
        weeklyWeekday: DateTime.sunday,
      );
    } catch (e) {
      // Fallback schedule if profile fetch fails
      await NotificationService().rescheduleAllOnLogin(
        displayName: null,
        streakDays: null,
        lastLogUtc: DateTime.now().toUtc(),
        dailyTime: const TimeOfDay(hour: 8, minute: 0),
        weeklyWeekday: DateTime.sunday,
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
