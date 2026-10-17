import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/dates/local_date.dart';
import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/budget.dart';
import '../../domain/models/daily_status.dart';
import '../../domain/models/expense_category.dart';
import '../../domain/models/premium_entitlement.dart';
import '../../domain/models/user_preferences.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/repositories/repositories.dart';
import 'firebase_error_mapper.dart';
import 'firestore_serializers.dart';
import 'firestore_user_store.dart';
import 'write_tracker.dart';

Stream<T> _mapErrors<T>(String component, Stream<T> s) =>
    s.handleError((Object e, StackTrace st) {
      AppLogger.error(component, 'Listener error', e, st);
      throw FirebaseErrorMapper.firestore(e);
    });

class FirestoreCategoryRepository implements CategoryRepository {
  FirestoreCategoryRepository(this._store, this._tracker);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;

  @override
  Stream<List<ExpenseCategory>> watchAll() => _mapErrors(
    'Categories',
    _store.categories.snapshots().map((snap) {
      final stored = snap.docs
          .map(FirestoreSerializers.categoryFromDoc)
          .whereType<ExpenseCategory>()
          .toList();
      return DefaultCategories.merge(stored);
    }),
  );

  @override
  String newId() => _store.categories.doc().id;

  @override
  Future<SaveOutcome> save(ExpenseCategory category) => _tracker.track(
    _store.categories
        .doc(category.id)
        .set(FirestoreSerializers.categoryToMap(category)),
    operation: 'saveCategory',
  );

  @override
  Future<SaveOutcome> delete(String id) {
    if (DefaultCategories.isBuiltInId(id)) {
      throw const AppFailure(
        FailureKind.permissionDenied,
        'Built-in categories can be archived but not deleted.',
      );
    }
    return _tracker.track(
      _store.categories.doc(id).delete(),
      operation: 'deleteCategory',
    );
  }
}

class FirestoreBudgetRepository implements BudgetRepository {
  FirestoreBudgetRepository(this._store, this._tracker);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;

  @override
  Stream<List<Budget>> watchAll() => _mapErrors(
    'Budgets',
    _store.budgets.snapshots().map(
      (snap) => snap.docs
          .map(FirestoreSerializers.budgetFromDoc)
          .whereType<Budget>()
          .toList(),
    ),
  );

  @override
  Future<SaveOutcome> save(Budget budget) => _tracker.track(
    _store.budgets.doc(budget.id).set(FirestoreSerializers.budgetToMap(budget)),
    operation: 'saveBudget',
  );

  @override
  Future<SaveOutcome> delete(String id) => _tracker.track(
    _store.budgets.doc(id).delete(),
    operation: 'deleteBudget',
  );

  @override
  Future<bool> claimAlert({
    required String monthKey,
    required String budgetId,
    required int threshold,
  }) async {
    final ref = _store.budgetAlerts.doc('${monthKey}_$budgetId');
    try {
      return await _store.db
          .runTransaction<bool>((tx) async {
            final snap = await tx.get(ref);
            final existing = snap.data()?['threshold'];
            if (existing is int && existing >= threshold) return false;
            tx.set(ref, {
              'monthKey': monthKey,
              'budgetId': budgetId,
              'threshold': threshold,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            return true;
          })
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // Offline or contention: do not notify now; it will be re-evaluated.
      AppLogger.warn('Budgets', 'Alert claim skipped', e);
      return false;
    }
  }
}

class FirestoreDailyStatusRepository implements DailyStatusRepository {
  FirestoreDailyStatusRepository(this._store, this._tracker);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;

  @override
  Stream<Map<LocalDate, StoredDayStatus>> watchRange(DateRange range) =>
      _mapErrors(
        'DailyStatus',
        _store.dailyStatus
            .where('date', isGreaterThanOrEqualTo: range.start.toIso())
            .where('date', isLessThanOrEqualTo: range.end.toIso())
            .snapshots()
            .map((snap) {
              final map = <LocalDate, StoredDayStatus>{};
              for (final doc in snap.docs) {
                final r = FirestoreSerializers.statusFromDoc(doc);
                if (r != null) map[r.date] = r.status;
              }
              return map;
            }),
      );

  @override
  Future<SaveOutcome> setStatus(LocalDate date, StoredDayStatus status) =>
      _tracker.track(
        _store.dailyStatus.doc(date.toIso()).set({
          'date': date.toIso(),
          'status': status.key,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        operation: 'setDayStatus',
      );

  @override
  Future<SaveOutcome> clearStatus(LocalDate date) => _tracker.track(
    _store.dailyStatus.doc(date.toIso()).delete(),
    operation: 'clearDayStatus',
  );
}

class FirestorePreferencesRepository implements PreferencesRepository {
  FirestorePreferencesRepository(this._store, this._tracker, this._locale);

  final FirestoreUserStore _store;
  final WriteTracker _tracker;
  final String _locale;

  UserPreferences get _defaults => UserPreferences.defaultsFor(_locale);

  @override
  Stream<UserPreferences> watch() => _mapErrors(
    'Preferences',
    _store.preferences.snapshots().map(
      (snap) => FirestoreSerializers.preferencesFromMap(snap.data(), _defaults),
    ),
  );

  @override
  Future<SaveOutcome> save(UserPreferences preferences) => _tracker.track(
    _store.preferences.set(FirestoreSerializers.preferencesToMap(preferences)),
    operation: 'savePreferences',
  );

  @override
  Future<void> ensureInitialized() async {
    try {
      final snap = await _store.preferences.get();
      if (!snap.exists) {
        await save(_defaults);
      }
    } catch (e) {
      // Offline on first launch: defaults are used until it can be saved.
      AppLogger.warn('Preferences', 'Could not initialise preferences', e);
    }
  }
}

class FirestoreEntitlementRepository implements EntitlementRepository {
  FirestoreEntitlementRepository(this._store);

  final FirestoreUserStore _store;

  static const _developerPreview =
      kDebugMode && bool.fromEnvironment('PREMIUM_PREVIEW');

  PremiumEntitlement _withPreview(PremiumEntitlement e) => _developerPreview
      ? PremiumEntitlement(
          active: e.active,
          expiresAt: e.expiresAt,
          source: e.source,
          developerPreview: true,
        )
      : e;

  @override
  Stream<PremiumEntitlement> watch() => _store.premium
      .snapshots()
      .map(
        (s) => _withPreview(FirestoreSerializers.entitlementFromMap(s.data())),
      )
      .handleError((Object e) {
        AppLogger.warn('Entitlement', 'Listener error', e);
      });

  @override
  Future<PremiumEntitlement> refresh() async {
    try {
      final snap = await _store.premium.get(
        const GetOptions(source: Source.server),
      );
      return _withPreview(FirestoreSerializers.entitlementFromMap(snap.data()));
    } catch (e) {
      throw FirebaseErrorMapper.firestore(e);
    }
  }
}

class FirestoreUserDataRepository implements UserDataRepository {
  FirestoreUserDataRepository(this._store);

  final FirestoreUserStore _store;

  @override
  Future<void> ensureProfile(UserProfile profile) async {
    try {
      final snap = await _store.userDoc.get();
      // The email lets the admin console identify accounts; the rules only
      // accept the signed-in user's own (token) email.
      if (!snap.exists) {
        await _store.userDoc.set({
          'displayName': profile.displayName ?? '',
          'email': profile.email,
          'createdAt': FieldValue.serverTimestamp(),
          'schemaVersion': 1,
        });
      } else {
        final data = snap.data() ?? const {};
        final changes = <String, Object?>{
          if ((data['displayName'] ?? '') != (profile.displayName ?? ''))
            'displayName': profile.displayName ?? '',
          if (profile.email.isNotEmpty && data['email'] != profile.email)
            'email': profile.email,
        };
        if (changes.isNotEmpty) await _store.userDoc.update(changes);
      }
    } catch (e) {
      AppLogger.warn('UserData', 'ensureProfile failed', e);
    }
  }

  @override
  Future<void> checkServerReachable() async {
    try {
      await _store.userDoc
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw FirebaseErrorMapper.firestore(e).kind == FailureKind.unknown
          ? AppFailure.network
          : FirebaseErrorMapper.firestore(e);
    }
  }

  @override
  Future<DeletionReport> deleteAllUserData({
    void Function(String step)? onProgress,
  }) async {
    var deleted = 0;
    final failed = <String>[];
    for (final name in FirestoreUserStore.userCollections) {
      onProgress?.call('Deleting $name');
      try {
        deleted += await _deleteCollection(_store.userDoc.collection(name));
      } catch (e) {
        AppLogger.warn('UserData', 'Failed deleting $name', e);
        failed.add(name);
      }
    }
    if (failed.isEmpty) {
      onProgress?.call('Deleting profile');
      try {
        await _store.userDoc.delete().timeout(const Duration(seconds: 15));
        deleted++;
      } catch (e) {
        AppLogger.warn('UserData', 'Failed deleting profile', e);
        failed.add('profile');
      }
    }
    return DeletionReport(deletedDocuments: deleted, failed: failed);
  }

  Future<int> _deleteCollection(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    var count = 0;
    while (true) {
      final snap = await col
          .limit(300)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (snap.docs.isEmpty) return count;
      final batch = _store.db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 20));
      count += snap.docs.length;
    }
  }
}
