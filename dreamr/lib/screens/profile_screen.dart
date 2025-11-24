// screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/state/subscription_model.dart';

class ProfileScreen extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  final VoidCallback? onDone;
  const ProfileScreen({super.key, required this.refreshTrigger, this.onDone});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  String? _email;
  String? _firstName;
  String? _gender;
  DateTime? _birthdate;
  String _subscriptionTier = 'free';

  // Password change fields
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _currentPasswordVisible = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _changingPassword = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    
    // Refresh subscription data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SubscriptionModel>(context, listen: false).refresh();
    });
  }
  
  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService.getProfile();
      setState(() {
        _email = data['email'];
        _firstName = data['first_name'];
        _gender = data['gender'];
        _birthdate = (data['birthdate'] != null && data['birthdate'] != '')
            ? DateTime.parse(data['birthdate'])
            : null;
        _subscriptionTier = data['subscription_tier'] ?? 'free';
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load profile: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    try {
      await ApiService.setProfile(
        firstName: _firstName ?? '',
        gender: _gender ?? '',
        birthdate: _birthdate,
      );

      widget.refreshTrigger.value++;
      widget.onDone?.call();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Profile saved')),
      );
    } catch (e) {
      debugPrint('❌ Failed to save profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Failed to save profile')),
      );
    }
  }

  // to make the profile page pretty
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white54),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
    );
  }

  Widget _buildLoadingWidget() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildPasswordChangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.lock_outline,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'Change Password',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_changingPassword)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        
        Form(
          key: _passwordFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Current Password
              TextFormField(
                controller: _currentPasswordController,
                obscureText: !_currentPasswordVisible,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  labelStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _currentPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _currentPasswordVisible = !_currentPasswordVisible;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // New Password
              TextFormField(
                controller: _newPasswordController,
                obscureText: !_newPasswordVisible,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'New Password',
                  labelStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _newPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _newPasswordVisible = !_newPasswordVisible;
                      });
                    },
                  ),
                ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a new password';
                }
                if (value.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                // Check for additional complexity requirements
                if (!value.contains(RegExp(r'[A-Z]'))) {
                  return 'Password must contain at least one uppercase letter';
                }
                if (!value.contains(RegExp(r'[0-9]'))) {
                  return 'Password must contain at least one number';
                }
                return null;
              },
              ),
              const SizedBox(height: 16),
              
              // Confirm Password
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: !_confirmPasswordVisible,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  labelStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _confirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _confirmPasswordVisible = !_confirmPasswordVisible;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your new password';
                  }
                  if (value != _newPasswordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // Change Password Button
              ElevatedButton(
                onPressed: _changingPassword ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  "Change Password",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Future<void> _changePassword() async {
    // Validate form
    if (_passwordFormKey.currentState?.validate() != true) {
      return;
    }
    
    setState(() {
      _changingPassword = true;
    });
    
    try {
      // Enhanced debug logging
      debugPrint('🔒 Attempting password change:');
      debugPrint('- Current password length: ${_currentPasswordController.text.length}');
      debugPrint('- New password length: ${_newPasswordController.text.length}');
      debugPrint('- New password has uppercase: ${_newPasswordController.text.contains(RegExp(r'[A-Z]'))}');
      debugPrint('- New password has number: ${_newPasswordController.text.contains(RegExp(r'[0-9]'))}');
      debugPrint('- New password has special char: ${_newPasswordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))}');
      
      final currentPwTrimmed = _currentPasswordController.text.trim();
      final newPwTrimmed = _newPasswordController.text.trim();
      
      // More validation to ensure request will succeed
      if (currentPwTrimmed.isEmpty) {
        throw Exception('Current password cannot be empty');
      }
      
      if (newPwTrimmed.length < 8) {
        throw Exception('New password must be at least 8 characters long');
      }
      
      // Make the API call
      await ApiService.changePassword(
        currentPassword: currentPwTrimmed,
        newPassword: newPwTrimmed,
      );
      
      // Clear password fields on success
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      
      if (!mounted) return;
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Password changed successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to change password: $e');
      
      if (!mounted) return;
      
      String errorMessage = 'Failed to change password';
      
      // More specific error messages
      if (e.toString().contains('400')) {
        errorMessage = 'Your current password may be incorrect or your new password doesn\'t meet the requirements (minimum 8 characters with at least one uppercase letter and one number)';
      } else if (e.toString().contains('401') || e.toString().contains('403')) {
        errorMessage = 'You need to be logged in to change your password';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Connection timed out. Please try again';
      } else if (e.toString().contains('empty') || e.toString().contains('at least 8 characters')) {
        errorMessage = e.toString().contains('Exception:') 
            ? e.toString().split('Exception:')[1].trim()
            : e.toString();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $errorMessage'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _changingPassword = false;
        });
      }
    }
  }

  Widget _buildProfileContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Back button and Email display
          Row(
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => widget.onDone?.call(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _email ?? 'unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // Empty space to balance the back button
              const SizedBox(width: 24),
            ],
          ),
          const SizedBox(height: 20),

          // Subscription section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.purple950,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<SubscriptionModel>(
                  builder: (context, subscriptionModel, _) {
                    final tier = subscriptionModel.status.tier;
                    final isFree = tier == 'free';
                    return Row(
                      children: [
                        Icon(
                          isFree ? Icons.star_border : Icons.star,
                          color: isFree ? Colors.grey : Colors.amber,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Subscription: ${tier.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  }
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/subscription');
                    },
                    icon: const Icon(Icons.card_membership, size: 18),
                    label: const Text('Manage Subscription'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Form Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.purple950,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // First name
                  TextFormField(
                    initialValue: _firstName,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('First Name'),
                    onChanged: (val) => _firstName = val,
                  ),
                  const SizedBox(height: 20),

                  // Gender
                  DropdownButtonFormField<String>(
                    initialValue: _gender?.isNotEmpty == true ? _gender : null,
                    decoration: _inputDecoration('Gender'),
                    dropdownColor: AppColors.purple950,
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(
                        value: 'male',
                        child: Text("Male"),
                      ),
                      DropdownMenuItem(
                        value: 'female',
                        child: Text("Female"),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text("Prefer not to answer"),
                      ),
                    ],
                    onChanged: (val) => _gender = val,
                  ),
                  const SizedBox(height: 20),

                  // Birthdate
                  InkWell(
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _birthdate ?? DateTime(2000),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Colors.deepPurple,
                                surface: Colors.black87,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) setState(() => _birthdate = picked);
                    },
                    child: InputDecorator(
                      decoration: _inputDecoration('Birthdate'),
                      child: Text(
                        _birthdate == null
                            ? 'Tap to select'
                            : _birthdate!.toLocal().toString().split(' ')[0],
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),

                  // Buttons
                  Row(
                    children: [
                      // Cancel button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            widget.onDone?.call();
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Save button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurpleAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            "Save",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Password Change Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.purple950,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _buildPasswordChangeSection(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.purple900,
      body: SafeArea(
        bottom: true,
        child: _loading ? _buildLoadingWidget() : _buildProfileContent(),
      ),
    );
  }
}