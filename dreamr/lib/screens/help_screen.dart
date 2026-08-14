// screens/help_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';


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
                '• Choose your preferred dream interpreter personality\n'
                '• Tap "Analyze my dream" to get your personalized interpretation\n'
                '• Pro users: a dream image is generated automatically\n'
                '• Free users: tap "Generate Dream Image" inside the analysis card to create one (uses 4 tokens)\n'
                '• Chat with the AI to explore your dream further\n'
                '• Add personal notes about your dream\n'
                '• Share your dream with others\n\n'
                'Free users get 2 dream analyses per week. Upgrade to Pro for unlimited analyses.',
            ),
            
            // Dream Interpreters Section
            _buildSection(
              title: 'Dream Interpreters',
              icon: Icons.person,
              content: 'Choose from different AI personalities to analyze your dreams:\n\n'
                '• Tap the "Interpreter" icon on the dream entry screen\n'
                '• You can also access interpreters from the hamburger menu\n'
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
                '• Use the search bar to find a dream by keyword\n'
                '• Swipe down to refresh your journal with new entries\n\n'
                'Managing journal entries:\n\n'
                '• Swipe left on any entry to reveal a Delete option\n'
                '• Swipe right on any entry to reveal a Hide option\n'
                '• Hidden dreams are removed from your journal but not deleted\n'
                '• Recover hidden dreams anytime via the hamburger menu → Hidden Dreams\n'
                '• Swipe actions are available on the main Journal tab only — dreams shown inside Insights filters are read-only',
            ),

            // Insights Section
            _buildSection(
              title: 'Insights',
              icon: Icons.insights,
              content: 'Discover the patterns hiding inside your dream journal:\n\n'
                '• Access through the "Insights" tab in the navigation bar\n'
                '• Recurring Symbols — see which images, animals, and objects appear most often across your dreams, each with a short interpretation\n'
                '• Emotional Themes — view the moods that thread through your nights (Anxiety, Wonder, Connection, Power, Peace, Loss, Strangeness)\n'
                '• Recurring Patterns — surface clusters of symbols and feelings that show up together\n'
                '• Deep Interpretation — once you\'ve logged enough dreams, Dreamr writes a personal reflection on what your dreams may be telling you, refreshed weekly\n'
                '• Tap any card to see the dreams that contributed to that pattern\n\n'
                'Insights grows richer the more you journal — keep adding dreams to unlock deeper analysis.',
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
                '• Select "Dreamr ✨ Decides" to let the AI match a style to your dream\'s vibe\n'
                '• Or pick a fixed preset to keep all future dream images visually consistent\n'
                '• Browse styles grouped by vibe (Peaceful, Epic, Nightmarish, etc.)\n'
                '• Preview example thumbnails before selecting (cached on-device for speed)\n'
                '• Tap the selected style again to clear it and return to automatic AI selection\n'
                '• Your choice is saved automatically and applied to all newly generated images',
            ),
            
            // Life Events Section
            _buildSection(
              title: 'Life Events',
              icon: Icons.favorite,
              content: 'Track important life events that might influence your dreams:\n\n'
                '• Access through the hamburger menu → Life Events\n'
                '• Add significant events like travel, stress, medication, etc.\n'
                '• These events will be considered in your dream analyses if relevant\n'
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
                '• Change the text size\n'
                '• Update your password\n'
                '• Log out of your account\n'
                '• Delete your account',
            ),
            
            // Dream Credits & Subscriptions Section
            _buildSection(
              title: 'Credits & Subscriptions',
              icon: Icons.stars,
              content: 'How credits and subscriptions work:\n\n'
                'New to Dreamr?\n'
                '• 5 days of free Pro access when you first start — unlimited analyses, automatic dream images, and every interpreter and image style\n\n'
                'Free tier (after the trial):\n'
                '• 2 dream analyses per week, refreshed every Sunday\n'
                '• Dream images use tokens — 4 tokens per image\n'
                '• Tap "Generate Dream Image" inside an analysis to spend tokens, or purchase a token pack from Subscription\n\n'
                'Pro subscribers:\n'
                '• Unlimited dream analyses\n'
                '• A dream image generated automatically with every analysis — no token cost\n'
                '• Access to all dream interpreter personalities and image styles\n'
                '• Discuss any dream further with the AI\n\n'
                '• Manage or upgrade your plan via the hamburger menu → Subscription',
            ),
            
            // Reporting Inappropriate Content
            _buildSection(
              title: 'Report Content',
              icon: Icons.flag_outlined,
              content: 'Dreamr screens AI output for safety, but if something feels wrong you can report it from the app:\n\n'
                '• Open the menu (top-right) and tap "Report content"\n'
                '• Pick what you were viewing and a reason\n'
                '• Optionally add a comment, then Submit\n'
                '• The content is hidden from you and reviewed within 24 hours\n\n'
                'The Deep Interpretation card on the Insights tab also has a small flag icon for one-tap reporting.',
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
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snap) {
                        final version = snap.hasData
                            ? 'v${snap.data!.version}+${snap.data!.buildNumber}'
                            : '';
                        return Text(
                          'Dreamr ✨ $version\n© 2026 Michael Kuriger',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color.fromARGB(200, 122, 209, 255),
                            fontSize: 12,
                          ),
                        );
                      },
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