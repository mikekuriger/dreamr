// screens/insights_screen.dart
import 'package:flutter/material.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/models/dream_insights.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/services/insights_analyzer.dart';
import 'package:dreamr/screens/dream_detail_screen.dart';
import 'package:dreamr/widgets/dream_journal_widget.dart';
import 'package:dreamr/theme/colors.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _loading = true;
  String? _error;
  DreamInsights? _insights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dreams = await ApiService.fetchDreams();
      final insights = InsightsAnalyzer.analyze(dreams);
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load dreams: $e';
        _loading = false;
      });
    }
  }

  void _openFilteredDreams(BuildContext context, String title, List<Dream> dreams) {
    if (dreams.isEmpty) return;
    if (dreams.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DreamDetailScreen(dream: dreams.first)),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FilteredDreamsScreen(title: title, dreams: dreams),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.purple950,
      appBar: AppBar(
        backgroundColor: AppColors.purple950,
        foregroundColor: Colors.white,
        elevation: 4,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dreamr ✨ Insights',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            SizedBox(height: 2),
            Text(
              'Patterns, symbols, and themes from your journal',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFD1B2FF)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white54, size: 40),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final insights = _insights;
    if (insights == null || insights.isEmpty) {
      return _emptyState();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _headerCard(insights),
          const SizedBox(height: 12),
          if (insights.symbols.isNotEmpty) ...[
            _sectionTitle('🔮 Recurring Symbols'),
            const SizedBox(height: 8),
            _symbolsGrid(insights.symbols),
            const SizedBox(height: 16),
          ],
          if (insights.themes.isNotEmpty) ...[
            _sectionTitle('💗 Emotional Themes'),
            const SizedBox(height: 8),
            _themesCard(insights.themes),
            const SizedBox(height: 16),
          ],
          if (insights.patterns.isNotEmpty) ...[
            _sectionTitle('🔁 Recurring Patterns'),
            const SizedBox(height: 8),
            ...insights.patterns.map(_patternCard),
            const SizedBox(height: 16),
          ],
          _whyDreamsRepeatCard(insights),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          const SizedBox(height: 80),
          const Center(child: Text('🌙', style: TextStyle(fontSize: 48))),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Not enough dreams yet',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Insights need a few dreams to find patterns in. Log a handful of dreams and come back — symbols and themes will start to surface here.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(DreamInsights insights) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color.fromARGB(255, 255, 230, 7), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 130, 217, 255).withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '✨ Patterns in Your Dreams',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 13),
              children: [
                const TextSpan(text: 'Based on '),
                TextSpan(
                  text: '${insights.dreamCount}',
                  style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold),
                ),
                TextSpan(text: insights.dreamCount == 1 ? ' dream' : ' dreams'),
                if (insights.windowDays > 1) ...[
                  const TextSpan(text: ' across '),
                  TextSpan(
                    text: '${insights.windowDays}',
                    style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' days'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _symbolsGrid(List<SymbolHit> symbols) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: symbols.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, i) {
        final s = symbols[i];
        return GestureDetector(
          onTap: () => _showSymbolSheet(s),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.black.withAlpha(200),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.purple400.withValues(alpha: 0.5), width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(s.icon, style: const TextStyle(fontSize: 26)),
                const SizedBox(height: 4),
                Text(
                  s.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '×${s.count}',
                  style: const TextStyle(color: Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSymbolSheet(SymbolHit s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.purple950,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(s.icon, style: const TextStyle(fontSize: 36)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                          ),
                          Text(
                            'Appears in ${s.count} ${s.count == 1 ? 'dream' : 'dreams'}',
                            style: const TextStyle(color: Colors.yellow, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  s.meaning,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _openFilteredDreams(context, '${s.icon} ${s.name}', s.dreams);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.deepPurple.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.list_alt),
                    label: Text('View these ${s.count} ${s.count == 1 ? 'dream' : 'dreams'}'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _themesCard(List<ThemeWeight> themes) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.purple400.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        children: themes.map((t) {
          final pct = (t.weight * 100).round();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GestureDetector(
              onTap: () => _openFilteredDreams(context, '${t.emoji} ${t.label}', t.dreams),
              child: Row(
                children: [
                  Text(t.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Text(
                      t.label,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: t.weight,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(_themeColor(t.label)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$pct%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _themeColor(String label) {
    switch (label) {
      case 'Anxiety & Escape':
        return Colors.orange.shade300;
      case 'Wonder & Discovery':
        return Colors.purple.shade200;
      case 'Connection & Love':
        return Colors.pink.shade200;
      case 'Power & Adventure':
        return Colors.amber.shade300;
      case 'Peace & Stillness':
        return Colors.tealAccent.shade100;
      case 'Loss & Endings':
        return Colors.brown.shade200;
      case 'Strangeness & The Uncanny':
        return Colors.indigo.shade200;
      default:
        return Colors.deepPurple.shade200;
    }
  }

  Widget _patternCard(PatternFinding p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.headline,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, height: 1.3),
          ),
          if (p.detail != null) ...[
            const SizedBox(height: 6),
            Text(
              p.detail!,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ],
          if (p.dreams.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openFilteredDreams(context, p.headline, p.dreams),
                icon: const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                label: Text(
                  'View these ${p.dreams.length} ${p.dreams.length == 1 ? 'dream' : 'dreams'}',
                  style: const TextStyle(color: Colors.white),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.purple800.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Placeholder for the future AI-generated narrative. Today this composes a
  // gentle reflection from the local data — no network call. When the backend
  // /api/insights endpoint exists, swap the body of this card for the returned
  // narrative and add a "Generate fresh interpretation" button.
  Widget _whyDreamsRepeatCard(DreamInsights insights) {
    final lines = <String>[];
    if (insights.symbols.isNotEmpty) {
      final top = insights.symbols.first;
      lines.add(
        '${top.name} keeps returning — it has surfaced in ${top.count} of your dreams. Symbols that recur are usually trying to be noticed.',
      );
    }
    if (insights.themes.isNotEmpty) {
      final top = insights.themes.first;
      lines.add(
        'The dominant emotional thread is ${top.label.toLowerCase()}. That mood is the lens your sleeping mind seems to be looking through right now.',
      );
    }
    if (insights.symbols.length > 1) {
      final second = insights.symbols[1];
      lines.add(
        '${second.name} shows up too, appearing in ${second.count} dreams. Pairings tell a richer story than any single image.',
      );
    }
    if (lines.isEmpty) {
      lines.add(
        'As your journal grows, recurring images and feelings will gather here — the threads that connect one dream to the next.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.purple900.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.purple600.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🌙 Why Your Dreams Repeat',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tip: deeper AI interpretation coming soon. For now, tap a symbol or theme above to revisit the dreams behind it.',
            style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

class _FilteredDreamsScreen extends StatelessWidget {
  final String title;
  final List<Dream> dreams;

  const _FilteredDreamsScreen({required this.title, required this.dreams});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.purple900,
      appBar: AppBar(
        backgroundColor: AppColors.purple950,
        foregroundColor: Colors.white,
        elevation: 4,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        top: false,
        child: DreamJournalWidget(
          filteredDreams: dreams,
          autoExpandSingle: false,
          embeddedInScrollView: true,
        ),
      ),
    );
  }
}
