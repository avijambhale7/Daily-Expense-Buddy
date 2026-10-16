import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/logging/app_logger.dart';
import '../../domain/services/reminder_planner.dart';
import 'notification_service.dart';

/// [NotificationService] backed by `flutter_local_notifications`.
///
/// * Android/iOS: reminders are scheduled with the OS using
///   `zonedSchedule` in **inexact** mode. Android may delay delivery for
///   battery optimisation (Doze), so times are approximate.
/// * Web: browsers cannot schedule notifications for a closed tab without a
///   push service. While the app is open, reminders due today are shown via
///   in-session timers and the Notification API (permission required).
class LocalNotificationService implements NotificationService {
  LocalNotificationService();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  final List<Timer> _webTimers = [];
  bool _initialized = false;
  bool _webInitialized = false;
  String? _launchRoute;

  /// Custom chime in android/app/src/main/res/raw. Android fixes a channel's
  /// sound when it is created, so the channel ids carry a version.
  static const _chime = RawResourceAndroidNotificationSound('reminder_chime');
  static const _oldChannelIds = ['daily_reminders', 'budget_alerts'];

  static const _remindersChannel = AndroidNotificationDetails(
    'daily_reminders_v2',
    'Daily reminders',
    channelDescription: 'Reminders to record your daily expenses',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_stat_wallet',
    category: AndroidNotificationCategory.reminder,
    sound: _chime,
    playSound: true,
  );

  static const _alertsChannel = AndroidNotificationDetails(
    'budget_alerts_v2',
    'Budget alerts',
    channelDescription: 'Alerts when spending reaches a budget threshold',
    importance: Importance.defaultImportance,
    icon: 'ic_stat_wallet',
    sound: _chime,
    playSound: true,
  );

  @override
  ReminderCapability get capability {
    if (kIsWeb) {
      return WebFlutterLocalNotificationsPlugin.isSupported
          ? ReminderCapability.whileOpen
          : ReminderCapability.unsupported;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return ReminderCapability.scheduled;
      default:
        return ReminderCapability.unsupported;
    }
  }

  @override
  Stream<String> get taps => _taps.stream;

  @override
  String? takeLaunchRoute() {
    final r = _launchRoute;
    _launchRoute = null;
    return r;
  }

  void _onResponse(NotificationResponse response) {
    final route = response.payload;
    if (route != null && route.startsWith('/')) _taps.add(route);
  }

  @override
  Future<void> initialize() async {
    if (_initialized || capability == ReminderCapability.unsupported) return;
    // On web, initialising registers the plugin's service worker; defer that
    // until the user enables reminders (see [_ensureWeb]).
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (e) {
        AppLogger.warn('Notifications', 'Falling back to UTC time zone', e);
        tz.setLocalLocation(tz.UTC);
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_wallet'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final route = launch!.notificationResponse?.payload;
        if (route != null && route.startsWith('/')) _launchRoute = route;
      }
      _initialized = true;
      // Remove the pre-chime channels so they don't linger in system settings.
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      for (final id in _oldChannelIds) {
        await android?.deleteNotificationChannel(channelId: id);
      }
    } catch (e, st) {
      AppLogger.error('Notifications', 'Initialisation failed', e, st);
    }
  }

  Future<WebFlutterLocalNotificationsPlugin?> _ensureWeb() async {
    final web = _plugin
        .resolvePlatformSpecificImplementation<
          WebFlutterLocalNotificationsPlugin
        >();
    if (web == null) return null;
    if (!_webInitialized) {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          web: WebInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      _webInitialized = ok ?? false;
    }
    return _webInitialized ? web : null;
  }

  @override
  Future<bool> hasPermission() async {
    try {
      if (kIsWeb) {
        if (!WebFlutterLocalNotificationsPlugin.isSupported) return false;
        final web = _plugin
            .resolvePlatformSpecificImplementation<
              WebFlutterLocalNotificationsPlugin
            >();
        return web?.permissionStatus == WebNotificationPermission.granted;
      }
      await initialize();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final opts = await ios.checkPermissions();
        return opts?.isEnabled ?? false;
      }
    } catch (e) {
      AppLogger.warn('Notifications', 'Permission check failed', e);
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) {
        final web = await _ensureWeb();
        return await web?.requestNotificationsPermission() ?? false;
      }
      await initialize();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: false,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      AppLogger.warn('Notifications', 'Permission request failed', e);
    }
    return false;
  }

  @override
  Future<void> syncReminders(List<PlannedReminder> plan) async {
    if (kIsWeb) return _syncWeb(plan);
    if (capability != ReminderCapability.scheduled) return;
    await initialize();
    if (!_initialized) return;
    try {
      await _cancelPendingReminders();
      for (final r in plan) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: r.payload,
          scheduledDate: tz.TZDateTime(
            tz.local,
            r.at.year,
            r.at.month,
            r.at.day,
            r.at.hour,
            r.at.minute,
          ),
          notificationDetails: const NotificationDetails(
            android: _remindersChannel,
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      AppLogger.info('Notifications', 'Scheduled ${plan.length} reminders');
    } catch (e, st) {
      AppLogger.error('Notifications', 'Scheduling failed', e, st);
    }
  }

  Future<void> _cancelPendingReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= ReminderPlanner.idBase) {
        await _plugin.cancel(id: p.id);
      }
    }
  }

  Future<void> _syncWeb(List<PlannedReminder> plan) async {
    for (final t in _webTimers) {
      t.cancel();
    }
    _webTimers.clear();
    if (plan.isEmpty || !await hasPermission()) return;
    final web = await _ensureWeb();
    if (web == null) return;
    final now = DateTime.now();
    for (final r in plan) {
      final delay = r.at.difference(now);
      // Only arm timers for the next 24h; the plan is refreshed on resume.
      if (delay.isNegative || delay > const Duration(hours: 24)) continue;
      _webTimers.add(
        Timer(delay, () {
          unawaited(
            showNow(id: r.id, title: r.title, body: r.body, route: r.payload),
          );
        }),
      );
    }
  }

  @override
  Future<void> cancelAllReminders() async {
    for (final t in _webTimers) {
      t.cancel();
    }
    _webTimers.clear();
    if (kIsWeb || !_initialized) return;
    try {
      await _cancelPendingReminders();
    } catch (e) {
      AppLogger.warn('Notifications', 'Cancel failed', e);
    }
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? route,
  }) async {
    try {
      if (kIsWeb) {
        if (!await hasPermission() || await _ensureWeb() == null) return;
      } else {
        await initialize();
        if (!_initialized) return;
      }
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: route,
        notificationDetails: const NotificationDetails(
          android: _alertsChannel,
          iOS: DarwinNotificationDetails(),
          web: WebNotificationDetails(),
        ),
      );
    } catch (e) {
      AppLogger.warn('Notifications', 'Show failed', e);
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (kIsWeb) return;
    try {
      await _plugin.openAppNotificationSettings();
    } catch (e) {
      AppLogger.warn('Notifications', 'Could not open settings', e);
    }
  }
}
