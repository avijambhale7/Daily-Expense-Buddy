import 'package:cloud_firestore/cloud_firestore.dart';

/// Typed access to the authenticated user's document tree.
///
/// Every path is derived from the signed-in user's uid, which is supplied by
/// Firebase Authentication – never by user input – and enforced again by
/// the security rules.
///
/// ```
/// users/{uid}
/// users/{uid}/expenses/{expenseId}
/// users/{uid}/categories/{categoryId}
/// users/{uid}/budgets/{budgetId}
/// users/{uid}/budget_alerts/{yyyy-MM}_{budgetId}
/// users/{uid}/daily_status/{yyyy-MM-dd}
/// users/{uid}/loans/{loanId}
/// users/{uid}/settings/preferences
/// users/{uid}/entitlements/premium      (server-written only)
/// ```
class FirestoreUserStore {
  FirestoreUserStore(this.db, this.uid) : assert(uid.isNotEmpty);

  final FirebaseFirestore db;
  final String uid;

  static const userCollections = [
    'expenses',
    'categories',
    'budgets',
    'budget_alerts',
    'daily_status',
    'loans',
    'recurring',
    'goals',
    'settings',
    'entitlements',
  ];

  DocumentReference<Map<String, dynamic>> get userDoc =>
      db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> get expenses =>
      userDoc.collection('expenses');
  CollectionReference<Map<String, dynamic>> get categories =>
      userDoc.collection('categories');
  CollectionReference<Map<String, dynamic>> get budgets =>
      userDoc.collection('budgets');
  CollectionReference<Map<String, dynamic>> get budgetAlerts =>
      userDoc.collection('budget_alerts');
  CollectionReference<Map<String, dynamic>> get dailyStatus =>
      userDoc.collection('daily_status');
  CollectionReference<Map<String, dynamic>> get loans =>
      userDoc.collection('loans');
  CollectionReference<Map<String, dynamic>> get recurring =>
      userDoc.collection('recurring');
  CollectionReference<Map<String, dynamic>> get goals =>
      userDoc.collection('goals');
  DocumentReference<Map<String, dynamic>> get preferences =>
      userDoc.collection('settings').doc('preferences');
  DocumentReference<Map<String, dynamic>> get premium =>
      userDoc.collection('entitlements').doc('premium');
}
