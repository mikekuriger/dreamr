// screens/interpreters_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/models/interpreter.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/widgets/interpreter_icon_widget.dart';
import 'package:provider/provider.dart';
import 'package:dreamr/state/subscription_model.dart';
import 'package:dreamr/state/selected_interpreter_model.dart';

// Category configuration
class InterpreterCategory {
  final String name;
  final String label;
  final Color color;

  const InterpreterCategory({
    required this.name,
    required this.label,
    required this.color,
  });
}

const List<InterpreterCategory> _categories = [
  InterpreterCategory(name: 'grounded', label: 'Stable', color: Color(0xFFA9C2B1)),
  InterpreterCategory(name: 'supportive', label: 'Gentle', color: Color(0xFFE8B7C1)),
  InterpreterCategory(name: 'embodied', label: 'Present', color: Color(0xFFE6D3A3)),
  InterpreterCategory(name: 'analytical', label: 'Clear', color: Color(0xFF8FA6C1)),
  InterpreterCategory(name: 'reflective', label: 'Introspective', color: Color(0xFFB9A9C9)),
  InterpreterCategory(name: 'intuitive', label: 'Insightful', color: Color(0xFF9FC3C0)),
  InterpreterCategory(name: 'symbolic', label: 'Meaningful', color: Color(0xFF7E87B8)),
  InterpreterCategory(name: 'mythic', label: 'Transformative', color: Color(0xFF8B6C9E)),
  InterpreterCategory(name: 'creative', label: 'Imaginative', color: Color(0xFFE3A1A1)),
  InterpreterCategory(name: 'playful', label: 'Light', color: Color(0xFFF2C27A)),
  InterpreterCategory(name: 'whimsical', label: 'Delightful', color: Color(0xFFC4C9E8)),
];

// Extension method for string capitalization
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return '';
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

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
  String? _selectedFilter; // Store selected category filter (single selection)

  @override
  void initState() {
    super.initState();
    _loadInterpreters();
    _loadSelectedInterpreter();
    _loadFilters();
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

      if (!mounted) return;

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

      if (!mounted) return;

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

  Future<void> _loadFilters() async {
    final prefs = await SharedPreferences.getInstance();
    final filter = prefs.getString('interpreter_filter');
    if (!mounted) return;
    setState(() {
      _selectedFilter = filter ?? 'grounded'; // Default to 'grounded' if none selected
    });
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedFilter != null) {
      await prefs.setString('interpreter_filter', _selectedFilter!);
    } else {
      await prefs.remove('interpreter_filter');
    }
  }

  void _toggleFilter(String category) {
    setState(() {
      _selectedFilter = category; // Always select the clicked category
    });
    _saveFilters();
  }

  Future<void> _loadSelectedInterpreter() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getInt('selected_interpreter_id');
    if (!mounted) return;
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

  List<Interpreter> get _filteredInterpreters {
    final activeFilter = _selectedFilter ?? 'grounded'; // Default to 'grounded' if none selected
    return _sortedInterpreters.where((interpreter) => interpreter.category == activeFilter).toList();
  }

  List<Interpreter> get _sortedInterpreters {
    final sorted = List<Interpreter>.from(_interpreters);
    sorted.sort((a, b) {
      // First sort by category order
      final aCategoryIndex = _categories.indexWhere((cat) => cat.name == a.category);
      final bCategoryIndex = _categories.indexWhere((cat) => cat.name == b.category);
      
      final aIndex = aCategoryIndex >= 0 ? aCategoryIndex : _categories.length;
      final bIndex = bCategoryIndex >= 0 ? bCategoryIndex : _categories.length;
      
      if (aIndex != bIndex) {
        return aIndex.compareTo(bIndex);
      }
      
      // Then sort by sort_order
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return sorted;
  }

  List<InterpreterCategory> get _availableCategories {
    final usedCategories = _interpreters.map((interpreter) => interpreter.category).toSet();
    return _categories.where((category) => usedCategories.contains(category.name)).toList();
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
            const SizedBox(height: 4),
            // Filter buttons
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _availableCategories.length,
                itemBuilder: (context, index) {
                  final category = _availableCategories[index];
                  final activeFilter = _selectedFilter ?? 'grounded';
                  final isSelected = activeFilter == category.name;
                  return Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? category.color.withValues(alpha: 0.4)
                              : category.color.withValues(alpha: 0.2),
                          blurRadius: isSelected ? 8 : 8,
                          spreadRadius: isSelected ? 2 : 2,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: FilterChip(
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            category.name.capitalize(),
                            style: TextStyle(
                              color: isSelected ? const Color.fromARGB(255, 255, 255, 255) : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // Text(
                          //   category.label,
                          //   style: TextStyle(
                          //     color: Colors.white70,
                          //     fontSize: 9,
                          //   ),
                          // ),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (_) => _toggleFilter(category.name),
                      backgroundColor: Colors.black,
                      selectedColor: Colors.black87,
                      // checkmarkColor: Colors.white,
                      showCheckmark: false,
                      side: BorderSide(
                        color: isSelected ? category.color : category.color.withValues(alpha: 0.2),
                        width: isSelected ? 2 : 2,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredInterpreters.length,
                itemBuilder: (context, index) {
                  final interpreter = _filteredInterpreters[index];
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
    final category = _categories.firstWhere(
      (cat) => cat.name == interpreter.category,
      orElse: () => _categories.first,
    );

    final bool isProInterpreter = interpreter.accessTier != 'free';
    final bool locked = isProInterpreter && !_isPro;

    return GestureDetector(
      onTap: () {
        if (locked) {
          Navigator.pushNamed(context, '/subscription');
        } else {
          _selectInterpreter(interpreter.id);
        }
      },
      child: Opacity(
        opacity: locked ? 0.65 : 1.0,
        child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.all(8), // Add margin to allow shadow to extend beyond bounds
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? category.color : category.color.withValues(alpha: 0.4),
                width: isSelected ? 2 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? category.color.withValues(alpha: 0.6)
                      : category.color.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 4,
                  offset: const Offset(0, 4),
                ),
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
                      color: category.color.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: InterpreterIconWidget(
                      url: interpreter.iconFile.isNotEmpty
                          ? 'https://dreamr-us-west-01.zentha.me'
                              '${interpreter.animatedIconFile ?? interpreter.iconFile}'
                          : '',
                      iconSize: 40,
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
                            Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 14,
                                color: category.color,
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
          // Top-right badge: checkmark if selected, PRO lock if locked
          if (isSelected)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: category.color,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            )
          else if (locked)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: Colors.white, size: 10),
                    SizedBox(width: 3),
                    Text(
                      'PRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        ),  // Stack
      ),    // Opacity
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