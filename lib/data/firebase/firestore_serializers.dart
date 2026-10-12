import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/dates/local_date.dart';
import '../../domain/models/budget.dart';
import '../../domain/models/daily_status.dart';
import '../../domain/models/expense.dart';
import '../../domain/models/expense_category.dart';
import '../../domain/models/premium_entitlement.dart';
import '../../domain/models/user_preferences.dart';

/// Firestore <-> model conversion. Documents are validated on read; malformed
/// documents are skipped (and logged by callers) rather than crashing a list.
///
/// Storage conventions
/// * money: `amountMinor` (int, minor units) + `currency` (ISO 4217 code)
/// * expense calendar date: `date` as `yyyy-MM-dd` string (no time zone)
/// * instants: Firestore `Timestamp`s written with `serverTimestamp()`
abstract final class FirestoreSerializers {
  static DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

  static String? _optString(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;

  static Expense? expenseFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final amount = data['amountMinor'];
    final currency = data['currency'];
    final date = LocalDate.tryParse(data['date'] as String?);
    final category = data['categoryId'];
    if (amount is! int || currency is! String || date == null) return null;
    return Expense(
      id: doc.id,
      amountMinor: amount,
      currencyCode: currency,
      categoryId: category is String && category.isNotEmpty
          ? category
          : ExpenseCategory.fallbackId,
      date: date,
      note: _optString(data['note']),
      merchant: _optString(data['merchant']),
      paymentMethod: PaymentMethod.fromKey(data['paymentMethod'] as String?),
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
      version: data['version'] is int ? data['version'] as int : 0,
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  /// Fields shared by create and update (excludes createdAt/version).
  static Map<String, Object?> expenseFields(Expense e) => {
    'amountMinor': e.amountMinor,
    'currency': e.currencyCode,
    'categoryId': e.categoryId,
    'date': e.date.toIso(),
    'note': _optString(e.note?.trim()),
    'merchant': _optString(e.merchant?.trim()),
    'paymentMethod': e.paymentMethod?.key,
  };

  static ExpenseCategory? categoryFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    if (d == null) return null;
    final name = d['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final color = d['colorIndex'];
    return ExpenseCategory(
      id: doc.id,
      name: name,
      iconKey: d['iconKey'] is String ? d['iconKey'] as String : 'other',
      colorIndex:
          color is int && color >= 0 && color < ExpenseCategory.paletteSize
          ? color
          : 11,
      isBuiltIn: DefaultCategories.isBuiltInId(doc.id),
      isArchived: d['archived'] == true,
      sortOrder: d['sortOrder'] is int ? d['sortOrder'] as int : 100,
    );
  }

  static Map<String, Object?> categoryToMap(ExpenseCategory c) => {
    'name': c.name.trim(),
    'iconKey': c.iconKey,
    'colorIndex': c.colorIndex,
    'archived': c.isArchived,
    'sortOrder': c.sortOrder,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static Budget? budgetFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    final amount = d['amountMinor'];
    final currency = d['currency'];
    if (amount is! int || currency is! String) return null;
    return Budget(
      id: doc.id,
      amountMinor: amount,
      currencyCode: currency,
      categoryId: d['categoryId'] is String ? d['categoryId'] as String : null,
    );
  }

  static Map<String, Object?> budgetToMap(Budget b) => {
    'amountMinor': b.amountMinor,
    'currency': b.currencyCode,
    'categoryId': b.categoryId,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static DailyStatusRecord? statusFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    if (d == null) return null;
    final date = LocalDate.tryParse(d['date'] as String?);
    final status = StoredDayStatus.fromKey(d['status'] as String?);
    if (date == null || status == null) return null;
    return DailyStatusRecord(
      date: date,
      status: status,
      updatedAt: _ts(d['updatedAt']),
    );
  }

  static UserPreferences preferencesFromMap(
    Map<String, dynamic>? d,
    UserPreferences defaults,
  ) {
    if (d == null) return defaults;
    final thresholds = d['budgetAlertThresholds'];
    final weekStart = d['weekStart'];
    return UserPreferences(
      currencyCode: d['currencyCode'] is String
          ? d['currencyCode'] as String
          : defaults.currencyCode,
      weekStart: weekStart is int && weekStart >= 1 && weekStart <= 7
          ? weekStart
          : defaults.weekStart,
      formatLocale: _optString(d['formatLocale']),
      reminders: ReminderSettings.fromMap(
        (d['reminders'] as Map?)?.cast<String, Object?>(),
      ),
      budgetAlertThresholds: thresholds is List
          ? (thresholds
                .whereType<int>()
                .where((t) => t > 0 && t <= 200)
                .toSet()
                .toList()
              ..sort())
          : defaults.budgetAlertThresholds,
    );
  }

  static Map<String, Object?> preferencesToMap(UserPreferences p) => {
    'currencyCode': p.currencyCode,
    'weekStart': p.weekStart,
    'formatLocale': p.formatLocale,
    'reminders': p.reminders.toMap(),
    'budgetAlertThresholds': p.budgetAlertThresholds,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static PremiumEntitlement entitlementFromMap(Map<String, dynamic>? d) {
    if (d == null) return PremiumEntitlement.none;
    return PremiumEntitlement(
      active: d['active'] == true,
      expiresAt: _ts(d['expiresAt']),
      source: _optString(d['source']),
    );
  }
}
