import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/dates/local_date.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/expense.dart';
import '../../domain/models/recurring_expense.dart';
import '../../domain/models/savings_goal.dart';
import '../../domain/repositories/repositories.dart';
import 'firebase_error_mapper.dart';
import 'firestore_user_store.dart';
import 'write_tracker.dart';

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

Stream<List<T>> _watch<T>(
  CollectionReference<Map<String, dynamic>> col,
  T? Function(DocumentSnapshot<Map<String, dynamic>>) parse,
  String tag,
) => col
    .snapshots()
    .map((snap) => [for (final d in snap.docs) ?parse(d)])
    .handleError((Object e, StackTrace st) {
      AppLogger.error(tag, 'Listener error', e, st);
      throw FirebaseErrorMapper.firestore(e);
    });

class FirestoreRecurringRepository implements RecurringRepository {
  FirestoreRecurringRepository(this._store, this._tracker);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;

  CollectionReference<Map<String, dynamic>> get _col => _store.recurring;

  static RecurringExpense? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    final amount = d['amountMinor'];
    final currency = d['currency'];
    final category = d['categoryId'];
    final frequency = RecurrenceFrequency.fromKey(d['frequency']);
    final start = LocalDate.tryParse(d['startDate'] as String?);
    if (amount is! int ||
        currency is! String ||
        category is! String ||
        frequency == null ||
        start == null) {
      return null;
    }
    return RecurringExpense(
      id: doc.id,
      amountMinor: amount,
      currencyCode: currency,
      categoryId: category,
      frequency: frequency,
      startDate: start,
      merchant: _str(d['merchant']),
      note: _str(d['note']),
      paymentMethod: PaymentMethod.fromKey(d['paymentMethod'] as String?),
      lastPostedDate: LocalDate.tryParse(d['lastPostedDate'] as String?),
      active: d['active'] != false,
    );
  }

  @override
  String newId() => _col.doc().id;

  @override
  Stream<List<RecurringExpense>> watchAll() => _watch(
    _col,
    fromDoc,
    'Recurring',
  ).map((list) => list..sort((a, b) => a.startDate.compareTo(b.startDate)));

  @override
  Future<SaveOutcome> save(RecurringExpense t, {required bool isNew}) {
    final data = <String, Object?>{
      'amountMinor': t.amountMinor,
      'currency': t.currencyCode,
      'categoryId': t.categoryId,
      'frequency': t.frequency.key,
      'startDate': t.startDate.toIso(),
      'merchant': _str(t.merchant),
      'note': _str(t.note),
      'paymentMethod': t.paymentMethod?.key,
      'lastPostedDate': t.lastPostedDate?.toIso(),
      'active': t.active,
      'updatedAt': FieldValue.serverTimestamp(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
    };
    final ref = _col.doc(t.id);
    return _tracker.track(
      isNew ? ref.set(data) : ref.update(data),
      isUpdate: !isNew,
      operation: 'saveRecurring',
    );
  }

  @override
  Future<SaveOutcome> markPosted(String id, LocalDate date) => _tracker.track(
    _col.doc(id).update({
      'lastPostedDate': date.toIso(),
      'updatedAt': FieldValue.serverTimestamp(),
    }),
    isUpdate: true,
    operation: 'markRecurring',
  );

  @override
  Future<SaveOutcome> delete(String id) =>
      _tracker.track(_col.doc(id).delete(), operation: 'deleteRecurring');
}

class FirestoreGoalRepository implements GoalRepository {
  FirestoreGoalRepository(this._store, this._tracker);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;

  CollectionReference<Map<String, dynamic>> get _col => _store.goals;

  static SavingsGoal? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    final name = _str(d['name']);
    final target = d['targetMinor'];
    final currency = d['currency'];
    if (name == null || target is! int || currency is! String) return null;
    return SavingsGoal(
      id: doc.id,
      name: name,
      targetMinor: target,
      savedMinor: d['savedMinor'] is int ? d['savedMinor'] as int : 0,
      currencyCode: currency,
      targetDate: LocalDate.tryParse(d['targetDate'] as String?),
    );
  }

  @override
  String newId() => _col.doc().id;

  @override
  Stream<List<SavingsGoal>> watchAll() => _watch(_col, fromDoc, 'Goals').map(
    (list) => list
      ..sort((a, b) {
        if (a.reached != b.reached) return a.reached ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }),
  );

  @override
  Future<SaveOutcome> save(SavingsGoal g, {required bool isNew}) {
    final data = <String, Object?>{
      'name': g.name.trim(),
      'targetMinor': g.targetMinor,
      'savedMinor': g.savedMinor,
      'currency': g.currencyCode,
      'targetDate': g.targetDate?.toIso(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
    };
    final ref = _col.doc(g.id);
    return _tracker.track(
      isNew ? ref.set(data) : ref.update(data),
      isUpdate: !isNew,
      operation: 'saveGoal',
    );
  }

  @override
  Future<SaveOutcome> delete(String id) =>
      _tracker.track(_col.doc(id).delete(), operation: 'deleteGoal');
}
