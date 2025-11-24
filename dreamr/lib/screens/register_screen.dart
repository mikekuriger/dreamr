// screens/register_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dreamr/constants.dart';
import 'package:dreamr/widgets/main_scaffold.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState(); 
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = '';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: kWebClientId,
  );
  
  Future<void> _handleGoogleLogin() async {
    try {
      final account = await _googleSignIn.signIn();

      if (account == null) {
        setState(() {
          _errorMessage = "Registration cancelled";
        });
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        setState(() {
          _errorMessage = "Google authentication failed";
        });
        return;
      }

      await ApiService.googleLogin(idToken);
      if (!mounted) return; 
      // After a successful Google "registration", treat it like login and
      // enter the full app shell (header + nav) via MainScaffold.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScaffold(initialIndex: 0)),
      );
    } catch (e) {
      setState(() {
        _errorMessage = "Google login failed";
      });
    }
  }

  // Validate inputs
  String? validateRegistration(String name, String email, String password) {
    final emailRegex = RegExp(r"^[^@]+@[^@]+\.[^@]+$");

    if (name.isEmpty || name.length > 20) {
      return "Name must be 1–20 characters";
    }

    if (!emailRegex.hasMatch(email)) {
      return "Invalid email address";
    }

    if (password.length < 8) {
      return "Password must be at least 8 characters";
    }

    return null;
  }

  // Handle Registration
  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();       // makes keyboard go away

    final firstName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

  // Client-side validation first
    final error = validateRegistration(firstName, email, password);
    if (error != null) {
      setState(() {
        _errorMessage = error;
      });
      return;
    }

    setState(() {
      _errorMessage = '';
    });

  // Register user
    try {
      final result = await ApiService.register(firstName, email, password);
      if (!mounted) return;

  // // Clear fields
  //     _nameController.clear();
  //     _emailController.clear();
  //     _passwordController.clear();

  // Show confirmation
      setState(() {
        // _errorMessage = "✅ Check your email to confirm your Dreamr✨ account.";
        _errorMessage = result;
      });

  //  Snacky snack
      if (result.startsWith("✅")) {

      // Clear fields
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result),
            duration: const Duration(seconds: 5),
          ),
        );

        // User is auto-logged-in by the backend; send them into the full
        // main scaffold so they get header + hamburger + bottom navigation.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScaffold(initialIndex: 0)),
        );
      }

    } catch (e) {
      setState(() {
        _errorMessage = "❌ ${e.toString().replaceFirst('Exception: ', '')}";
      });
    } finally {
      if (mounted) {
        setState(() {
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.purple950, // use your darkest shade
        elevation: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Welcome to Dreamr ✨",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "Your personal AI-powered dream analysis",
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Color(0xFFD1B2FF), // soft lavender/purple for subtext
              ),
            ),
          ],
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "First Name",
                  labelStyle: TextStyle(color: Colors.white), // Label
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Email",
                  labelStyle: TextStyle(color: Colors.white), // Label
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                obscureText: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Password",
                  labelStyle: TextStyle(color: Colors.white), // Label
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),

              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                ),

      //Register button
              Center(
                child: SizedBox(
                  width: 160, // desired width
                  height: 40, // optional height
                  child: ElevatedButton(
                    onPressed: _handleRegister,
                    child: const Text("Register"),
                  ),
                ),
              ),

      // Back to Login
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white), // Default style
                    children: const [
                      TextSpan(
                        text: "Already have an account? ",
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                      TextSpan(
                        text: "Log in",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

      // Register via Google
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _handleGoogleLogin,
                child: SvgPicture.asset(
                  'assets/images/google_logo.svg',
                  width: 40,
                  height: 40,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

