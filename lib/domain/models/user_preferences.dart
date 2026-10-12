import 'package:equatable/equatable.dart';

import '../../core/money/currency.dart';

/// Daily reminder configuration. Times are minutes after local midnight.
class ReminderSettings extends Equatable {
  const ReminderSettings({
    this.enabled = false,
    this.timeMinutes = 22 * 60,
    this.followUpsEnabled = true,
    this.followUpMinutes = const [22 * 60 + 45, 23 * 60 + 30],
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 23 * 60,
    this.quietEndMinutes = 7 * 60,
  });

  static const int maxFollowUps = 3;

  final bool enabled;
  final int timeMinutes;
  final bool followUpsEnabled;
  final List<int> followUpMinutes;
  final bool quietHoursEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;

  /// Whether [minutes] (after midnight) falls inside the quiet window.
  /// Windows may wrap past midnight (e.g. 23:00–07:00).
  bool isQuiet(int minutes) {
    if (!quietHoursEnabled || quietStartMinutes == quietEndMinutes) {
      return false;
    }
    if (quietStartMinutes < quietEndMinutes) {
      return minutes >= quietStartMinutes && minutes < quietEndMinutes;
    }
    return minutes >= quietStartMinutes || minutes < quietEndMinutes;
  }

  ReminderSettings copyWith({
    bool? enabled,
    int? timeMinutes,
    bool? followUpsEnabled,
    List<int>? followUpMinutes,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      timeMinutes: timeMinutes ?? this.timeMinutes,
      followUpsEnabled: followUpsEnabled ?? this.followUpsEnabled,
      followUpMinutes: followUpMinutes ?? this.followUpMinutes,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
      quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    );
  }

  Map<String, Object?> toMap() => {
    'enabled': enabled,
    'timeMinutes': timeMinutes,
    'followUpsEnabled': followUpsEnabled,
    'followUpMinutes': followUpMinutes,
    'quietHoursEnabled': quietHoursEnabled,
    'quietStartMinutes': quietStartMinutes,
    'quietEndMinutes': quietEndMinutes,
  };

  static int _minutes(Object? v, int fallback) {
    if (v is int && v >= 0 && v < 24 * 60) return v;
    return fallback;
  }

  factory ReminderSettings.fromMap(Map<String, Object?>? map) {
    const d = ReminderSettings();
    if (map == null) return d;
    final follow = map['followUpMinutes'];
    return ReminderSettings(
      enabled: map['enabled'] is bool ? map['enabled']! as bool : d.enabled,
      timeMinutes: _minutes(map['timeMinutes'], d.timeMinutes),
      followUpsEnabled: map['followUpsEnabled'] is bool
          ? map['followUpsEnabled']! as bool
          : d.followUpsEnabled,
      followUpMinutes: follow is List
          ? follow
                .whereType<int>()
                .where((m) => m >= 0 && m < 24 * 60)
                .take(maxFollowUps)
                .toList()
          : d.followUpMinutes,
      quietHoursEnabled: map['quietHoursEnabled'] is bool
          ? map['quietHoursEnabled']! as bool
          : d.quietHoursEnabled,
      quietStartMinutes: _minutes(
        map['quietStartMinutes'],
        d.quietStartMinutes,
      ),
      quietEndMinutes: _minutes(map['quietEndMinutes'], d.quietEndMinutes),
    );
  }

  @override
  List<Object?> get props => [
    enabled,
    timeMinutes,
    followUpsEnabled,
    followUpMinutes,
    quietHoursEnabled,
    quietStartMinutes,
    quietEndMinutes,
  ];
}

/// Per-user preferences synchronised through Firestore
/// (`users/{uid}/settings/preferences`).
class UserPreferences extends Equatable {
  const UserPreferences({
    required this.currencyCode,
    this.weekStart = DateTime.monday,
    this.formatLocale,
    this.reminders = const ReminderSettings(),
    this.budgetAlertThresholds = const [80, 100],
  });

  factory UserPreferences.defaultsFor(String locale) => UserPreferences(
    currencyCode: Currencies.defaultForLocale(locale),
    weekStart: _defaultWeekStart(locale),
  );

  static int _defaultWeekStart(String locale) {
    final region = locale.split(RegExp('[_-]')).last.toUpperCase();
    const sundayRegions = {'US', 'CA', 'JP', 'IN', 'AU', 'BR', 'MX', 'IL'};
    if (sundayRegions.contains(region)) return DateTime.sunday;
    if (region == 'AE') return DateTime.saturday;
    return DateTime.monday;
  }

  /// Reporting currency. New expenses are recorded in this currency.
  final String currencyCode;

  /// ISO weekday the week starts on (1 = Monday … 7 = Sunday).
  final int weekStart;

  /// Locale used for number/date formatting; null follows the device.
  final String? formatLocale;
  final ReminderSettings reminders;

  /// Budget alert thresholds in percent, ascending (e.g. [80, 100]).
  final List<int> budgetAlertThresholds;

  UserPreferences copyWith({
    String? currencyCode,
    int? weekStart,
    String? Function()? formatLocale,
    ReminderSettings? reminders,
    List<int>? budgetAlertThresholds,
  }) {
    return UserPreferences(
      currencyCode: currencyCode ?? this.currencyCode,
      weekStart: weekStart ?? this.weekStart,
      formatLocale: formatLocale != null ? formatLocale() : this.formatLocale,
      reminders: reminders ?? this.reminders,
      budgetAlertThresholds:
          budgetAlertThresholds ?? this.budgetAlertThresholds,
    );
  }

  @override
  List<Object?> get props => [
    currencyCode,
    weekStart,
    formatLocale,
    reminders,
    budgetAlertThresholds,
  ];
}
