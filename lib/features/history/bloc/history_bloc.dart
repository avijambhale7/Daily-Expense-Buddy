import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/session_cubits.dart';
import '../../../core/errors/app_failure.dart';
import '../../../domain/models/expense.dart';
import '../../../domain/models/expense_filter.dart';
import '../../../domain/repositories/repositories.dart';

sealed class HistoryEvent {
  const HistoryEvent();
}

class HistoryStarted extends HistoryEvent {
  const HistoryStarted();
}

class HistoryFilterChanged extends HistoryEvent {
  const HistoryFilterChanged(this.filter);
  final ExpenseFilter filter;
}

class HistorySearchChanged extends HistoryEvent {
  const HistorySearchChanged(this.query);
  final String query;
}

class HistoryLoadMore extends HistoryEvent {
  const HistoryLoadMore();
}

/// Removes every filter and the search text (the sort order is kept).
class HistoryFiltersCleared extends HistoryEvent {
  const HistoryFiltersCleared();
}

/// Re-runs the current query after a failure.
class HistoryRetried extends HistoryEvent {
  const HistoryRetried();
}

class _HistoryPageReceived extends HistoryEvent {
  const _HistoryPageReceived(this.page, this.generation);
  final ExpensePage page;
  final int generation;
}

class _HistoryFailed extends HistoryEvent {
  const _HistoryFailed(this.message, this.generation);
  final String message;
  final int generation;
}

class HistoryState extends Equatable {
  const HistoryState({
    this.status = LoadStatus.loading,
    this.items = const [],
    this.filter = const ExpenseFilter(),
    this.query = '',
    this.limit = HistoryBloc.pageSize,
    this.hasMore = false,
    this.loadingMore = false,
    this.error,
  });

  final LoadStatus status;

  /// Loaded items (server-filtered). Use [visible] for display.
  final List<Expense> items;
  final ExpenseFilter filter;
  final String query;
  final int limit;
  final bool hasMore;
  final bool loadingMore;
  final String? error;

  /// Number of active filters, counting a non-empty search as one.
  int get activeFilterCount =>
      (filter.range != null ? 1 : 0) +
      (filter.categoryId != null ? 1 : 0) +
      (filter.paymentMethod != null ? 1 : 0) +
      (query.trim().isNotEmpty ? 1 : 0);

  /// Items matching the client-side text search.
  List<Expense> get visible => query.trim().isEmpty
      ? items
      : items.where((e) => ExpenseSearch.matches(e, query)).toList();

  HistoryState copyWith({
    LoadStatus? status,
    List<Expense>? items,
    ExpenseFilter? filter,
    String? query,
    int? limit,
    bool? hasMore,
    bool? loadingMore,
    String? Function()? error,
  }) {
    return HistoryState(
      status: status ?? this.status,
      items: items ?? this.items,
      filter: filter ?? this.filter,
      query: query ?? this.query,
      limit: limit ?? this.limit,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error != null ? error() : this.error,
    );
  }

  @override
  List<Object?> get props => [
    status,
    items,
    filter,
    query,
    limit,
    hasMore,
    loadingMore,
    error,
  ];
}

/// Transaction history with server-side filters, client-side text search and
/// incremental loading.
///
/// The list is a live Firestore query limited to [HistoryState.limit] items;
/// "load more" raises the limit by [pageSize]. Because the query is live,
/// edits and deletions from other devices appear without refreshing, and
/// the app never downloads more history than the user has scrolled to.
class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc(this._repository) : super(const HistoryState()) {
    on<HistoryStarted>((_, emit) => _listen(emit));
    on<HistoryFilterChanged>((event, emit) {
      emit(
        state.copyWith(
          filter: event.filter,
          limit: pageSize,
          status: LoadStatus.loading,
          items: const [],
          hasMore: false,
          loadingMore: false,
          error: () => null,
        ),
      );
      _listen(emit);
    });
    on<HistoryFiltersCleared>((_, emit) {
      emit(
        state.copyWith(
          filter: ExpenseFilter(newestFirst: state.filter.newestFirst),
          query: '',
          limit: pageSize,
          status: LoadStatus.loading,
          items: const [],
          hasMore: false,
          loadingMore: false,
          error: () => null,
        ),
      );
      _listen(emit);
    });
    on<HistoryRetried>((_, emit) {
      emit(
        state.copyWith(
          status: LoadStatus.loading,
          loadingMore: false,
          error: () => null,
        ),
      );
      _listen(emit);
    });
    on<HistorySearchChanged>(
      (event, emit) => emit(state.copyWith(query: event.query)),
    );
    on<HistoryLoadMore>((_, emit) {
      if (!state.hasMore || state.loadingMore) return;
      emit(state.copyWith(limit: state.limit + pageSize, loadingMore: true));
      _listen(emit);
    });
    on<_HistoryPageReceived>((event, emit) {
      if (event.generation != _generation) return;
      emit(
        state.copyWith(
          status: LoadStatus.ready,
          items: event.page.items,
          hasMore: event.page.hasMore,
          loadingMore: false,
          error: () => null,
        ),
      );
    });
    on<_HistoryFailed>((event, emit) {
      if (event.generation != _generation) return;
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          loadingMore: false,
          error: () => event.message,
        ),
      );
    });
  }

  static const int pageSize = 30;

  final ExpenseRepository _repository;
  StreamSubscription<ExpensePage>? _sub;

  /// Incremented for every new query; results tagged with an older value
  /// belong to a superseded filter or page size and are dropped.
  int _generation = 0;

  void _listen(Emitter<HistoryState> emit) {
    unawaited(_sub?.cancel());
    final generation = ++_generation;
    _sub = _repository
        .watchHistory(state.filter, limit: state.limit)
        .listen(
          (page) => add(_HistoryPageReceived(page, generation)),
          onError: (Object e) => add(
            _HistoryFailed(
              e is AppFailure ? e.message : AppFailure.unknown(e).message,
              generation,
            ),
          ),
        );
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
