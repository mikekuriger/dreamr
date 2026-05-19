// services/insights_analyzer.dart
//
// Pure-Dart analyzer. Takes a List<Dream> and produces a DreamInsights
// object that the InsightsScreen renders. No network, no async work.
//
// Strategy:
//  - Pull the searchable text out of each dream (text + summary + notes).
//    The AI `analysis` field is intentionally excluded — it uses figurative
//    language ("you're being tested", "the death of an old chapter") that
//    would tag symbols which the dream itself never mentions.
//  - For each symbol in the curated dictionary, count how many dreams it
//    appears in, using word-boundary matching so `test` doesn't fire on
//    "latest" and `dead` doesn't fire on "deadline".
//  - We count *dreams*, not raw occurrences, so a single dream that says
//    "water" five times doesn't dominate.
//  - For themes, we bucket dreams into emotional families using their tone string
//    and a small set of keyword cues.
//  - For patterns, we surface simple structural signals:
//      * symbol + theme co-occurrences ("water shows up alongside anxiety in 4 dreams")
//      * short streaks ("3 dreams in a row mention…")
//      * window stats ("you logged 5 dreams in the last week")
//
// Everything is "best effort". If the journal is small or sparse, sections
// simply come back shorter — the UI handles empty states.

import 'package:dreamr/data/dream_symbols.dart';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/models/dream_insights.dart';

class InsightsAnalyzer {
  static const int _minSymbolCount = 2; // hide one-off matches; they're noise
  static const int _maxSymbols = 12;
  static const int _maxPatterns = 5;

  static DreamInsights analyze(List<Dream> dreams) {
    if (dreams.isEmpty) {
      return const DreamInsights(
        dreamCount: 0,
        windowDays: 0,
        earliest: null,
        latest: null,
        symbols: [],
        themes: [],
        patterns: [],
        tones: [],
      );
    }

    final sorted = [...dreams]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final earliest = sorted.first.createdAt;
    final latest = sorted.last.createdAt;
    final windowDays = latest.difference(earliest).inDays + 1;

    final symbols = _findSymbols(dreams);
    final themes = _findThemes(dreams);
    final tones = _toneSlices(dreams);
    final patterns = _findPatterns(dreams, symbols, themes);

    return DreamInsights(
      dreamCount: dreams.length,
      windowDays: windowDays,
      earliest: earliest,
      latest: latest,
      symbols: symbols,
      themes: themes,
      patterns: patterns,
      tones: tones,
    );
  }

  // Combine the searchable surfaces of a dream into one lowercase string.
  // Deliberately excludes `analysis` — see file header.
  static String _haystack(Dream d) {
    return '${d.text}\n${d.summary}\n${d.notes}'.toLowerCase();
  }

  static List<SymbolHit> _findSymbols(List<Dream> dreams) {
    final hits = <SymbolHit>[];
    final hays = dreams.map(_haystack).toList(growable: false);

    for (final def in kDreamSymbols) {
      final patterns = def.keywords
          .map((kw) => RegExp(r'\b' + RegExp.escape(kw) + r'\b'))
          .toList(growable: false);
      final exclusions = def.excludePhrases
          .map((p) => RegExp(r'\b' + RegExp.escape(p) + r'\b'))
          .toList(growable: false);
      final matched = <Dream>[];
      for (var i = 0; i < dreams.length; i++) {
        var hay = hays[i];
        for (final ex in exclusions) {
          hay = hay.replaceAll(ex, ' ');
        }
        if (patterns.any((re) => re.hasMatch(hay))) {
          matched.add(dreams[i]);
        }
      }
      if (matched.length >= _minSymbolCount) {
        hits.add(SymbolHit(
          name: def.name,
          icon: def.icon,
          meaning: def.meaning,
          count: matched.length,
          dreams: matched,
        ));
      }
    }

    hits.sort((a, b) => b.count.compareTo(a.count));
    return hits.take(_maxSymbols).toList();
  }

  // Themes are coarser than symbols — they're emotional families.
  // We bucket on tone first (since the AI already labeled it), then nudge
  // with text keywords when the tone is ambiguous or missing.
  static List<ThemeWeight> _findThemes(List<Dream> dreams) {
    final buckets = <String, _ThemeBucket>{
      'Anxiety & Escape': _ThemeBucket(
        emoji: '😰',
        description:
            'Dreams in this family often surface when something in waking life feels out of your control. Notice what you are running from — it usually points to what you have been avoiding rather than what is actually dangerous.',
        toneCues: ['nightmar', 'dark', 'fear', 'anxious'],
        textCues: ['running', 'hiding', 'trapped', 'escape', 'scared', 'afraid', 'terrified'],
      ),
      'Wonder & Discovery': _ThemeBucket(
        emoji: '✨',
        description:
            'These dreams have an open, exploratory quality — magic, beauty, the unfamiliar. They often arrive when you are growing or shifting perspective, even quietly.',
        toneCues: ['whimsical', 'surreal', 'mythic', 'ancient'],
        textCues: ['discovered', 'magical', 'beautiful', 'glowing', 'shimmering', 'curious'],
      ),
      'Connection & Love': _ThemeBucket(
        emoji: '💗',
        description:
            'Dreams of reunion, warmth, or family usually reflect the relationships your mind is holding onto. Sometimes the message is gratitude; sometimes it is longing.',
        toneCues: ['romantic', 'nostalgic'],
        textCues: ['kissed', 'embrace', 'loved', 'together', 'reunited', 'family'],
      ),
      'Power & Adventure': _ThemeBucket(
        emoji: '⚡',
        description:
            'Heroic, decisive dreams often reflect a part of you that wants to take action. Pay attention to what you are fighting for — that is often what matters most to you right now.',
        toneCues: ['epic', 'heroic'],
        textCues: ['fought', 'won', 'rescued', 'climbed', 'battle', 'leader'],
      ),
      'Peace & Stillness': _ThemeBucket(
        emoji: '🌿',
        description:
            'Quiet, floating, serene dreams are themselves the message. They tend to surface when something difficult has begun to settle, or when your mind is making space.',
        toneCues: ['peaceful', 'gentle'],
        textCues: ['quiet', 'calm', 'still', 'floating', 'gentle', 'serene'],
      ),
      'Loss & Endings': _ThemeBucket(
        emoji: '🍂',
        description:
            'Dreams of death, goodbyes, or things slipping away rarely mean what they show literally. They usually mark a chapter ending — a role, habit, or relationship transforming.',
        toneCues: [],
        textCues: ['died', 'death', 'goodbye', 'gone', 'left me', 'lost', 'funeral', 'grief'],
      ),
      'Strange & Uncanny': _ThemeBucket(
        emoji: '🌀',
        description:
            'When things feel twisted, wrong, or familiar-but-off, your mind is often probing something it has not named yet. The strangeness is the signal — the discomfort is doing work.',
        toneCues: ['futuristic', 'uncanny', 'elegant', 'ornate'],
        textCues: ['strange', 'twisted', 'wrong', 'familiar but', 'shifted'],
      ),
    };

    for (final d in dreams) {
      final tone = d.tone.toLowerCase();
      final hay = _haystack(d);
      for (final entry in buckets.entries) {
        final bucket = entry.value;
        final toneMatch = bucket.toneCues.any((c) => tone.contains(c));
        final textMatch = bucket.textCues.any((c) => hay.contains(c));
        if (toneMatch || textMatch) {
          bucket.dreams.add(d);
        }
      }
    }

    final total = dreams.length;
    final results = <ThemeWeight>[];
    buckets.forEach((label, bucket) {
      if (bucket.dreams.isEmpty) return;
      results.add(ThemeWeight(
        label: label,
        emoji: bucket.emoji,
        description: bucket.description,
        weight: bucket.dreams.length / total,
        dreams: bucket.dreams,
      ));
    });

    results.sort((a, b) => b.weight.compareTo(a.weight));
    return results;
  }

  static List<ToneSlice> _toneSlices(List<Dream> dreams) {
    final counts = <String, int>{};
    for (final d in dreams) {
      final t = d.tone.trim();
      if (t.isEmpty) continue;
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const [];
    final slices = counts.entries
        .map((e) => ToneSlice(label: e.key, count: e.value, percent: e.value / total))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return slices;
  }

  // Patterns are derived from the symbol and theme results so we don't
  // re-tokenize the corpus. We look for:
  //   - top symbol that dominates the journal
  //   - co-occurrence of the top symbol with the top theme
  //   - recent activity ("X dreams in the last 7 days")
  //   - short streaks of the same dominant theme
  static List<PatternFinding> _findPatterns(
    List<Dream> dreams,
    List<SymbolHit> symbols,
    List<ThemeWeight> themes,
  ) {
    final findings = <PatternFinding>[];

    if (symbols.isNotEmpty) {
      final top = symbols.first;
      if (top.count >= 3) {
        findings.add(PatternFinding(
          headline: '${top.icon} ${top.name} appears in ${top.count} of your dreams.',
          detail:
              'This is your most recurring symbol. Notice when it shows up calm versus when it shows up overwhelming — the difference often carries the message.',
          dreams: top.dreams,
        ));
      }
    }

    if (symbols.isNotEmpty && themes.isNotEmpty) {
      final topSymbol = symbols.first;
      final topTheme = themes.first;
      final overlap = topSymbol.dreams
          .where((d) => topTheme.dreams.contains(d))
          .toList();
      if (overlap.length >= 2) {
        findings.add(PatternFinding(
          headline:
              '${topSymbol.name} tends to appear alongside ${topTheme.label.toLowerCase()}.',
          detail:
              'Out of ${topSymbol.count} dreams featuring ${topSymbol.name.toLowerCase()}, ${overlap.length} also carry the mood of ${topTheme.label.toLowerCase()}. The pairing may matter more than either one alone.',
          dreams: overlap,
        ));
      }
    }

    final now = DateTime.now();
    final recent =
        dreams.where((d) => now.difference(d.createdAt).inDays <= 7).toList();
    if (recent.length >= 3) {
      findings.add(PatternFinding(
        headline:
            'You logged ${recent.length} dreams in the last 7 days — your recall is sharpening.',
        detail:
            'Frequent recall is itself a pattern. The brain tends to surface recurring material once you start paying attention.',
        dreams: recent,
      ));
    }

    final streak = _longestThemeStreak(dreams, themes);
    if (streak != null && streak.length >= 3) {
      final label = streak.first.$1;
      final dreamsInStreak = streak.map((e) => e.$2).toList();
      findings.add(PatternFinding(
        headline:
            '${dreamsInStreak.length} dreams in a row carried the mood of ${label.toLowerCase()}.',
        detail:
            'Streaks like this often line up with something specific happening in waking life around that time.',
        dreams: dreamsInStreak,
      ));
    }

    return findings.take(_maxPatterns).toList();
  }

  // Walk dreams chronologically. For each dream, attach the top theme it belongs to
  // (if any). Find the longest consecutive run of the same theme.
  static List<(String, Dream)>? _longestThemeStreak(
    List<Dream> dreams,
    List<ThemeWeight> themes,
  ) {
    if (themes.isEmpty || dreams.length < 3) return null;

    final byDream = <int, String>{};
    for (final t in themes) {
      for (final d in t.dreams) {
        byDream.putIfAbsent(d.id, () => t.label);
      }
    }

    final sorted = [...dreams]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    List<(String, Dream)> best = [];
    List<(String, Dream)> current = [];
    String? currentLabel;

    for (final d in sorted) {
      final label = byDream[d.id];
      if (label == null) {
        current = [];
        currentLabel = null;
        continue;
      }
      if (label == currentLabel) {
        current.add((label, d));
      } else {
        current = [(label, d)];
        currentLabel = label;
      }
      if (current.length > best.length) {
        best = [...current];
      }
    }

    return best.isEmpty ? null : best;
  }
}

class _ThemeBucket {
  final String emoji;
  final String description;
  final List<String> toneCues;
  final List<String> textCues;
  final List<Dream> dreams = [];

  _ThemeBucket({
    required this.emoji,
    required this.description,
    required this.toneCues,
    required this.textCues,
  });
}
