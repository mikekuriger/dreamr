// widgets/report_content_sheet.dart
//
// Shared "Report content" modal used to satisfy Google Play's
// AI-Generated Content policy. Invoke from any AI surface (analysis
// text, dream image, insight card, discuss reply, gallery image) via
// the static `show(...)` helper. The sheet collects a category and
// optional comment, then POSTs through ApiService.reportContent.
//
// Returns true if the user successfully submitted; false otherwise.

import 'package:flutter/material.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/theme/colors.dart';

/// What kind of AI-generated content is being reported. The string
/// value is what the backend expects.
enum ReportContentType {
  analysis('analysis', 'Dream analysis'),
  image('image', 'Dream image'),
  insight('insight', 'Deep interpretation'),
  discuss('discuss', 'Discussion reply'),
  other('other', 'Other');

  final String wire;
  final String label;
  const ReportContentType(this.wire, this.label);
}

/// User-facing reason for the report. The string value is what the
/// backend expects.
enum ReportCategory {
  childSafety('child_safety', 'Child safety concern'),
  sexual('sexual', 'Sexual or explicit content'),
  hate('hate', 'Hate speech or harassment'),
  violence('violence', 'Violence, self-harm, or dangerous content'),
  misinfo('misinfo', 'Misinformation'),
  other('other', 'Something else');

  final String wire;
  final String label;
  const ReportCategory(this.wire, this.label);
}

class ReportContentSheet extends StatefulWidget {
  /// The content type being reported. When unknown (e.g. invoked from
  /// the hamburger menu), pass `other` and the sheet will surface a
  /// picker so the user can tell us what they were looking at.
  final ReportContentType contentType;

  /// Optional pointer to the source row (dream id, discuss id, etc.).
  /// Backend accepts any string up to 64 chars.
  final String? contentId;

  /// Optional snapshot of what the user actually saw. Useful if the
  /// underlying record gets edited or deleted before review.
  final String? contentSnapshot;

  /// When true, show a content-type picker (used by the hamburger menu
  /// entry point where the source isn't inferred).
  final bool allowContentTypeChange;

  const ReportContentSheet({
    super.key,
    required this.contentType,
    this.contentId,
    this.contentSnapshot,
    this.allowContentTypeChange = false,
  });

  /// Show the sheet. Returns true if the user submitted a report.
  static Future<bool> show(
    BuildContext context, {
    required ReportContentType contentType,
    String? contentId,
    String? contentSnapshot,
    bool allowContentTypeChange = false,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.purple950,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ReportContentSheet(
        contentType: contentType,
        contentId: contentId,
        contentSnapshot: contentSnapshot,
        allowContentTypeChange: allowContentTypeChange,
      ),
    );
    return result == true;
  }

  @override
  State<ReportContentSheet> createState() => _ReportContentSheetState();
}

class _ReportContentSheetState extends State<ReportContentSheet> {
  late ReportContentType _type;
  ReportCategory? _category;
  final TextEditingController _comment = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.contentType;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_category == null) {
      setState(() => _error = 'Please choose a reason.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiService.reportContent(
        contentType: _type.wire,
        category: _category!.wire,
        contentId: widget.contentId,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        contentSnapshot: widget.contentSnapshot,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Thanks — we'll review this within 24 hours."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit report. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + viewInsets,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Report content',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                "Help us keep Dreamr safe. Reports are reviewed within 24 hours, and this content will be hidden from you in the meantime.",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),

              if (widget.allowContentTypeChange) ...[
                const Text(
                  'What were you viewing?',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<ReportContentType>(
                  value: _type,
                  dropdownColor: AppColors.purple900,
                  iconEnabledColor: Colors.white70,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.purple800,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: ReportContentType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (v) {
                          if (v != null) setState(() => _type = v);
                        },
                ),
                const SizedBox(height: 16),
              ],

              const Text(
                'Why are you reporting this?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...ReportCategory.values.map(
                (cat) => RadioListTile<ReportCategory>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: cat,
                  groupValue: _category,
                  onChanged: _submitting ? null : (v) => setState(() => _category = v),
                  title: Text(cat.label, style: const TextStyle(color: Colors.white)),
                  activeColor: AppColors.purple400,
                ),
              ),

              const SizedBox(height: 8),
              const Text(
                'Additional details (optional)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _comment,
                enabled: !_submitting,
                maxLines: 3,
                maxLength: 500,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'What was wrong with this content?',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: AppColors.purple800,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: const TextStyle(color: Colors.white38),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.purple400.withValues(alpha: 0.6)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purple600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Submit',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
