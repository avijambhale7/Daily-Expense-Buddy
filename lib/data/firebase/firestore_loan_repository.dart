import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/dates/local_date.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/loan.dart';
import '../../domain/repositories/repositories.dart';
import 'firebase_error_mapper.dart';
import 'firestore_user_store.dart';
import 'write_tracker.dart';

class FirestoreLoanRepository implements LoanRepository {
  FirestoreLoanRepository(this._store, this._tracker);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;

  CollectionReference<Map<String, dynamic>> get _col => _store.loans;

  static Loan? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    final direction = LoanDirection.fromKey(d['direction']);
    final name = d['personName'];
    final amount = d['amountMinor'];
    final repaid = d['repaidMinor'];
    final currency = d['currency'];
    final date = LocalDate.tryParse(d['date'] as String?);
    if (direction == null ||
        name is! String ||
        amount is! int ||
        currency is! String ||
        date == null) {
      return null;
    }
    return Loan(
      id: doc.id,
      direction: direction,
      personName: name,
      amountMinor: amount,
      repaidMinor: repaid is int ? repaid : 0,
      currencyCode: currency,
      date: date,
      dueDate: LocalDate.tryParse(d['dueDate'] as String?),
      note: d['note'] as String?,
      settled: d['settled'] == true,
      cancelled: d['cancelled'] == true,
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  static Map<String, Object?> fields(Loan l) => {
    'direction': l.direction.key,
    'personName': l.personName.trim(),
    'amountMinor': l.amountMinor,
    'repaidMinor': l.repaidMinor,
    'currency': l.currencyCode,
    'date': l.date.toIso(),
    'dueDate': l.dueDate?.toIso(),
    'note': (l.note?.trim().isEmpty ?? true) ? null : l.note!.trim(),
    'settled': l.settled,
    'cancelled': l.cancelled,
  };

  CollectionReference<Map<String, dynamic>> _repayments(String loanId) =>
      _col.doc(loanId).collection('repayments');

  static LoanRepayment? repaymentFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    if (d == null) return null;
    final amount = d['amountMinor'];
    final date = LocalDate.tryParse(d['date'] as String?);
    if (amount is! int || date == null) return null;
    final created = d['createdAt'];
    return LoanRepayment(
      id: doc.id,
      amountMinor: amount,
      date: date,
      note: d['note'] as String?,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }

  @override
  String newId() => _col.doc().id;

  @override
  Stream<List<Loan>> watchAll() => _col
      .snapshots(includeMetadataChanges: true)
      .map((snap) {
        final list = <Loan>[];
        for (final doc in snap.docs) {
          final loan = fromDoc(doc);
          if (loan == null) {
            AppLogger.warn('Loans', 'Skipped malformed loan document');
          } else {
            list.add(loan);
          }
        }
        // Newest first; ties broken by name for a stable order.
        list.sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : a.personName.compareTo(b.personName);
        });
        return list;
      })
      .handleError((Object e, StackTrace st) {
        AppLogger.error('Loans', 'Listener error', e, st);
        throw FirebaseErrorMapper.firestore(e);
      });

  @override
  Future<SaveOutcome> create(Loan loan) => _tracker.track(
    _col.doc(loan.id).set({
      ...fields(loan),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }),
    operation: 'createLoan',
  );

  @override
  Future<SaveOutcome> update(Loan loan) => _tracker.track(
    _col.doc(loan.id).update({
      ...fields(loan),
      'updatedAt': FieldValue.serverTimestamp(),
    }),
    isUpdate: true,
    operation: 'updateLoan',
  );

  @override
  Future<SaveOutcome> delete(String id) async {
    final List<DocumentReference<Map<String, dynamic>>> history;
    try {
      history = [
        for (final d in (await _repayments(id).get()).docs) d.reference,
      ];
    } catch (e) {
      throw FirebaseErrorMapper.firestore(e);
    }
    final batch = _store.db.batch();
    for (final ref in history) {
      batch.delete(ref);
    }
    batch.delete(_col.doc(id));
    return _tracker.track(batch.commit(), operation: 'deleteLoan');
  }

  @override
  String newRepaymentId(String loanId) => _repayments(loanId).doc().id;

  @override
  Stream<List<LoanRepayment>> watchRepayments(String loanId) =>
      _repayments(loanId)
          .snapshots()
          .map((snap) {
            final list = [for (final doc in snap.docs) ?repaymentFromDoc(doc)];
            list.sort((a, b) {
              final byDate = b.date.compareTo(a.date);
              if (byDate != 0) return byDate;
              final at = a.createdAt, bt = b.createdAt;
              if (at == null || bt == null) return 0;
              return bt.compareTo(at);
            });
            return list;
          })
          .handleError((Object e, StackTrace st) {
            AppLogger.error('Loans', 'Repayments listener error', e, st);
            throw FirebaseErrorMapper.firestore(e);
          });

  @override
  Future<SaveOutcome> addRepayment(Loan loan, LoanRepayment repayment) {
    final updated = loan.withRepayment(repayment.amountMinor);
    final note = repayment.note?.trim();
    final batch = _store.db.batch()
      ..set(_repayments(loan.id).doc(repayment.id), {
        'amountMinor': repayment.amountMinor,
        'date': repayment.date.toIso(),
        'note': (note?.isEmpty ?? true) ? null : note,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..update(_col.doc(loan.id), {
        'repaidMinor': updated.repaidMinor,
        'settled': updated.settled,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    return _tracker.track(
      batch.commit(),
      isUpdate: true,
      operation: 'addRepayment',
    );
  }
}
