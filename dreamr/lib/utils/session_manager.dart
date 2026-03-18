// utils/session_manager.dart

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/services/api_service.dart';

Future<void> performLogout(BuildContext context) async {
  // kill Google session
  final google = GoogleSignIn(scopes: ['email','profile']);
  try { await google.signOut(); } catch (_) {}
  try { await google.disconnect(); } catch (_) {}

  // kill Facebook session
  try { await FacebookAuth.instance.logOut(); } catch (_) {}

  // kill server session + cookies
  await ApiService.logout();

  // nuke local flags
  const storage = FlutterSecureStorage();
  await storage.delete(key: 'login_method');
  await storage.delete(key: 'email');
  await storage.delete(key: 'password');

  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('loggedIn');
  await prefs.remove('userId');

  if (!context.mounted) return;
  Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
}
