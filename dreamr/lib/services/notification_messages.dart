// services/notification_messages.dart
import 'dart:math';

class NotificationLine {
  final String title;
  final String body;
  const NotificationLine({required this.title, required this.body});
}

class NotificationMessages {
  // Replace the literal placeholder `$name` with the user display name.
  static NotificationLine _withName(
    NotificationLine line,
    String? displayName,
  ) {
    final name = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : 'there';

    return NotificationLine(
      title: line.title.replaceAll('\$name', name),
      body: line.body.replaceAll('\$name', name),
    );
  }

  static NotificationLine pickForTodayPersonalized(
    DateTime localNow,
    String? displayName,
  ) {
    final base = pickForToday(localNow);
    return _withName(base, displayName);
  }

  static NotificationLine pickByIndexPersonalized(
    int idx,
    String? displayName,
  ) {
    final base = pickByIndex(idx);
    return _withName(base, displayName);
  }

  static NotificationLine pickRandomPersonalized(String? displayName) {
    final base = pickRandom();
    return _withName(base, displayName);
  }

  /// Generic morning messages — each is a (title, body) pair.
  static const List<NotificationLine> generic = [
    NotificationLine(
      title: 'Record last night\'s dream',
      body: 'Take a minute to jot down what you remember.',
    ),
    NotificationLine(
      title: 'Before it fades',
      body: 'Write a quick line before the details blur.',
    ),
    NotificationLine(
      title: 'Good morning \$name',
      body: 'Capture one image or feeling from last night.',
    ),
    NotificationLine(
      title: 'Morning dream check-in',
      body: 'Open Dreamr and add today\'s entry.',
    ),
    NotificationLine(
      title: 'Your story continues',
      body: 'Each dream is a page—add today\'s page.',
    ),
    NotificationLine(
      title: 'How did you sleep, \$name?',
      body: 'Dream fragments matter. Write what you recall.',
    ),
    NotificationLine(
      title: 'Preserve the feeling',
      body: 'Note the emotion, even if the plot is fuzzy.',
    ),
    NotificationLine(
      title: 'Dreams don\'t last',
      body: 'One sentence now keeps this dream alive.',
    ),
    NotificationLine(
      title: 'Quick dream check',
      body: 'Spend 30 seconds writing last night\'s story.',
    ),
    NotificationLine(
      title: 'Dreamr reminder',
      body: 'Add today\'s dream before the day takes over.',
    ),
    NotificationLine(
      title: 'Did you dream, \$name?',
      body: 'Your subconscious spoke. Capture its message.',
    ),
    NotificationLine(
      title: 'Rise and shine, \$name',
      body: 'Add one more dream to your journal today.',
    ),
    NotificationLine(
      title: 'Dream journal moment',
      body: 'Open Dreamr and write what still lingers.',
    ),
    NotificationLine(
      title: 'Morning reflection',
      body: 'Start your day by recording last night\'s dream.',
    ),
    NotificationLine(
      title: 'Hold onto this one',
      body: 'Write a quick note before this dream disappears.',
    ),
    NotificationLine(
      title: 'Dreamr daily nudge',
      body: 'Capture your dream in a few short lines.',
    ),
    NotificationLine(
      title: 'Your inner story',
      body: 'Each entry reveals more of you. Add today\'s.',
    ),
    NotificationLine(
      title: 'Dreams fade fast',
      body: 'Log what you remember while it\'s still clear.',
    ),
    NotificationLine(
      title: 'Just one detail',
      body: 'Write a single image, scene, or feeling.',
    ),
    NotificationLine(
      title: 'Make it a ritual',
      body: 'Wake, reflect, record—start with your dream.',
    ),
    NotificationLine(
      title: 'Mindful morning',
      body: 'A short dream entry can ground your day.',
    ),
    NotificationLine(
      title: 'Time to wake up, \$name',
      body: 'Turn last night\'s dream into today\'s insight.',
    ),
    NotificationLine(
      title: 'Don\'t lose the thread',
      body: 'Write your dream before your coffee cools.',
    ),
    NotificationLine(
      title: 'Dreamr is ready',
      body: 'Open the app and add last night\'s chapter.',
    ),
    NotificationLine(
      title: 'Honor your dream',
      body: 'Give it a place in your journal, not just memory.',
    ),
    NotificationLine(
      title: 'Tiny entry, big payoff',
      body: 'Even one line can matter weeks from now.',
    ),
    NotificationLine(
      title: 'Morning check-in',
      body: 'Your inner self spoke. Capture a few words.',
    ),
    NotificationLine(
      title: 'Dream streak check',
      body: 'Keep the habit alive with today\'s entry.',
    ),
    NotificationLine(
      title: 'You awake, \$name?',
      body: 'Foggy dream? Write the first thing you recall.',
    ),
    NotificationLine(
      title: 'Between sleep and sunrise',
      body: 'Describe whatever still stands out to you.',
    ),
    NotificationLine(
      title: 'Rise and shine, \$name',
      body: 'Log your thoughts where only you can see them.',
    ),
    NotificationLine(
      title: 'Dreams are clues',
      body: 'Treat last night as a clue—record what happened.',
    ),
    NotificationLine(
      title: 'Start with a feeling',
      body: 'Happy, scared, confused—write how you woke up.',
    ),
    NotificationLine(
      title: 'Morning \$name',
      body: 'Dream recall improves with practice. Keep going.',
    ),
    NotificationLine(
      title: 'Quick journal check',
      body: 'Open Dreamr and add one more dream today.',
    ),
    NotificationLine(
      title: 'Don\'t skip today',
      body: 'A tiny entry is better than none at all.',
    ),
    NotificationLine(
      title: 'Time to wake up, \$name',
      body: 'Let last night inspire a few written lines.',
    ),
    NotificationLine(
      title: 'Connect the dots',
      body: 'Today\'s dream might link to older entries—log it.',
    ),
    NotificationLine(
      title: 'Your dream, your data',
      body: 'Record it now so you can explore patterns later.',
    ),
    NotificationLine(
      title: 'Hello \$name',
      body: 'Bring last night\'s story into your journal.',
    ),
    NotificationLine(
      title: 'Soft nudge from Dreamr',
      body: 'Take a quiet moment to write your dream.',
    ),
    NotificationLine(
      title: 'How did you sleep, \$name?',
      body: 'Turn last night\'s images into a short note.',
    ),
    NotificationLine(
      title: 'Reflect before scrolling',
      body: 'Pause the feed and write your dream first.',
    ),
    NotificationLine(
      title: 'Stay consistent',
      body: 'Your journal grows one morning at a time.',
    ),
    NotificationLine(
      title: 'Today\'s tiny ritual',
      body: 'Thirty seconds of writing keeps this dream alive.',
    ),
    NotificationLine(
      title: 'Dream journal check-in',
      body: 'Add whatever is left in your mind from last night.',
    ),
    NotificationLine(
      title: 'Subconscious recap',
      body: 'Your night brain was busy—write its highlight.',
    ),
  ];

  // --- Monthly deterministic shuffle (no repeats within a month) ---
  static int _gcd(int a, int b) => b == 0 ? a.abs() : _gcd(b, a % b);

  // Pick a step that’s coprime with N so we walk the list without repeats.
  static int _coprimeStep(int n, int seed) {
    int s = (seed | 1) % n; // make it odd and within range
    if (s == 0) s = 1;
    while (_gcd(s, n) != 1) {
      s = (s + 2) % n;
      if (s == 0) s = 1;
    }
    return s;
  }

  // Deterministic index for this month/day using a full-cycle permutation.
  static int indexForMonthDay(DateTime localNow) {
    final n = generic.length;
    if (n == 0) return 0;

    final year = localNow.year;
    final month = localNow.month;    // 1..12
    final dayIdx = localNow.day - 1; // 0-based day within month

    final seed = year * 131 + month * 37;
    final offset = (seed * 73) % n;
    final step = _coprimeStep(n, seed * 97);

    return (offset + dayIdx * step) % n;
  }

  static NotificationLine pickForToday(DateTime localNow) =>
      generic[indexForMonthDay(localNow)];

  static NotificationLine pickForTodayWithOffset(DateTime localNow, int offsetAdj) {
    final n = generic.length;
    if (n == 0) {
      return const NotificationLine(
        title: 'Dreamr reminder',
        body: 'Open Dreamr and write last night\'s dream.',
      );
    }
    final base = indexForMonthDay(localNow);
    return generic[(base + offsetAdj) % n];
  }

  static NotificationLine pickByIndex(int idx) {
    if (generic.isEmpty) {
      return const NotificationLine(
        title: 'Dreamr reminder',
        body: 'Record last night\'s dream in your journal.',
      );
    }
    return generic[idx % generic.length];
  }

  static NotificationLine pickRandom() {
    if (generic.isEmpty) {
      return const NotificationLine(
        title: 'Dreamr reminder',
        body: 'Write a quick note about last night\'s dream.',
      );
    }
    return generic[Random().nextInt(generic.length)];
  }

  /// Inactivity nudges: short title/body based on days since last entry.
  static NotificationLine inactivityMessage({
    required String? displayName,
    required int? streakDays,
    required int daysSinceLast,
  }) {
    final name = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : 'there';

    if (daysSinceLast >= 7) {
      return NotificationLine(
        title: 'We miss your dreams',
        body: 'Hey $name, drop in with a quick entry today.',
      );
    }
    if (daysSinceLast >= 4) {
      return NotificationLine(
        title: 'It’s been a few days',
        body: 'Write a short note about your last dream.',
      );
    }
    if (daysSinceLast >= 2) {
      return NotificationLine(
        title: 'Dreams are waiting',
        body: 'Take a minute to log last night’s dream.',
      );
    }

    // Fallback if called with small gaps.
    return NotificationLine(
      title: 'Check in with Dreamr',
      body: 'Write a quick line about your latest dream.',
    );
  }

  /// Weekly reminder: gentle weekly check-in.
  static NotificationLine weeklyMessage({
    required String? displayName,
    required int? streakDays,
  }) {
    final name = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : null;
    final streak = streakDays ?? 0;

    if (streak >= 5 && name != null) {
      return NotificationLine(
        title: 'Weekly dream check-in',
        body: '$name, keep your streak alive with today’s dream.',
      );
    }

    return const NotificationLine(
      title: 'Weekly dream reflection',
      body: 'Look back on this week and log today’s dream.',
    );
  }

  /// Streak encouragement notification.
  static NotificationLine streakMessage({
    required String? displayName,
    required int streakDays,
  }) {
    final name = (displayName?.trim().isNotEmpty == true)
        ? displayName!.trim()
        : null;

    if (streakDays >= 10) {
      return NotificationLine(
        title: name != null ? 'Amazing streak, $name!' : 'Amazing dream streak!',
        body: '$streakDays days in a row—log today’s dream.',
      );
    }
    if (streakDays >= 5) {
      return NotificationLine(
        title: name != null ? 'Nice streak, $name' : 'Nice dream streak',
        body: '$streakDays days so far—add today’s dream.',
      );
    }
    // 2–4 days
    return NotificationLine(
      title: 'You’re on a roll',
      body: 'Another entry today can turn this into a habit.',
    );
  }

  /// (Optional) keep this if used elsewhere, or delete if not needed.
  static String personalized({
    required String? displayName,
    required int? streakDays,
    required int? daysSinceLast,
  }) {
    return inactivityMessage(
      displayName: displayName,
      streakDays: streakDays,
      daysSinceLast: daysSinceLast ?? 0,
    ).body;
  }


  /// Personalized line based on usage signals (used for inactivity nudges).
  // static String personalized({
  //   required String? displayName,
  //   required int? streakDays,
  //   required int? daysSinceLast,
  // }) {
  //   final name = (displayName?.trim().isNotEmpty == true)
  //       ? displayName!.trim()
  //       : 'there';

  //   if (daysSinceLast != null && daysSinceLast >= 7) {
  //     return 'Hey $name, it\'s been a while since your last dream entry. Even a few words can keep your reflection going.';
  //   }
  //   if (daysSinceLast != null && daysSinceLast >= 4) {
  //     return 'Hey $name, it\'s been $daysSinceLast days since your last entry. Write what you remember—even fragments matter.';
  //   }
  //   if (daysSinceLast != null && daysSinceLast >= 2) {
  //     return 'Welcome back, $name. It\'s been a few days—take a moment to record last night\'s dream.';
  //   }

  //   if ((streakDays ?? 0) >= 10) {
  //     return 'Incredible, $name — $streakDays days in a row! Keep your dream practice alive with today\'s entry.';
  //   }
  //   if ((streakDays ?? 0) >= 5) {
  //     return 'Nice work, $name — you\'re on a $streakDays-day streak. Keep the momentum and log today\'s dream.';
  //   }
  //   if ((streakDays ?? 0) >= 3) {
  //     return 'You\'re building a great habit, $name. Add another dream to your journal today.';
  //   }
  //   if ((streakDays ?? 0) == 2) {
  //     return 'You\'re on a roll, $name. A third day in a row can turn this into a lasting habit.';
  //   }

  //   return 'Good morning, $name. Take a moment to write down last night\'s dream before the day begins.';
  // }
}
