// services/notification_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart' as os;
import 'package:permission_handler/permission_handler.dart';

import 'package:dreamr/services/notification_messages.dart'; // NEW
import 'package:dreamr/services/api_service.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  // ===== Config =====
  static const String _oneSignalAppId = 'YOUR-ONESIGNAL-APP-ID';
  static const int _dailyReminderId = 1001;
  static const int _creditUpdateId = 2001;
  static const String _channelId = 'dreamr_daily';
  static const String _channelName = 'Daily Reminders';
  static const String _channelDesc = 'Daily Dreamr reminder notifications';

  // Pref keys
  static const _kNotifHour = 'notification_hour';
  static const _kNotifMin = 'notification_minute';
  static const _kNotifEnabled = 'enable_notifications';
  static const _kReminderEnabled = 'reminder_enabled';
  static const _kHasSetNotifs = 'has_set_notifications';
  static const _kRotationIdx = 'notif_rotation_idx';

  // Usage snapshot keys (persist for background scheduling)
  static const _kUserDisplayName = 'usage_display_name';
  static const _kStreakDays = 'usage_streak_days';
  static const _kLastLogEpochMs = 'usage_last_log_epoch_ms';

  // ===== Constants =====
  static const int _weeklyReminderId = 1002;
  static const int _inactive2Id = 2002;
  static const int _inactive4Id = 2004;
  static const int _inactive7Id = 2007;
  static const int _creditResetNotifId = 3001;

  // ===== State =====
  bool _isInitialized = false;
  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

  // ===== Public API =====
// Initialize notification service (idempotent).
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      tzdata.initializeTimeZones();
      final String tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _fln.initialize(initSettings, onDidReceiveNotificationResponse: _onTapLocalNotification);

    final android = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'dreamr_daily',
      'Daily Reminders',
      description: 'Daily reminder to log dreams',
      importance: Importance.max,
      enableLights: true,
      playSound: true,
      enableVibration: true,
    ));

    _isInitialized = true;
    await _enableNotificationsByDefault();
  }

/// Store a snapshot of user data for use in background notification scheduling.
  Future<void> setUsageSnapshot({
    required String? displayName,
    required int? streakDays,
    required DateTime? lastLogUtc,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (displayName != null) {
      await prefs.setString(_kUserDisplayName, displayName);
    }
    if (streakDays != null) {
      await prefs.setInt(_kStreakDays, streakDays);
    }
    if (lastLogUtc != null) {
      await prefs.setInt(_kLastLogEpochMs, lastLogUtc.millisecondsSinceEpoch);
    }
  }

/// Request notification permissions from the user.
  Future<bool> requestPermissions() async {
    await init();
    final status = await Permission.notification.request();
    bool androidGranted = status.isGranted;

    bool iosGranted = true;
    final ios = _fln.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      iosGranted = await ios.requestPermissions(alert: true, badge: true, sound: true) ?? true;
    }
    return iosGranted && androidGranted;
  }

/// Enable or disable notifications and schedule/cancel reminders accordingly.
  Future<void> toggleNotifications(bool enable) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, enable);

    if (enable) {
      final granted = await requestPermissions();
      if (!granted) return;
      final t = await getNotificationTime();
      await scheduleMorningReminder(t);
      await prefs.setBool(_kReminderEnabled, true);
    } else {
      await cancelMorningReminder();
      await prefs.setBool(_kReminderEnabled, false);
    }

    if (_usingOneSignal) {
      try {
        if (enable) {
          os.OneSignal.login(await _deviceKey());
        } else {
          os.OneSignal.logout();
        }
      } catch (_) {}
    }
  }

/// Get current notification enabled setting.
  Future<bool> getNotificationSetting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNotifEnabled) ?? false;
  }

/// Get the currently scheduled notification time.
  Future<TimeOfDay> getNotificationTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_kNotifHour) ?? 8;
    final minute = prefs.getInt(_kNotifMin) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

/// Set the notification time and reschedule the daily reminder if enabled.
  Future<void> setNotificationTime(TimeOfDay time) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNotifHour, time.hour);
    await prefs.setInt(_kNotifMin, time.minute);
    if (await getNotificationSetting()) {
      await scheduleMorningReminder(time);
    }
  }

/// Schedule or reschedule the daily reminder at the specified local time.
  Future<void> scheduleMorningReminder(TimeOfDay time) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNotifHour, time.hour);
    await prefs.setInt(_kNotifMin, time.minute);

    const String dailyChannelId = 'dreamr_daily_reminder';
    final android = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      dailyChannelId,
      'Daily Dream Reminders',
      description: 'Daily reminder to log your dreams',
      importance: Importance.max,
      enableLights: true,
      playSound: true,
      enableVibration: true,
    ));

    // Build personalized body (fallback to generic rotation).
    final msg = await _buildDailyMessage(prefs);

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        dailyChannelId,
        'Daily Dream Reminders',
        channelDescription: 'Daily reminder to log your dreams',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        playSound: true,
        fullScreenIntent: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'dreamr.daily',
      ),
    );

    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {}

    final first = _nextInstance(time);
    await _fln.zonedSchedule(
      _dailyReminderId,
      msg.title,
      msg.body,
      first,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_reminder',
    );

    // Advance rotation index for next day
    final nextIdx = (prefs.getInt(_kRotationIdx) ?? 0) + 1;
    await prefs.setInt(_kRotationIdx, nextIdx);
  }

/// Cancel the scheduled daily reminder.
  Future<void> cancelMorningReminder() async {
    await init();
    await _fln.cancel(_dailyReminderId);
  }

  /// Send an immediate daily-style notification (generic rotation)
  /// so the user can test how the daily reminder looks without waiting for the
  /// scheduled time.
  Future<void> sendDailyTestNow() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    // Ensure permissions (no-op if already granted)
    await requestPermissions();

    const String dailyChannelId = 'dreamr_daily_reminder';
    final android = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      dailyChannelId,
      'Daily Dream Reminders',
      description: 'Daily reminder to log your dreams',
      importance: Importance.max,
      enableLights: true,
      playSound: true,
      enableVibration: true,
    ));

    final msg = await _buildDailyMessage(prefs);
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        dailyChannelId,
        'Daily Dream Reminders',
        channelDescription: 'Daily reminder to log your dreams',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        playSound: true,
        fullScreenIntent: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'dreamr.daily',
      ),
    );

    await _fln.show(
      9971,
      msg.title,
      msg.body,
      details,
      payload: 'daily_test_now',
    );
  }


  /// Send a notification informing the user of new dream credits added.
  Future<void> sendCreditUpdateNotification(int creditCount) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kNotifEnabled) ?? false;
    if (!enabled) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _fln.show(
      _creditUpdateId,
      'New dream credits',
      '$creditCount credits added to your account.',
      details,
      payload: 'credit_update',
    );

    await prefs.setInt('last_credit_update', DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt('last_credit_amount', creditCount);
  }

  // ===== Debug/Test helpers (kept but disabled in release) =====
  // Wrap in kDebugMode so they never run in release builds.

  /// Show an immediate test notification to verify that notifications work.
  Future<void> showNowTest() async {
    if (!kDebugMode) return;
    await init();
    const String channelId = 'dreamr_test';
    final android = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelId, 'Test Notifications', description: 'Test notifications',
      importance: Importance.max, enableLights: true, playSound: true,
    ));
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(channelId, 'Test Notifications',
          channelDescription: 'Test notifications',
          importance: Importance.max, priority: Priority.max),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
    );
    await _fln.show(9999, 'Test', 'If you see this, notifications work.', details);
  }

/// Schedule a test notification after the specified delay.
  Future<void> scheduleTestExactNotification(Duration delay) async {
    if (!kDebugMode) return;
    await init();
    const String testChannelId = 'dreamr_test_exact';
    final android = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      testChannelId, 'Test Notifications',
      description: 'High priority exact test notifications',
      importance: Importance.max, enableLights: true, playSound: true, enableVibration: true,
    ));
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        testChannelId, 'Test Notifications',
        channelDescription: 'High priority exact test notifications',
        importance: Importance.max, priority: Priority.max,
        category: AndroidNotificationCategory.alarm, visibility: NotificationVisibility.public, playSound: true,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
    );
    final when = tz.TZDateTime.now(tz.local).add(delay);
    await _fln.zonedSchedule(
      4343, 'Scheduled system notification',
      'This notification was scheduled ${delay.inSeconds}s ago via system alarm',
      when, details,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: Platform.isAndroid
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'scheduled_test',
    );
  }

/// Dump pending notifications to debug console.
  Future<void> debugDumpNotifications() async {
    if (!kDebugMode) return;
    await init();
    final pending = await _fln.pendingNotificationRequests();
    debugPrint('Pending notifications: ${pending.length}');
    for (final p in pending) {
      debugPrint('id=${p.id} title=${p.title} body=${p.body}');
    }
  }

  /// Schedule a weekly reminder at the specified time and weekday.
  Future<void> scheduleWeeklyReminder({
    required TimeOfDay time,
    int weekday = DateTime.sunday, // 1=Mon … 7=Sun
    String body = "Weekly check-in: reflect on this week’s dreams and add today’s.",
  }) async {
    await init();

    const channelId = 'dreamr_weekly_reminder';
    final android = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      'Weekly Dream Reminders',
      description: 'Weekly reminder to log your dreams',
      importance: Importance.max,
      enableLights: true,
      playSound: true,
      enableVibration: true,
    ));

    // Find the next occurrence of the requested weekday at the chosen time
    tz.TZDateTime target = _nextInstance(time);
    while (target.weekday != weekday) {
      target = target.add(const Duration(days: 1));
    }

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        channelId, 'Weekly Dream Reminders',
        channelDescription: 'Weekly reminder to log your dreams',
        importance: Importance.max, priority: Priority.max,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public, playSound: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true, presentBadge: true, presentSound: true,
        threadIdentifier: 'dreamr.weekly',
      ),
    );

    await _fln.zonedSchedule(
      _weeklyReminderId,
      "Weekly Dreamr check-in",
      body,
      target,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // repeats weekly
      payload: 'weekly_reminder',
    );
  }

  /// Schedule a Sunday credit-reset reminder for free users who are below their 2-credit limit.
  Future<void> scheduleCreditResetReminder(TimeOfDay time) async {
    await init();

    // Check subscription — skip for paid users or those already at full credits
    try {
      final status = await ApiService.getSubscriptionStatus();
      final isPaid = status.tier != 'free';
      final credits = status.totalCredits;
      if (isPaid || credits >= 2) return;
    } catch (_) {
      return; // If we can't check, don't send
    }

    const channelId = 'dreamr_credit_reset';
    final android = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      'Credit Reset Reminders',
      description: 'Weekly notification when free dream credits reset',
      importance: Importance.high,
      enableLights: true,
      playSound: true,
    ));

    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId, 'Credit Reset Reminders',
        channelDescription: 'Weekly notification when free dream credits reset',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'dreamr.credit_reset',
      ),
    );

    // Find next Sunday at the requested time
    tz.TZDateTime target = _nextInstance(time);
    while (target.weekday != DateTime.sunday) {
      target = target.add(const Duration(days: 1));
    }

    await _fln.zonedSchedule(
      _creditResetNotifId,
      'Your dream credits are back!',
      'You have 2 free dream analyses this week. Open Dreamr and record last night\'s dream.',
      target,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // repeats every Sunday
      payload: 'credit_reset',
    );
  }

/// Cancel the scheduled weekly reminder.
  Future<void> scheduleInactivityNudges({TimeOfDay fireTime = const TimeOfDay(hour: 9, minute: 0)}) async {
    await init();
    final prefs = await SharedPreferences.getInstance();

    // Get snapshot (fall back if missing)
    final name = (prefs.getString(_kUserDisplayName) ?? '').trim();
    final streakDays = prefs.getInt(_kStreakDays);
    final lastLogMs = prefs.getInt(_kLastLogEpochMs);
    final lastLogUtc = (lastLogMs != null) ? DateTime.fromMillisecondsSinceEpoch(lastLogMs, isUtc: true) : null;

    // Nothing to schedule without a known last-log moment
    if (lastLogUtc == null) return;

    // Helper to schedule a one-shot at lastLog + N days @ local fireTime
    Future<void> _one(int id, int days, String body) async {
      final localBase = tz.TZDateTime.from(lastLogUtc, tz.local);
      final scheduled = tz.TZDateTime(
        tz.local,
        localBase.year, localBase.month, localBase.day,
        fireTime.hour, fireTime.minute,
      ).add(Duration(days: days));

      // Skip if in the past
      if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

      final details = NotificationDetails(
        android: const AndroidNotificationDetails(
          'dreamr_inactive', 'Inactivity Nudges',
          channelDescription: 'Gentle nudges when you haven’t logged a dream',
          importance: Importance.high, priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public, playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
          threadIdentifier: 'dreamr.inactive',
        ),
      );

      await _fln.zonedSchedule(
        id,
        'Dreamr reminder',
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'inactive_nudge_$days',
      );
    }

    // Build bodies using your personalization helper (at schedule time)
    String? who = name.isEmpty ? null : name;
    String p2 = NotificationMessages.personalized(displayName: who, streakDays: streakDays, daysSinceLast: 2);
    String p4 = NotificationMessages.personalized(displayName: who, streakDays: streakDays, daysSinceLast: 4);
    String p7 = NotificationMessages.personalized(displayName: who, streakDays: streakDays, daysSinceLast: 7);

    await _one(_inactive2Id, 2, p2);
    await _one(_inactive4Id, 4, p4);
    await _one(_inactive7Id, 7, p7);
  }

/// Reschedule all notifications on user login with latest data.
  Future<void> rescheduleAllOnLogin({
    required String? displayName,
    required int? streakDays,
    required DateTime? lastLogUtc,
    TimeOfDay dailyTime = const TimeOfDay(hour: 8, minute: 0),
    int weeklyWeekday = DateTime.sunday,
  }) async {
    await init();
    final prefs = await SharedPreferences.getInstance();

    // Persist latest usage snapshot (used by message builders)
    await setUsageSnapshot(
      displayName: displayName,
      streakDays: streakDays,
      lastLogUtc: lastLogUtc,
    );

    // Respect user toggle
    final enabled = prefs.getBool(_kNotifEnabled) ?? false;
    if (!enabled) return;

    // Clear known scheduled items (don’t wipe unrelated notifications)
    await _fln.cancel(_dailyReminderId);
    await _fln.cancel(_weeklyReminderId);
    await _fln.cancel(_inactive2Id);
    await _fln.cancel(_inactive4Id);
    await _fln.cancel(_inactive7Id);
    await _fln.cancel(_creditResetNotifId);

    // Rebuild
    await scheduleMorningReminder(dailyTime);
    await scheduleWeeklyReminder(time: const TimeOfDay(hour: 9, minute: 0), weekday: weeklyWeekday);
    await scheduleInactivityNudges();
    await scheduleCreditResetReminder(dailyTime);

    // Optional: streak encouragement tomorrow 8:00 if streak >= 2
    if ((streakDays ?? 0) >= 2) {
      final when = _nextInstance(const TimeOfDay(hour: 8, minute: 0)).add(const Duration(days: 1));
      final details = NotificationDetails(
        android: const AndroidNotificationDetails(
          'dreamr_streaks', 'Streak Encouragement',
          channelDescription: 'Motivational streak reminders',
          importance: Importance.high, priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true, threadIdentifier: 'dreamr.streak',
        ),
      );
      final body = "Nice work${displayName != null && displayName.trim().isNotEmpty ? ", ${displayName.trim()}" : ""} — "
                  "you’re on a ${(streakDays ?? 0)}-day streak. Log today’s dream.";
      await _fln.zonedSchedule(
        3000, 'Keep your streak going', body, when, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'streak_nudge',
      );
    }
  }



  // ===== Helpers =====
  bool get _usingOneSignal =>
      _oneSignalAppId.isNotEmpty && _oneSignalAppId != 'YOUR-ONESIGNAL-APP-ID';

  tz.TZDateTime _nextInstance(TimeOfDay t) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<String> _deviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('onesignal_key');
    if (id == null) {
      id = 'anon-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('onesignal_key', id);
    }
    return id;
  }

  void _onTapLocalNotification(NotificationResponse r) {
    // Deep links if desired
  }

  // Build the daily reminder title/body pair for today.
  Future<NotificationLine> _buildDailyMessage(SharedPreferences prefs) async {
    // Get cached display name, or fetch from API and cache it.
    final displayName = await _getOrFetchDisplayName(prefs);

    // Use your deterministic picker + name injection.
    return NotificationMessages.pickForTodayPersonalized(
      DateTime.now(),
      displayName,
    );
  }


  /// Get display name from prefs; if missing, fetch from API and cache for personalization.
  Future<String?> _getOrFetchDisplayName(SharedPreferences prefs) async {
    final cached = prefs.getString(_kUserDisplayName);
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.trim();
    }
    try {
      final profile = await ApiService.getProfile();
      final first = (profile['first_name']?.toString() ?? '').trim();
      if (first.isNotEmpty) {
        await prefs.setString(_kUserDisplayName, first);
        return first;
      }
    } catch (_) {
      // Ignore fetch errors; fall back to default in message builder
    }
    return null;
  }
  /// Public helper to access the current cached (or freshly fetched) display name.
  Future<String?> getCachedDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return _getOrFetchDisplayName(prefs);
  }

/// Enable notifications by default on first run based on permission status.
  Future<void> _enableNotificationsByDefault() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSet = prefs.getBool(_kHasSetNotifs) ?? false;
    if (hasSet) return;

    final granted = await requestPermissions();
    if (granted) {
      await prefs.setBool(_kNotifEnabled, true);
      await prefs.setBool(_kReminderEnabled, true);
      await scheduleMorningReminder(const TimeOfDay(hour: 8, minute: 0));
    } else {
      await prefs.setBool(_kNotifEnabled, false);
      await prefs.setBool(_kReminderEnabled, false);
    }
    await prefs.setBool(_kHasSetNotifs, true);
  }
}
