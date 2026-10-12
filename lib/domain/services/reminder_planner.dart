import 'package:equatable/equatable.dart';

import '../../core/dates/local_date.dart';
import '../models/user_preferences.dart';

class PlannedReminder extends Equatable {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.day,
    required this.slot,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Notification id, stable for a given day + slot.
  final int id;

  /// Local wall-clock time the reminder should fire.
  final DateTime at;

  /// The day the reminder is about.
  final LocalDate day;

  /// 0 = primary reminder, 1.. = follow-ups.
  final int slot;
  final String title;
  final String body;

  /// Route opened when the notification is tapped.
  final String payload;

  bool get isFollowUp => slot > 0;

  @override
  List<Object?> get props => [id, at, day, slot, title, body, payload];
}

/// Computes which reminder notifications should be pending.
///
/// Reminders are scheduled as individual one-shot notifications for the next
/// [horizonDays] days, rather than one repeating notification, so that the
/// reminders of a day can be removed as soon as that day is marked complete.
/// The plan is recomputed whenever settings or day statuses change and every
/// time the app is opened.
abstract final class ReminderPlanner {
  static const int horizonDays = 14;
  static const int idBase = 100000;

  static int idFor(LocalDate day, int slot) =>
      idBase + (day.epochDay % 10000) * 10 + slot;

  static String payloadFor(LocalDate day) => '/calendar/day/${day.toIso()}';

  static List<PlannedReminder> plan({
    required DateTime now,
    required ReminderSettings settings,
    required Set<LocalDate> completedDays,
    int days = horizonDays,
  }) {
    if (!settings.enabled) return const [];
    final today = LocalDate.fromDateTime(now);
    final slots = <int>[settings.timeMinutes];
    if (settings.followUpsEnabled) {
      final followUps =
          settings.followUpMinutes
              .where((m) => m > settings.timeMinutes)
              .toSet()
              .toList()
            ..sort();
      slots.addAll(followUps.take(ReminderSettings.maxFollowUps));
    }

    final result = <PlannedReminder>[];
    for (var i = 0; i < days; i++) {
      final day = today.addDays(i);
      if (completedDays.contains(day)) continue;
      for (var s = 0; s < slots.length; s++) {
        final minutes = slots[s];
        if (settings.isQuiet(minutes)) continue;
        final at = DateTime(
          day.year,
          day.month,
          day.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (!at.isAfter(now)) continue;
        result.add(
          PlannedReminder(
            id: idFor(day, s),
            at: at,
            day: day,
            slot: s,
            title: s == 0
                ? "Time to log today's expenses"
                : "Today's expenses aren't complete yet",
            body: s == 0
                ? 'Take a few seconds to record what you spent today.'
                : 'Add anything missing or mark the day as complete.',
            payload: payloadFor(day),
          ),
        );
      }
    }
    return result;
  }
}
