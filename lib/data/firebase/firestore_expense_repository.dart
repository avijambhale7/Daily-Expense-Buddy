import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/dates/local_date.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/expense.dart';
import '../../domain/models/expense_filter.dart';
import '../../domain/repositories/repositories.dart';
import 'firebase_error_mapper.dart';
import 'firestore_serializers.dart';
import 'firestore_user_store.dart';
import 'write_tracker.dart';

class FirestoreExpenseRepository implements ExpenseRepository {
  FirestoreExpenseRepository(this._store, this._tracker);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;

  CollectionReference<Map<String, dynamic>> get _col => _store.expenses;

  List<Expense> _parse(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = <Expense>[];
    for (final doc in snap.docs) {
      final e = FirestoreSerializers.expenseFromDoc(doc);
      if (e == null) {
        AppLogger.warn('Expenses', 'Skipped malformed expense document');
      } else {
        list.add(e);
      }
    }
    return list;
  }

  Stream<T> _mapErrors<T>(Stream<T> s) =>
      s.handleError((Object e, StackTrace st) {
        AppLogger.error('Expenses', 'Listener error', e, st);
        throw FirebaseErrorMapper.firestore(e);
      });

  Query<Map<String, dynamic>> _query(ExpenseFilter filter) {
    Query<Map<String, dynamic>> q = _col;
    if (filter.categoryId != null) {
      q = q.where('categoryId', isEqualTo: filter.categoryId);
    }
    if (filter.paymentMethod != null) {
      q = q.where('paymentMethod', isEqualTo: filter.paymentMethod!.key);
    }
    final range = filter.range;
    if (range != null) {
      q = q
          .where('date', isGreaterThanOrEqualTo: range.start.toIso())
          .where('date', isLessThanOrEqualTo: range.end.toIso());
    }
    return q.orderBy('date', descending: filter.newestFirst);
  }

  @override
  String newId() => _col.doc().id;

  @override
  Stream<List<Expense>> watchRange(DateRange range) {
    final q = _col
        .where('date', isGreaterThanOrEqualTo: range.start.toIso())
        .where('date', isLessThanOrEqualTo: range.end.toIso());
    return _mapErrors(q.snapshots(includeMetadataChanges: true).map(_parse));
  }

  @override
  Stream<ExpensePage> watchHistory(ExpenseFilter filter, {required int limit}) {
    return _mapErrors(
      _query(filter)
          .limit(limit + 1)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
            final items = _parse(snap);
            final hasMore = items.length > limit;
            final page = items.take(limit).toList()
              ..sort(
                filter.newestFirst
                    ? Expense.newestFirst
                    : (a, b) => Expense.newestFirst(b, a),
              );
            return ExpensePage(page, hasMore: hasMore);
          }),
    );
  }

  @override
  Stream<Expense?> watchExpense(String id) => _mapErrors(
    _col
        .doc(id)
        .snapshots(includeMetadataChanges: true)
        .map(FirestoreSerializers.expenseFromDoc),
  );

  @override
  Future<List<Expense>> fetch(ExpenseFilter filter) async {
    try {
      final snap = await _query(filter).get();
      return _parse(snap);
    } catch (e, st) {
      AppLogger.error('Expenses', 'Fetch failed', e, st);
      throw FirebaseErrorMapper.firestore(e);
    }
  }

  @override
  Future<SaveOutcome> create(Expense expense) {
    final data = {
      ...FirestoreSerializers.expenseFields(expense),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'version': 1,
    };
    // `set` on a pre-generated id is idempotent: re-submitting the same form
    // can never produce a second document.
    return _tracker.track(_col.doc(expense.id).set(data), operation: 'create');
  }

  @override
  Future<SaveOutcome> update(Expense expense) {
    final fields = FirestoreSerializers.expenseFields(expense);
    final data = <String, Object?>{
      for (final entry in fields.entries)
        entry.key: entry.value ?? FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'version': expense.version + 1,
    };
    return _tracker.track(
      _col.doc(expense.id).update(data),
      isUpdate: true,
      operation: 'update',
    );
  }

  @override
  Future<SaveOutcome> delete(String id) =>
      _tracker.track(_col.doc(id).delete(), operation: 'delete');

  @override
  Future<bool> isCategoryUsed(String categoryId) async {
    try {
      final snap = await _col
          .where('categoryId', isEqualTo: categoryId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      throw FirebaseErrorMapper.firestore(e);
    }
  }
}
