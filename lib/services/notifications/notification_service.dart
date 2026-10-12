import 'dart:async';

import '../../domain/services/reminder_planner.dart';

enum ReminderCapability {
  /// Reminders are scheduled with the operating system and fire even when
  /// the app is closed (Android, iOS).
  scheduled,

  /// Reminders can only be shown while the app is open in a browser tab
  /// (web). Closed-tab delivery would need push messaging infrastructure.
  whileOpen,

  /// Notifications are not available on this platform/browser.
  unsupported,
}

/// Platform-neutral notification API used by the reminder and budget-alert
/// coordinators.
abstract class NotificationService {
  ReminderCapability get capability;

  /// Routes (e.g. `/calendar/day/2026-10-12`) of tapped notifications.
  Stream<String> get taps;

  /// Route of the notification that launched the app, if any (consumed once).
  String? takeLaunchRoute();

  Future<void> initialize();

  /// Whether notifications are currently permitted. Does not prompt.
  Future<bool> hasPermission();

  /// Prompts for permission. Only call after the user has explicitly opted
  /// in and seen an explanation.
  Future<bool> requestPermission();

  /// Replaces all pending reminder notifications with [plan].
  Future<void> syncReminders(List<PlannedReminder> plan);

  Future<void> cancelAllReminders();

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? route,
  });

  /// Opens the system notification settings for the app (mobile).
  Future<void> openSystemSettings();
}

/// Used in tests and on platforms without notification support.
class NoopNotificationService implements NotificationService {
  final _taps = StreamController<String>.broadcast();
  final List<PlannedReminder> lastPlan = [];
  bool permissionGranted = false;

  @override
  ReminderCapability get capability => ReminderCapability.unsupported;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  String? takeLaunchRoute() => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> syncReminders(List<PlannedReminder> plan) async {
    lastPlan
      ..clear()
      ..addAll(plan);
  }

  @override
  Future<void> cancelAllReminders() async => lastPlan.clear();

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? route,
  }) async {}

  @override
  Future<void> openSystemSettings() async {}
}
