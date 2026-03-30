// screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:dreamr/widgets/main_scaffold.dart';
import 'package:dreamr/screens/welcome_screen.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/constants.dart';
import 'package:google_sign_in/google_sign_in.dart';
// import 'package:url_launcher/url_launcher.dart';
import 'package:dreamr/screens/privacy_policy_screen.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:dreamr/services/prefetch_service.dart';
import 'dart:io' show Platform;


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- controllers / state ---
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _pwCtl = TextEditingController();
  final _secure = const FlutterSecureStorage();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: kWebClientId,
  );

  @override
  void dispose() {
    _emailCtl.dispose();
    _pwCtl.dispose();
    super.dispose();
  }

  // ===== Email login =====
  Future<void> _handleEmailLogin() async {
    if (_loading) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final email = _emailCtl.text.trim();
      final password = _pwCtl.text;

      final user = await ApiService.login(email, password);

      await _secure.write(key: 'login_method', value: 'password');
      await _secure.write(key: 'email', value: email);
      await _secure.write(key: 'password', value: password);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      if (user['id'] is int) {
        await prefs.setInt('userId', user['id']);
      }

      PrefetchService.warmUp();
      if (!mounted) return;
      // Navigate to post-login destination (welcome tour or main scaffold)
      await navigateToPostLoginDestination(context);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // // ===== Open Privacy Policy =====
  // Future<void> _openPrivacyPolicy() async {
  //   const url = 'https://dreamr-us-west-01.zentha.me/static/privacy.html';
  //   final uri = Uri.parse(url);

  //   if (await canLaunchUrl(uri)) {
  //     await launchUrl(uri, mode: LaunchMode.externalApplication);
  //   } else {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('Unable to open Privacy Policy'),
  //         behavior: SnackBarBehavior.floating,
  //       ),
  //     );
  //   }
  // }

  // ===== Google login =====
  Future<void> _handleGoogleLogin() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in flow
        setState(() => _loading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final token = googleAuth.idToken;

      if (token == null) {
        throw Exception('Failed to get ID token from Google');
      }

      // Send token to backend for verification and login
      final user = await ApiService.googleLogin(token);

      // Store login method and token
      await _secure.write(key: 'login_method', value: 'google');
      await _secure.write(key: 'google_token', value: token);

      // Set login flag
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      if (user['id'] is int) {
        await prefs.setInt('userId', user['id']);
      }

      PrefetchService.warmUp();
      if (!mounted) return;
      // Navigate to post-login destination (welcome tour or main scaffold)
      await navigateToPostLoginDestination(context);
    } catch (e) {
      // Handle sign-in errors
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }

      // Sign out to clean up any partial sign-in state
      _googleSignIn.signOut();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== Facebook login =====
  Future<void> _handleFacebookLogin() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
        loginTracking: LoginTracking.enabled,
      );

      if (result.status == LoginStatus.cancelled) {
        setState(() => _loading = false);
        return;
      }
      if (result.status != LoginStatus.success) {
        throw Exception(result.message ?? 'Facebook login failed');
      }

      final accessToken = result.accessToken?.tokenString;
      if (accessToken == null) throw Exception('Failed to get Facebook access token');

      final user = await ApiService.facebookLogin(accessToken);

      await _secure.write(key: 'login_method', value: 'facebook');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      if (user['id'] is int) {
        await prefs.setInt('userId', user['id']);
      }

      if (!mounted) return;
      await navigateToPostLoginDestination(context);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
      await FacebookAuth.instance.logOut();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== Apple login =====
  Future<void> _handleAppleSignIn(AuthorizationCredentialAppleID credential) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final identityToken = credential.identityToken;
      final userIdentifier = credential.userIdentifier;

      if (identityToken == null) {
        throw Exception('Failed to get identity token from Apple');
      }
      if (userIdentifier == null) {
        throw Exception('Failed to get Apple user identifier');
      }

      // Build a simple full name if Apple gave you one (only on first sign-in)
      String? fullName;
      if (credential.givenName != null || credential.familyName != null) {
        fullName = [
          credential.givenName ?? '',
          credential.familyName ?? '',
        ].join(' ').trim();
      }

      // Call backend; it just returns {success: true} or error
      await ApiService.appleLogin(
        identityToken: identityToken,
        authorizationCode: credential.authorizationCode,
        userIdentifier: userIdentifier,
        email: credential.email,
        fullName: fullName,
      );

      // Persist login method + Apple user id
      await _secure.write(key: 'login_method', value: 'apple');
      await _secure.write(key: 'apple_user_id', value: credential.userIdentifier);

      // Mark logged in (same pattern as Google; no userId here)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);

      PrefetchService.warmUp();
      if (!mounted) return;
      // Navigate to post-login destination (welcome tour or main scaffold)
      await navigateToPostLoginDestination(context);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== Validators =====
  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email required';
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s)) return 'Invalid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').isEmpty) return 'Password required';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final subtle = const Color(0xFFD1B2FF);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.purple950,
        elevation: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Welcome to Dreamr ✨",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            SizedBox(height: 2),
            Text(
              "Your personal AI-powered dream analysis",
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFD1B2FF)),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),

              // ===== Login form (prominent) =====
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailCtl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      validator: _validateEmail,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pwCtl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleEmailLogin(),
                      style: const TextStyle(color: Colors.white),
                      validator: _validatePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Colors.white),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : () => Navigator.pushNamed(context, '/forgot-password'),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            decoration: TextDecoration.underline,
                            color: Color(0xFFD1B2FF)
                            ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                        ),
                        onPressed: _loading ? null : _handleEmailLogin,
                        child: _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text("Login"),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ===== Divider: or continue with =====
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.white24)),
                  const SizedBox(width: 8),
                  Text('or', style: TextStyle(color: subtle)),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),

              const SizedBox(height: 16),

              // ===== Social logins =====
              Center(
                child: Column(
                  children: [
                    // Google
                    GestureDetector(
                      onTap: _loading ? null : _handleGoogleLogin,
                      child: SvgPicture.asset(
                        'assets/images/google_logo.svg',
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Facebook (Android only — FB classic login is deprecated on iOS)
                    if (Platform.isAndroid) ...[
                      SizedBox(
                        width: 225,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _handleFacebookLogin,
                          icon: const Icon(Icons.facebook, color: Colors.white),
                          label: const Text(
                            'Continue with Facebook',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1877F2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Apple (iOS only)
                    if (Platform.isIOS) 
                      Center(
                        child: SizedBox(
                          height: 48,
                          width: 225, 
                          child: Builder(
                            builder: (context) {
                              // We scale text up globally on iPad. The Apple button's internal
                              // typography doesn't look great when scaled, so we undo ONLY the
                              // extra iPad multiplier here.
                              final mq = MediaQuery.of(context);
                              final isIpadLike = mq.size.shortestSide >= 600;

                              final effectiveMq = isIpadLike
                                  ? mq.copyWith(textScaleFactor: mq.textScaleFactor / 1.25)
                                  : mq;

                              return MediaQuery(
                                data: effectiveMq,
                                child: SignInWithAppleButton(
                                  onPressed: _loading
                                      ? null
                                      : () async {
                                          try {
                                            final credential =
                                                await SignInWithApple.getAppleIDCredential(
                                              scopes: [
                                                AppleIDAuthorizationScopes.email,
                                                AppleIDAuthorizationScopes.fullName,
                                              ],
                                            );

                                            if (!mounted) return; // <<< mounted check

                                            await _handleAppleSignIn(credential);
                                          } catch (e, st) {
                                            debugPrint('Apple sign-in failed: $e\n$st');

                                            if (!mounted) return; // <<< mounted check

                                            final msg =
                                                e.toString().replaceFirst('Exception: ', '');
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(msg),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                  style: SignInWithAppleButtonStyle.white,
                                  // style: SignInWithAppleButtonStyle.black,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ===== Register prompt (prominent) =====
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('New here?', style: TextStyle(color: Colors.white)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      child: const Text(
                        'Create account',
                        style: TextStyle(
                          decoration: TextDecoration.underline,
                          color: Color(0xFFD1B2FF)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 12),

              // Privacy Policy
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: Colors.white70,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
