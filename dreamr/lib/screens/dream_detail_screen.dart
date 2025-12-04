// screens/dream_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/widgets/dream_journal_widget.dart';
import 'package:dreamr/theme/colors.dart';

class DreamDetailScreen extends StatelessWidget {
  final Dream dream;

  const DreamDetailScreen({
    super.key,
    required this.dream,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.purple900,
      appBar: AppBar(
        backgroundColor: AppColors.purple950,
        foregroundColor: Colors.white,
        elevation: 4,
        title: const Text(
          'My Dream ✨',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: DreamJournalWidget(
          filteredDreams: [dream],
          autoExpandSingle: true,
          embeddedInScrollView: false,
        ),
      ),
    );
  }
}
