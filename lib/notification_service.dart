import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  NotificationService._init();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId   = 'scoopy_alarm_channel';
  static const _channelName = 'Scoopy Alarm';
  static const _notifId     = 1001;

  Future<void> init() async {
    // Init timezone — needed for zonedSchedule
    try {
      tz_data.initializeTimeZones();
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
      debugPrint('Timezone set: ${localTz.identifier}');
    } catch (e) {
      debugPrint('Timezone init failed: $e');
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: _onTap,
    );

    // Create channel — required for Android 8+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Scoopy cleaning alarm notifications',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

    debugPrint('NotificationService init OK');
  }

  @pragma('vm:entry-point')
  static void _onTap(NotificationResponse details) {
    debugPrint('Notification tapped: ${details.payload}');
  }

  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? ap =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (ap == null) return;
    try {
      final bool? granted = await ap.requestNotificationsPermission();
      debugPrint('POST_NOTIFICATIONS granted: $granted');
    } catch (e) {
      debugPrint('Notification permission failed: $e');
    }
    try {
      final bool? canSchedule = await ap.canScheduleExactNotifications();
      if (canSchedule == false) await ap.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('Exact alarm permission failed: $e');
    }
  }

  // ── Schedule OS-level alarm — fires even when app is minimized/killed ──────
  // Call this when the user taps SET REMINDER.
  // The OS delivers the notification at exactly targetTime regardless of
  // whether the app is open, minimized, or in the background.
  Future<void> scheduleAlarm(DateTime targetTime) async {
    await _plugin.cancel(id: _notifId); // cancel any previous

    final tz.TZDateTime scheduledDate =
        tz.TZDateTime.from(targetTime, tz.local);

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Scoopy cleaning alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarmsound'),
      enableVibration: true,
      icon: '@mipmap/launcher_icon',
      fullScreenIntent: true,
    );

    await _plugin.zonedSchedule(
      id: _notifId,
      title: '🧹 Cleaning Time!',
      body: 'Your scheduled cleaning session is starting now!',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'cleaning_alarm',
    );

    debugPrint('OS alarm scheduled for $targetTime');
  }

  // ── Cancel the OS alarm (e.g. user cancels the reminder) ──────────────────
  Future<void> cancelAlarm() async {
    await _plugin.cancel(id: _notifId);
    debugPrint('OS alarm cancelled');
  }

  // ── Show immediate notification — used by ReminderScreen when app is open ──
  // The _tick() in ReminderScreen still fires this when the app is in
  // foreground, giving the in-app heads-up alongside the OS alarm.
  Future<void> showAlarmNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Scoopy cleaning alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false, // sound handled by AudioPlayer in ReminderScreen
      enableVibration: true,
      icon: '@mipmap/launcher_icon',
    );
    await _plugin.show(
      id: _notifId,
      title: '🧹 Cleaning Time!',
      body: 'Your scheduled cleaning session is starting now!',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: 'cleaning_alarm',
    );
    debugPrint('showAlarmNotification() done');
  }
}