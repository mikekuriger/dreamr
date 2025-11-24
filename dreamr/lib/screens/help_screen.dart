// screens/help_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpScreen extends StatelessWidget {
  final VoidCallback? onDone;
  
  const HelpScreen({super.key, this.onDone});

  // Helper method to open email app
  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@dreamr.app',
      queryParameters: {
        'subject': 'Help with Dreamr App',
      },
    );
    
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      debugPrint('Could not launch email app');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Dreamr ✨ Help",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "Learn how to use Dreamr ✨ features",
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
            onDone?.call();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Getting Started Section
            _buildSection(
              title: 'Getting Started',
              icon: Icons.start,
              content: 'Dreamr ✨ is your personal dream analysis and journal app. Record your dreams and get personalized interpretations, along with generated images that capture the essence of your dreams.',
            ),
            
            // Dream Analysis Section
            _buildSection(
              title: 'Dream Analysis',
              icon: Icons.psychology,
              content: 'To analyze a dream:\n\n'
                '• Tap the "Add Dream" button in the navigation bar\n'
                '• Describe your dream in detail (characters, settings, emotions, events)\n'
                '• Use the microphone button to record your dream vocally\n'
                '• Tap "Analyze my dream" to get your personalized interpretation\n'
                '• Wait while the AI generates an image based on your dream\n\n'
                'Free users have limited dream analyses per week. Upgrade to Pro for unlimited analyses.',
            ),
            
            // Dream Journal Section
            _buildSection(
              title: 'Dream Journal',
              icon: Icons.auto_stories_rounded,
              content: 'Your dream journal stores all your analyzed dreams:\n\n'
                '• Access it through the "Journal" tab in the navigation bar\n'
                '• View your dreams chronologically\n'
                '• Tap on any entry to see the full analysis and image\n'
                '• Swipe down to refresh your journal with new entries',
            ),
            
            // Dream Gallery Section
            _buildSection(
              title: 'Dream Gallery',
              icon: Icons.photo_library_rounded,
              content: 'View all your dream images in one place:\n\n'
                '• Access through the "Gallery" tab in the navigation bar\n'
                '• Tap on an image to view it in full screen\n'
                '• Share images with friends directly from the gallery',
            ),
            
            // Life Events Section
            _buildSection(
              title: 'Life Events',
              icon: Icons.favorite,
              content: 'Track important life events that might influence your dreams:\n\n'
                '• Access through the hamburger menu → Life Events\n'
                '• Add significant events like travel, stress, medication, etc.\n'
                '• These events will be considered in your dream analyses\n'
                '• Helps identify patterns in your dream content',
            ),
            
            // Managing Your Account Section
            _buildSection(
              title: 'Managing Your Account',
              icon: Icons.manage_accounts,
              content: 'Access account profile and settings through the hamburger menu:\n\n'
                '• View and edit your profile information\n'
                '• Manage your subscription\n'
                '• Enable or disable features\n'
                '• Update your password\n'
                '• Log out of your account',
            ),
            
            // Dream Credits & Subscriptions Section
            _buildSection(
              title: 'Credits & Subscriptions',
              icon: Icons.stars,
              content: 'Understanding your dream credits:\n\n'
                '• Free users get 2 dream analyses per week\n'
                '• Pro subscribers get unlimited dream analyses\n'
                '• Upgrade through the hamburger menu → Subscription\n',
            ),
            
            // Contact Section
            _buildSection(
              title: 'Contact Support',
              icon: Icons.contact_support,
              content: 'Need help with Dreamr? Contact us!\n\n'
                '• Email: zentha.labs@gmail.com\n'
                '• Please include your email address and a detailed description of any issues\n'
                '• I do my best to respond right away, or within 24 hours',
              hasButton: true,
              buttonText: 'Email Support',
              onButtonPressed: _launchEmail,
            ),
            
            // Version Information
            Container(
              margin: const EdgeInsets.only(top: 30, bottom: 40),
              width: double.infinity,
              alignment: Alignment.center,
              child: const Text(
                'Dreamr ✨ v1.0.2\n© 2025 Michael Kuriger',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black26,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper method to build each section
  Widget _buildSection({
    required String title,
    required IconData icon,
    required String content,
    bool hasButton = false,
    String buttonText = '',
    VoidCallback? onButtonPressed,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.purple900,
        borderRadius: BorderRadius.circular(12),
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
          // Section header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.purple800,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Section content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                
                if (hasButton) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onButtonPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        buttonText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}