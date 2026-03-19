// screens/image_style_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dreamr/theme/colors.dart';

/// A screen for selecting the style preset used by dream image generation.
///
/// Notes:
/// - For now, dream tones + style slugs are hard-coded.
/// - Example image URLs are stubbed out (empty) until you wire the backend.
/// - We use CachedNetworkImage, which already caches to disk to avoid re-downloading.
class ImageStyleSelectionScreen extends StatefulWidget {
  final VoidCallback? onDone;

  const ImageStyleSelectionScreen({super.key, this.onDone});

  @override
  State<ImageStyleSelectionScreen> createState() => _ImageStyleSelectionScreenState();
}

class _SingleThumb extends StatelessWidget {
  final String? url;

  const _SingleThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: (url == null || url!.isEmpty)
              ? Container(
                  color: AppColors.purple950,
                  child: const Center(
                    child: Icon(
                      Icons.image,
                      size: 28,
                      color: Color(0xFF82D9FF),
                    ),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => Container(
                    color: AppColors.purple950,
                    child: const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, _, error) => Container(
                    color: AppColors.purple950,
                    child: const Icon(
                      Icons.broken_image,
                      size: 28,
                      color: Color(0xFF82D9FF),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ImageStyleSelectionScreenState extends State<ImageStyleSelectionScreen> {
  static const _prefsSelectedStyleKey = 'selected_image_style';

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey<_DreamToneSectionState>> _toneSectionKeys = {};

  String? _selectedStyleId;
  bool _loading = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSelectedStyle();
  }

  String? _toneKeyForStyleId(String styleId) {
    for (final tone in _toneSections) {
      for (final s in tone.styles) {
        if (s.id == styleId) return tone.id;
      }
    }
    return null;
  }

  String? _selectedSubjectUrl(String subject) {
    final styleId = _selectedStyleId;
    if (styleId == null) return null;
    final toneKey = _toneKeyForStyleId(styleId);
    if (toneKey == null) return null;
    return '$_stylesBaseUrl/$toneKey/$styleId/$subject.png';
  }

  Future<void> _loadSelectedStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _selectedStyleId = prefs.getString(_prefsSelectedStyleKey);
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load selected image style: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _selectStyle(ImageStyleOption style) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Toggle: tap selected style again to clear selection (AI decides).
      if (_selectedStyleId == style.id) {
        await prefs.remove(_prefsSelectedStyleKey);
        setState(() {
          _selectedStyleId = null;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Style cleared — AI will decide'),
            duration: Duration(milliseconds: 900),
          ),
        );
        return;
      }

      await prefs.setString(_prefsSelectedStyleKey, style.id);
      setState(() {
        _selectedStyleId = style.id;
      });

      // UX: after selecting a custom style, collapse the current section and
      // scroll back to the top so the user sees the "Selected Style" summary.
      final toneKey = _toneKeyForStyleId(style.id);
      if (toneKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _toneSectionKeys[toneKey]?.currentState?.collapse();
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Image style selected: ${style.title}'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to save selected image style: $e');
    }
  }

  Future<void> _selectAiDecides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsSelectedStyleKey);
      setState(() {
        _selectedStyleId = null;
      });
    } catch (e) {
      debugPrint('❌ Failed to clear selected image style: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Dreamr ✨ Image Styles',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Choose a “look” for your dream images',
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
            Navigator.of(context).pop();
            widget.onDone?.call();
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              // Protect the bottom gesture/nav area (home indicator) so the last cards
              // never sit under system UI.
              child: ListView(
                controller: _scrollController,
                // Slightly tighter horizontal padding so cards fill more of the screen.
                padding: EdgeInsets.fromLTRB(
                  8,
                  16,
                  8,
                  24 + MediaQuery.of(context).padding.bottom,
                ),
                children: [
                // const Text(
                //   'Tap a style to select it. Each style includes example thumbnails (cached on-device).',
                //   style: TextStyle(
                //     fontSize: 13,
                //     color: Colors.white54,
                //     height: 1.3,
                //   ),
                // ),
                // const SizedBox(height: 12),

                // Helpful “hint” callout to match the app’s visual language.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(105, 83, 93, 0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color.fromARGB(155, 255, 247, 0),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.tips_and_updates, color: Colors.yellow, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Dreamr images are generated using a style selected '
                          'from the dream’s tone. If you’d rather use a consistent visual '
                          'style for all images, choose one below.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Show selected image style if set.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.purple950,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color.fromARGB(195, 255, 247, 0),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                      color: const Color.fromARGB(255, 255, 247, 0),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Selected Style',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.purple950,
                                borderRadius: BorderRadius.circular(10),
                                // border: Border.all(
                                //   color: Colors.white24,
                                //   width: 1,
                                // ),
                              ),
                              child: Text(
                                _selectedStyleId == null
                                    ? 'Dreamr✨ decides'
                                    : _prettyFromSlug(_selectedStyleId!),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ),
                          if (_selectedStyleId != null) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SingleThumb(
                                url: _selectedSubjectUrl('tub'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Default option: AI decides (no fixed style)
                _AiDecidesCard(
                  selected: _selectedStyleId == null,
                  onTap: _selectAiDecides,
                ),

                const SizedBox(height: 16),

                ..._toneSections.map((tone) {
                  final key = _toneSectionKeys.putIfAbsent(
                    tone.id,
                    () => GlobalKey<_DreamToneSectionState>(),
                  );
                  return _DreamToneSection(
                    key: key,
                    tone: tone,
                    selectedStyleId: _selectedStyleId,
                    onSelect: _selectStyle,
                  );
                }),
                ],
              ),
            ),
    );
  }
}

// -------------------- Data + UI helpers --------------------

class DreamToneSectionData {
  final String id;
  final String title;
  final String? subtitle;
  final Color accent;
  final List<ImageStyleOption> styles;

  const DreamToneSectionData({
    required this.id,
    required this.title,
    required this.accent,
    required this.styles,
    this.subtitle,
  });
}

class ImageStyleOption {
  final String id; // slug
  final String title;
  final String? description;
  final List<String> exampleImageUrls;

  const ImageStyleOption({
    required this.id,
    required this.title,
    this.description,
    this.exampleImageUrls = const [],
  });
}

String _prettyFromSlug(String slug) {
  final normalized = slug.replaceAll('_', ', ').replaceAll('-', ' ').trim();
  if (normalized.isEmpty) return slug;
  final words = normalized.split(RegExp(r'\s+'));
  return words
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _prettyCategoryName(String raw) {
  // raw may look like "Ancient_mythic" or "_Uncategorized"
  final cleaned = raw.replaceAll('_', ' ').trim();
  return _prettyFromSlug(cleaned);
}

const List<Color> _accentPalette = [
  Color(0xFF82D9FF), // cyan
  Color(0xFFC084FC), // purple400
  Color(0xFFE8B7C1), // soft pink
  Color(0xFFE6D3A3), // sand
  Color(0xFF9FC3C0), // teal
  Color(0xFFB9A9C9), // lilac
  Color(0xFFF2C27A), // warm
  Color(0xFF8FA6C1), // bluegray
];

// Backend static styles base directory.
const String _stylesBaseUrl = 'https://dreamr-us-west-01.zentha.me/static/images/styles';

// Default set of example subjects to try for each style.
// The UI will show the first 4 in the 2x2 grid, but we keep extras for future UI.
const List<String> _defaultStyleSubjects = [
  // 'car',
  // 'couple',
  // 'tara',
  // 'treehouse',
  'tub_hires',
  // 'well',
];

List<String> _buildExampleImageUrls({
  required String toneKey,
  required String styleSlug,
  List<String> subjects = _defaultStyleSubjects,
}) {
  return subjects
      .map((s) => '$_stylesBaseUrl/$toneKey/$styleSlug/$s.png')
      .toList(growable: false);
}

final List<DreamToneSectionData> _toneSections = (() {
  // Your provided structure.
  const data = <String, List<String>>{
    'Peaceful_Gentle': [
      "soft-watercolor-illustration_pastel-tones_gentle-lighting",
      "dreamlike-oil-painting_muted-colors_smooth-brush-strokes",
      "minimalist-fantasy-illustration_airy-composition_warm-glow",
    ],  
    'Romantic_nostalgic': [
      'impressionist-painting_warm-light_nostalgic-mood',
      'soft-focus-oil-painting_romantic-atmosphere',
      'vintage-storybook-illustration_faded-tones',
    ],
    'Elegant_ornate': [
      'art-nouveau-inspired-illustration_flowing-lines',
      'decorative-fantasy-illustration_intricate-detail',
      'ornate-oil-painting_rich-textures_classical-elegance',
    ],
    'Whimsical_surreal': [
      'artistic-vivid-style',
      'painterly-surreal-fantasy_floating-elements_gentle-distortion',
      'surreal-storybook-illustration_imaginative-shapes_soft-color',
    ],
    'Ancient_mythic': [
      'ancient-fresco-inspired-painting_earthy-tones',
      'epic-mythic-oil-painting_timeless-atmosphere',
      'mythological-fantasy-illustration_classical-composition',
    ],
    'Epic_heroic': [
      'cinematic-fantasy-concept-art_dramatic-lighting_painterly',
      'illustrated-epic-fantasy-poster_dynamic-composition',
      'mythic-oil-painting_heroic-scale_rich-color-depth',
    ],
    'Futuristic_uncanny': [
      'cyberdream-illustration_neon-accents_soft-focus',
      'retrofuturistic-concept-art_uncanny-atmosphere',
      'surreal-sci-fi-painting_liminal-spaces',
    ],
    'Nightmarish_dark': [
      'dark-fairytale-illustration_shadow-heavy_painterly',
      'moody-cinematic-illustration_dream-horror-atmosphere',
      'surreal-nightmare-art_distorted-forms_low-light',
    ],
    'Just_For_Fun': [
      'concept-art',
      'steampunk',
      'photo-realistic',
    ],
  };

  // Display order: gentle at top → intense at bottom, Uncategorized last.
  const toneOrder = <String>[
    'Peaceful_Gentle',
    'Romantic_nostalgic',
    'Elegant_ornate',
    'Whimsical_surreal',
    'Ancient_mythic',
    'Epic_heroic',
    'Futuristic_uncanny',
    'Nightmarish_dark',
    'Just_For_Fun',
    'Uncategorized',
  ];

  final keys = <String>[
    ...toneOrder.where(data.containsKey),
    // Fallback: append any unknown/new categories not listed above.
    ...data.keys.where((k) => !toneOrder.contains(k)),
  ];

  return List.generate(keys.length, (i) {
    final key = keys[i];
    final accent = _accentPalette[i % _accentPalette.length];

    final styles = data[key]!
        .map(
          (slug) => ImageStyleOption(
            id: slug,
            title: _prettyFromSlug(slug),
            // Leave description empty for now; once you wire backend you can
            // add human-friendly descriptions.
            description: null,
            // TODO: fill from backend or a local JSON config.
            exampleImageUrls: _buildExampleImageUrls(toneKey: key, styleSlug: slug),
          ),
        )
        .toList();

    return DreamToneSectionData(
      id: key,
      title: _prettyCategoryName(key),
      subtitle: null,
      accent: accent,
      styles: styles,
    );
  });
})();

/// All style preview image URLs derived from the hardcoded tone/style data.
/// Used by PrefetchService to warm the image cache on login.
List<String> allStylePreviewUrls() => _toneSections
    .expand((tone) => tone.styles)
    .expand((style) => style.exampleImageUrls)
    .toList();

class _DreamToneSection extends StatefulWidget {
  final DreamToneSectionData tone;
  final String? selectedStyleId;
  final ValueChanged<ImageStyleOption> onSelect;

  const _DreamToneSection({
    super.key,
    required this.tone,
    required this.selectedStyleId,
    required this.onSelect,
  });

  @override
  State<_DreamToneSection> createState() => _DreamToneSectionState();
}

class _DreamToneSectionState extends State<_DreamToneSection> {
  final ExpansionTileController _controller = ExpansionTileController();
  bool _expanded = false;

  void collapse() {
    if (!_expanded) return;
    _controller.collapse();
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.purple950,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tone.accent.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: tone.accent.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        // Tames ExpansionTile defaults.
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          controller: _controller,
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white70,
          title: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: tone.accent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tone.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          subtitle: tone.subtitle == null
              ? Text(
                  '${tone.styles.length} styles',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                )
              : Text(
                  tone.subtitle!,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
          children: [
            for (final style in tone.styles)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _ImageStyleCard(
                  toneAccent: tone.accent,
                  style: style,
                  selected: widget.selectedStyleId == style.id,
                  onTap: () => widget.onSelect(style),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageStyleCard extends StatelessWidget {
  final Color toneAccent;
  final ImageStyleOption style;
  final bool selected;
  final VoidCallback onTap;

  const _ImageStyleCard({
    required this.toneAccent,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? toneAccent : toneAccent.withValues(alpha: 0.35);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  // Keep this subtle — just enough depth to highlight selection.
                  // When selected, match the shadow hue to the selected border color.
                  color: selected
                      ? borderColor.withValues(alpha: 0.78)
                      : toneAccent.withValues(alpha: 0.08),
                  blurRadius: selected ? 8 : 6,
                  spreadRadius: selected ? 1 : 0,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (style.description != null && style.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    style.description!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 10),

                // Full-width thumbnails so the tiny images are actually readable.
                _ThumbnailGrid(
                  urls: style.exampleImageUrls,
                  borderColor: toneAccent.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
          if (selected)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: toneAccent,
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

class _ThumbnailGrid extends StatelessWidget {
  final List<String> urls;
  final Color borderColor;

  const _ThumbnailGrid({
    required this.urls,
    required this.borderColor,
  });

//                                                                                            images
  @override
  Widget build(BuildContext context) {
    // 2 columns x 3 rows of square thumbnails.
    // Width : Height = 2 : 3 (because height = (width/2) * 3).
    return AspectRatio(
      // aspectRatio: 2 / 3,                                                                          // ratio
      aspectRatio: 1 / 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: LayoutBuilder(
            builder: (context, c) {
              final d = c.maxWidth;
              // final cell = d / 2;                                                                    // # columns
              final cell = d / 1;                                                                    // # columns

              // Fill 6 slots (2x3).
              // final slots = List<String?>.generate(6, (i) => i < urls.length ? urls[i] : null);
              final slots = List<String?>.generate(1, (i) => i < urls.length ? urls[i] : null);     // # images

              return Wrap(
                spacing: 0,
                runSpacing: 0,
                children: [
                  for (final url in slots)
                    SizedBox(
                      width: cell,
                      height: cell,
                      child: url == null || url.isEmpty
                          ? Container(
                            color: AppColors.purple950,
                            child: const Icon(
                              Icons.image,
                              size: 24,
                              color: Color(0xFF82D9FF),
                            ),
                          )
                          : CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              placeholder: (context, _) => Container(
                                color: AppColors.purple950,
                                child: const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              ),
                              errorWidget: (context, _, error) => Container(
                                color: AppColors.purple950,
                                child: const Icon(
                                  Icons.broken_image,
                                  size: 24,
                                  color: Color(0xFF82D9FF),
                                ),
                              ),
                            ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AiDecidesCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _AiDecidesCard({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF82D9FF);
    final borderColor = selected ? accent : accent.withValues(alpha: 0.35);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.purple950,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  // Match the selected-card glow style.
                  color: selected
                      ? accent.withValues(alpha: 0.50)
                      : accent.withValues(alpha: 0.08),
                  blurRadius: selected ? 14 : 6,
                  spreadRadius: selected ? 2 : 0,
                  offset: selected ? const Offset(0, 4) : const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.5), width: 1),
                  ),
                  child: const Icon(Icons.auto_awesome, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dreamr✨ decides',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'No fixed style preset — Dreamr will pick what fits your dream best.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            const Positioned(
              top: 10,
              right: 10,
              child: _SelectedBadge(),
            ),
        ],
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: const BoxDecoration(
        color: Color(0xFF82D9FF),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}
