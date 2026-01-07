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
      path: 'zentha.labs@gmail.com',
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
        // back button
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
                '• Choose your preferred dream interpreter personality\n'
                '• Tap "Analyze my dream" to get your personalized interpretation\n'
                '• Wait while the AI generates an image based on your dream\n\n'
                'Free users have limited dream analyses per week. Upgrade to Pro for unlimited analyses.',
            ),
            
            // Dream Interpreters Section
            _buildSection(
              title: 'Dream Interpreters',
              icon: Icons.person,
              content: 'Choose from different AI personalities to analyze your dreams:\n\n'
                '• Access through the "Interpreters" tab in the navigation bar\n'
                '• Each interpreter brings a unique perspective and style\n'
                '• Browse by categories like Grounded, Supportive, Analytical, etc.\n'
                '• Free users can access basic interpreters\n'
                '• Pro subscribers unlock additional specialized personalities\n'
                '• Your choice affects the tone and depth of dream interpretations',
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

            // Image Styles Section
            _buildSection(
              title: 'Image Styles',
              icon: Icons.palette_rounded,
              content: 'Customize the visual look of your dream images:\n\n'
                '• Open the hamburger menu → Image Styles\n'
                '• Choose Dreamr✨ decides to let the AI match a style to each dream’s tone\n'
                '• Or pick a fixed preset to keep all future dream images visually consistent\n'
                '• Browse styles grouped by vibe (Peaceful, Epic, Nightmarish, etc.)\n'
                '• Preview example thumbnails before selecting (cached on-device for speed)\n'
                '• Tap the selected style again to clear it and go back to AI selection\n'
                '• Your choice is saved automatically and used for newly generated images',
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
                '• Log out of your account\n'
                '• Delete your account',
            ),
            
            // Dream Credits & Subscriptions Section
            _buildSection(
              title: 'Credits & Subscriptions',
              icon: Icons.stars,
              content: 'Understanding your dream credits:\n\n'
                '• Free users get 2 dream analyses per week\n'
                '• Pro subscribers get unlimited dream analyses\n'
                '• Pro subscribers also unlock additional dream interpreter personalities\n'
                '• Upgrade through the hamburger menu → Subscription\n',
            ),
            
            // Contact Section
            _buildSection(
              title: 'Contact Support',
              icon: Icons.contact_support,
              content: 'Need help with Dreamr? Contact us!\n\n'
                '• Email: zentha.labs@gmail.com\n'
                '• Please include your email address and a detailed description of any issues\n'
                '• You will normally get a response within 24 hours',
              hasButton: true,
              buttonText: 'Email Support',
              onButtonPressed: _launchEmail,
            ),
            
            // Version Information and EULA
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 30), // distance from screen bottom
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Dreamr ✨ v1.0.13+18\n© 2025 Michael Kuriger',          // version number
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color.fromARGB(200, 122, 209, 255),
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 0),              // space between version and EULA
                    
                    Row(
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
                    )
                  ],
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
      margin: const EdgeInsets.only(bottom: 16),   // Spacing between sections
      decoration: BoxDecoration(
        color: AppColors.purple950,              // Dark purple background
        borderRadius: BorderRadius.circular(12),   // Bottom corners rounded
        border: Border.all(
          color: const Color(0xFF82D9FF), // pick your border color
          width: 1.0,                     // border width
        ),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 130, 217, 255).withValues(alpha: 0.5), // Shadow color with opacity
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
            padding: const EdgeInsets.all(16),    // Header thickness
            decoration: BoxDecoration(
              color: AppColors.purple800,       // lighter purple for header
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),     // Top corners rounded
                topRight: Radius.circular(12),    // Top corners rounded
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white,  // Icon color in headers
                  size: 24,
                ),
                const SizedBox(width: 12),  // Spacing between icon and title
                Text(
                  title,
                  style: const TextStyle(
                    color: Color.fromARGB(255, 255, 255, 255),  // Title color in headers
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Section content
          Padding(
            padding: const EdgeInsets.all(16),  // 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content,
                  style: const TextStyle(
                    color: Colors.white,   // Content text color
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
                        backgroundColor: const Color.fromARGB(255, 255, 96, 96),  // Red button color
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
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