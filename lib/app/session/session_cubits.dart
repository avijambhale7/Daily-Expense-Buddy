import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/expense_category.dart';
import '../../domain/models/premium_entitlement.dart';
import '../../domain/models/user_preferences.dart';
import '../../domain/repositories/repositories.dart';

enum LoadStatus { loading, ready, failure }

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

class PreferencesState extends Equatable {
  const PreferencesState({
    required this.preferences,
    this.status = LoadStatus.loading,
    this.error,
  });

  final UserPreferences preferences;
  final LoadStatus status;
  final String? error;

  @override
  List<Object?> get props => [preferences, status, error];
}

class PreferencesCubit extends Cubit<PreferencesState> {
  PreferencesCubit(this._repo, {required UserPreferences defaults})
    : super(PreferencesState(preferences: defaults)) {
    _sub = _repo.watch().listen(
      (p) => emit(PreferencesState(preferences: p, status: LoadStatus.ready)),
      onError: (Object e) => emit(
        PreferencesState(
          preferences: state.preferences,
          status: LoadStatus.failure,
          error: e is AppFailure ? e.message : AppFailure.unknown(e).message,
        ),
      ),
    );
    unawaited(_repo.ensureInitialized());
  }

  final PreferencesRepository _repo;
  StreamSubscription<UserPreferences>? _sub;

  UserPreferences get preferences => state.preferences;

  /// Applies the change locally at once; Firestore syncs it.
  Future<SaveOutcome> update(UserPreferences preferences) async {
    emit(PreferencesState(preferences: preferences, status: state.status));
    return _repo.save(preferences);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

class CategoriesState extends Equatable {
  CategoriesState({
    List<ExpenseCategory>? categories,
    this.status = LoadStatus.loading,
    this.error,
  }) : categories = categories ?? DefaultCategories.all,
       _byId = {for (final c in categories ?? DefaultCategories.all) c.id: c};

  final List<ExpenseCategory> categories;
  final LoadStatus status;
  final String? error;
  final Map<String, ExpenseCategory> _byId;

  Map<String, ExpenseCategory> get byId => _byId;

  List<ExpenseCategory> get active =>
      categories.where((c) => !c.isArchived).toList();

  /// Resolves an id, including archived and unknown categories, so that
  /// historical expenses always render.
  ExpenseCategory resolve(String id) =>
      _byId[id] ?? ExpenseCategory.unknown(id);

  @override
  List<Object?> get props => [categories, status, error];
}

class CategoriesCubit extends Cubit<CategoriesState> {
  CategoriesCubit(this._repo, this._expenses) : super(CategoriesState()) {
    _sub = _repo.watchAll().listen(
      (list) =>
          emit(CategoriesState(categories: list, status: LoadStatus.ready)),
      onError: (Object e) {
        AppLogger.warn('Categories', 'Load failed', e);
        emit(
          CategoriesState(
            categories: state.categories,
            status: LoadStatus.failure,
            error: e is AppFailure ? e.message : AppFailure.unknown(e).message,
          ),
        );
      },
    );
  }

  final CategoryRepository _repo;
  final ExpenseRepository _expenses;
  StreamSubscription<List<ExpenseCategory>>? _sub;

  String newId() => _repo.newId();

  Future<SaveOutcome> save(ExpenseCategory category) => _repo.save(category);

  Future<SaveOutcome> setArchived(ExpenseCategory category, bool archived) =>
      _repo.save(category.copyWith(isArchived: archived));

  /// Deletes a custom category only when no expense uses it. Otherwise the
  /// caller should offer archiving, which keeps history intact.
  Future<bool> deleteIfUnused(ExpenseCategory category) async {
    if (category.isBuiltIn) return false;
    if (await _expenses.isCategoryUsed(category.id)) return false;
    await _repo.delete(category.id);
    return true;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

// ---------------------------------------------------------------------------
// Premium entitlement
// ---------------------------------------------------------------------------

class EntitlementCubit extends Cubit<PremiumEntitlement> {
  EntitlementCubit(this._repo) : super(PremiumEntitlement.none) {
    _sub = _repo.watch().listen(emit);
  }

  final EntitlementRepository _repo;
  StreamSubscription<PremiumEntitlement>? _sub;

  /// Re-reads the entitlement from the server ("restore purchases").
  Future<void> refresh() async => emit(await _repo.refresh());

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
