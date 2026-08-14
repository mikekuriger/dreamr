// screens/splash_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/services/api_service.dart';
// import 'package:dreamr/widgets/main_scaffold.dart';
import 'package:dreamr/screens/welcome_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dreamr/constants.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/state/subscription_model.dart';
import 'package:dreamr/services/notification_service.dart';
import 'package:dreamr/services/prefetch_service.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';


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

  // Request ATT authorization on iOS before any login or ad network activity.
  // SKAdNetwork works without consent, but IDFA-based attribution requires it.
  Future<void> _requestTrackingIfNeeded() async {
    if (!Platform.isIOS) return;
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      // Brief delay so the splash UI is visible before the system dialog appears.
      await Future.delayed(const Duration(milliseconds: 300));
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }

  void _attemptAutoLogin() async {
    await _requestTrackingIfNeeded();
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasLoggedIn = prefs.getBool('loggedIn') ?? false;
      final loginMethod = await _storage.read(key: 'login_method');

      if (wasLoggedIn && loginMethod != null) {
        // We have a prior session — navigate immediately without blocking on network.
        // The persisted session cookie handles auth; re-validate silently in background.
        if (!mounted) return;
        await navigateToPostLoginDestination(context);
        _backgroundRefresh(loginMethod); // fire-and-forget
        return;
      }

      // No prior session — need a live login before we can proceed.
      if (loginMethod == 'google') {
        final token = await _storage.read(key: 'google_token');
        if (token != null) {
          try {
            final googleUser = await _googleSignIn.signInSilently();
            if (googleUser != null) {
              final googleAuth = await googleUser.authentication;
              final idToken = googleAuth.idToken;
              if (idToken != null) {
                await ApiService.googleLogin(idToken);
                await _storage.write(key: 'google_token', value: idToken);
                await _initializeSubscription();
                PrefetchService.warmUp();
                if (!mounted) return;
                await navigateToPostLoginDestination(context);
                return;
              }
            }
          } catch (e) {
            debugPrint('❌ Google auto-login failed: $e');
          }
        }
      }

      final email = await _storage.read(key: 'email');
      final password = await _storage.read(key: 'password');
      if (email != null && password != null) {
        try {
          await ApiService.login(email, password);
          await _initializeSubscription();
          PrefetchService.warmUp();
          await _rescheduleNotifications();
          if (!mounted) return;
          await navigateToPostLoginDestination(context);
          return;
        } catch (e) {
          // Login failed — fall through to login screen
        }
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint('❌ Secure storage error: $e');
      await _storage.deleteAll();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  /// Re-validates the server session and syncs data in the background.
  /// Called after navigating to the app when a prior session exists.
  /// Each step is isolated so a network failure in one doesn't block the others.
  Future<void> _backgroundRefresh(String loginMethod) async {
    // Step 1: try to re-validate the session (best-effort, offline failure is fine)
    try {
      if (loginMethod == 'google') {
        final googleUser = await _googleSignIn.signInSilently();
        if (googleUser != null) {
          final googleAuth = await googleUser.authentication;
          if (googleAuth.idToken != null) {
            await ApiService.googleLogin(googleAuth.idToken!);
            await _storage.write(key: 'google_token', value: googleAuth.idToken);
          }
        }
      } else if (loginMethod == 'password') {
        final email = await _storage.read(key: 'email');
        final password = await _storage.read(key: 'password');
        if (email != null && password != null) {
          await ApiService.login(email, password);
        }
      }
      // facebook/apple: persisted session cookie handles auth — no action needed
    } catch (e) {
      debugPrint('ℹ️ Session re-validation failed (offline?): $e');
    }

    // Step 2: refresh subscription — always runs, falls back to cache if offline
    try {
      await _initializeSubscription();
    } catch (e) {
      debugPrint('ℹ️ Subscription refresh failed: $e');
    }

    // Step 3: prefetch images and reschedule notifications
    try {
      PrefetchService.warmUp();
      await _rescheduleNotifications();
    } catch (e) {
      debugPrint('ℹ️ Prefetch/notifications failed: $e');
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
      final DateTime lastLogUtc = DateTime.now().toUtc();

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
