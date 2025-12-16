// screens/interpreters_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/models/interpreter.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/state/subscription_model.dart';
import 'package:dreamr/state/selected_interpreter_model.dart';

class InterpretersScreen extends StatefulWidget {
  const InterpretersScreen({super.key});

  @override
  State<InterpretersScreen> createState() => _InterpretersScreenState();
}

class _InterpretersScreenState extends State<InterpretersScreen> {
  List<Interpreter> _interpreters = [];
  bool _loading = true;
  int? _selectedInterpreterId;
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _loadInterpreters();
    _loadSelectedInterpreter();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check subscription status
    final subscriptionModel = Provider.of<SubscriptionModel>(context, listen: false);
    if (subscriptionModel.loaded) {
      setState(() {
        _isPro = subscriptionModel.status.isActive;
      });
      // Reload interpreters with subscription filter
      _loadInterpreters();
    }
  }

  Future<void> _loadInterpreters() async {
    try {
      final interpreters = await ApiService.fetchInterpreters();

      setState(() {
        _interpreters = interpreters;
        _loading = false;
      });

      // Load selected interpreter after interpreters are loaded
      await _loadSelectedInterpreter();

      // Show message if no interpreters loaded
      if (interpreters.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No interpreters available at this time')),
        );
      }
    } catch (e) {
      debugPrint('Failed to load interpreters: $e');
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load interpreters')),
        );
      }
    }
  }

  Future<void> _loadSelectedInterpreter() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getInt('selected_interpreter_id');
    setState(() {
      _selectedInterpreterId = selectedId;
    });

    // If we have interpreters loaded and a selected ID, update the provider
    if (_interpreters.isNotEmpty && selectedId != null && mounted) {
      final selectedInterpreter = _interpreters.cast<Interpreter?>().firstWhere(
        (interpreter) => interpreter?.id == selectedId,
        orElse: () => null,
      );
      if (selectedInterpreter != null) {
        final interpreterModel = Provider.of<SelectedInterpreterModel>(context, listen: false);
        interpreterModel.setSelectedInterpreter(selectedInterpreter);
      }
    }
  }

  Future<void> _selectInterpreter(int interpreterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_interpreter_id', interpreterId);

    setState(() {
      _selectedInterpreterId = interpreterId;
    });

    // Find the selected interpreter to show its name and update provider
    final selectedInterpreter = _interpreters.firstWhere(
      (interpreter) => interpreter.id == interpreterId,
    );

    // Update the global selected interpreter
    if (mounted) {
      final interpreterModel = Provider.of<SelectedInterpreterModel>(context, listen: false);
      interpreterModel.setSelectedInterpreter(selectedInterpreter);
    }

    // if (mounted) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(content: Text('${selectedInterpreter.name} selected!')),
    //   );
    // }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "Dreamr ✨ Interpreters",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "Choose your dream analysis personality",
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
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Dreamr ✨ Dram Interpreters",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "Choose your dream analysis personality",
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
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Each interpreter brings a unique perspective to your dream analysis.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white54,
              ),
            ),
            if (!_isPro) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.purple950.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.purple600.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.star,
                      color: AppColors.purple600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Upgrade to Pro for access to all dream interpreters and unlock the full dream analysis experience.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _interpreters.length,
                itemBuilder: (context, index) {
                  final interpreter = _interpreters[index];
                  final isSelected = _selectedInterpreterId == interpreter.id;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildInterpreterCard(interpreter, isSelected),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterpreterCard(Interpreter interpreter, bool isSelected) {
    return GestureDetector(
      onTap: () => _selectInterpreter(interpreter.id),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.all(8), // Add margin to allow shadow to extend beyond bounds
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.purple600 : const Color(0xFF82D9FF).withValues(alpha: 0.4),
                width: isSelected ? 2 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppColors.purple600.withValues(alpha: 0.6)
                      : const Color(0xFF82D9FF).withValues(alpha: 0.3),
                  // blurRadius: 20,
                  blurRadius: 8,
                  spreadRadius: 4,
                  offset: const Offset(0, 4),
                ),
                // BoxShadow(
                //   color: isSelected
                //       ? AppColors.purple600.withValues(alpha: 0.2)
                //       : const Color(0xFF82D9FF).withValues(alpha: 0.1),
                //   blurRadius: 40,
                //   // spreadRadius: 4,
                //   offset: const Offset(0, 3),
                // ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side: Character image
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF82D9FF).withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: CachedNetworkImage(
                      imageUrl: 'https://dreamr-us-west-01.zentha.me${interpreter.iconFile}',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.purple950,
                        child: const Icon(
                          Icons.person,
                          color: Color(0xFF82D9FF),
                          size: 40,
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.purple950,
                        child: const Icon(
                          Icons.person,
                          color: Color(0xFF82D9FF),
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),

                // Right side: Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name at top
                      Text(
                        interpreter.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Card blurb
                      Text(
                        interpreter.cardBlurb,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Card bullets
                      ...interpreter.cardBullets.map((bullet) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF82D9FF),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                bullet,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),

                      const SizedBox(height: 12),

                      // Tone examples (show first 2)
                      if (interpreter.toneExamples.isNotEmpty) ...[
                        const Text(
                          'Examples:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...interpreter.toneExamples.take(2).map((example) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '"$example"',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Selection indicator - positioned absolutely
          if (isSelected)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.purple600,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Helper function to get selected interpreter (can be used in dashboard)
class InterpreterHelper {
  static Future<Interpreter?> getSelectedInterpreter(List<Interpreter> allInterpreters) async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getInt('selected_interpreter_id');
    if (selectedId == null) return null;
    
    return allInterpreters.cast<Interpreter?>().firstWhere(
      (interpreter) => interpreter?.id == selectedId,
      orElse: () => null,
    );
  }
}