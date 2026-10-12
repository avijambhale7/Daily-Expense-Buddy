import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_dependencies.dart';
import '../../app/session/session_cubits.dart';
import '../dates/local_date.dart';
import '../money/currency.dart';
import '../money/money_formatter.dart';

/// Locale- and currency-aware formatting for the signed-in user.
class AppFormat {
  AppFormat._(this.locale, this.currencyCode, this.weekStart)
    : money = MoneyFormatter(locale: locale, currencyCode: currencyCode);

  static final Map<String, AppFormat> _cache = {};

  factory AppFormat.forLocale(
    String locale,
    String currencyCode, {
    int weekStart = DateTime.monday,
  }) {
    final verified = verifyLocale(locale);
    final key = '$verified|$currencyCode|$weekStart';
    return _cache.putIfAbsent(
      key,
      () => AppFormat._(verified, currencyCode, weekStart),
    );
  }

  /// Formatter for the current user's preferences (falls back to the device
  /// locale before preferences load). Rebuilds when preferences change.
  static AppFormat of(BuildContext context) {
    final deviceLocale = context.read<AppDependencies>().locale;
    PreferencesState? prefs;
    try {
      prefs = context.watch<PreferencesCubit>().state;
    } on ProviderNotFoundException {
      prefs = null;
    }
    final p = prefs?.preferences;
    return AppFormat.forLocale(
      p?.formatLocale ?? deviceLocale,
      p?.currencyCode ?? Currencies.defaultForLocale(deviceLocale),
      weekStart: p?.weekStart ?? DateTime.monday,
    );
  }

  static String verifyLocale(String locale) {
    try {
      return Intl.verifiedLocale(
            locale,
            (l) => NumberFormat.localeExists(l) && DateFormat.localeExists(l),
            onFailure: (_) => 'en_US',
          ) ??
          'en_US';
    } catch (_) {
      return 'en_US';
    }
  }

  final String locale;
  final String currencyCode;
  final int weekStart;
  final MoneyFormatter money;

  CurrencyConfiguration get currency => money.currency;

  String amount(int minor) => money.format(minor);
  String compact(int minor) => money.compact(minor);

  late final DateFormat _medium = DateFormat.yMMMd(locale);
  late final DateFormat _long = DateFormat.yMMMMEEEEd(locale);
  late final DateFormat _weekdayShort = DateFormat.E(locale);
  late final DateFormat _weekdayDay = DateFormat.MMMEd(locale);
  late final DateFormat _monthYear = DateFormat.yMMMM(locale);
  late final DateFormat _monthShort = DateFormat.MMM(locale);
  late final DateFormat _dayMonth = DateFormat.MMMd(locale);
  late final DateFormat _time = DateFormat.jm(locale);
  late final DateFormat _dateTime = DateFormat.yMMMd(locale).add_jm();

  String date(LocalDate d) => _medium.format(d.toDateTime());
  String dateLong(LocalDate d) => _long.format(d.toDateTime());
  String weekdayShort(LocalDate d) => _weekdayShort.format(d.toDateTime());
  String weekdayDay(LocalDate d) => _weekdayDay.format(d.toDateTime());
  String monthYear(LocalDate d) => _monthYear.format(d.toDateTime());
  String monthShort(int month) => _monthShort.format(DateTime(2000, month));
  String dayMonth(LocalDate d) => _dayMonth.format(d.toDateTime());
  String dateTime(DateTime t) => _dateTime.format(t.toLocal());

  /// "Today", "Yesterday" or a formatted date.
  String relativeDay(LocalDate d, LocalDate today) {
    if (d == today) return 'Today';
    if (d == today.addDays(-1)) return 'Yesterday';
    return _weekdayDay.format(d.toDateTime()) +
        (d.year != today.year ? ', ${d.year}' : '');
  }

  String timeOfDay(int minutes) =>
      _time.format(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60));

  String range(DateRange r) {
    if (r.start == r.end) return date(r.start);
    if (r.start.year == r.end.year) {
      return '${dayMonth(r.start)} – ${date(r.end)}';
    }
    return '${date(r.start)} – ${date(r.end)}';
  }

  /// Weekday names starting at [weekStart], short form.
  List<String> weekdayHeaders() {
    // 2024-01-01 was a Monday.
    final monday = LocalDate(2024, 1, 1);
    return [
      for (var i = 0; i < 7; i++)
        DateFormat.E(locale)
            .format(monday.addDays((weekStart - 1 + i) % 7).toDateTime()),
    ];
  }
}
