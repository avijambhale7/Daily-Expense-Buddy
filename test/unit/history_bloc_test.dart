import 'dart:async';

import 'package:daily/app/session/session_cubits.dart';
import 'package:daily/core/dates/local_date.dart';
import 'package:daily/core/errors/app_failure.dart';
import 'package:daily/domain/models/expense.dart';
import 'package:daily/domain/models/expense_filter.dart';
import 'package:daily/domain/repositories/repositories.dart';
import 'package:daily/features/history/bloc/history_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every history query and lets the test decide when (and with
/// what) each one answers.
class _ControlledRepo implements ExpenseRepository {
  final queries = <({ExpenseFilter filter, int limit})>[];
  final _controllers = <StreamController<ExpensePage>>[];

  StreamController<ExpensePage> get last => _controllers.last;
  StreamController<ExpensePage> at(int i) => _controllers[i];

  @override
  Stream<ExpensePage> watchHistory(ExpenseFilter filter, {required int limit}) {
    queries.add((filter: filter, limit: limit));
    final c = StreamController<ExpensePage>();
    _controllers.add(c);
    return c.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Expense _e(String id, {String? note}) => Expense(
  id: id,
  amountMinor: 100,
  currencyCode: 'INR',
  categoryId: 'food',
  date: LocalDate(2025, 10, 1),
  note: note,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _ControlledRepo repo;
  late HistoryBloc bloc;

  setUp(() {
    repo = _ControlledRepo();
    bloc = HistoryBloc(repo);
  });

  tearDown(() => bloc.close());

  test('selecting a category queries with it and shows its results', () async {
    bloc.add(const HistoryStarted());
    await _settle();
    repo.last.add(ExpensePage([_e('a'), _e('b')], hasMore: false));
    await _settle();
    expect(bloc.state.items, hasLength(2));

    bloc.add(const HistoryFilterChanged(ExpenseFilter(categoryId: 'food')));
    await _settle();
    expect(repo.queries.last.filter.categoryId, 'food');
    expect(bloc.state.status, LoadStatus.loading);
    expect(bloc.state.items, isEmpty, reason: 'old results are not reused');

    repo.last.add(ExpensePage([_e('c')], hasMore: false));
    await _settle();
    expect(bloc.state.items.map((e) => e.id), ['c']);
    expect(bloc.state.activeFilterCount, 1);
  });

  test('removing a category goes back to the unfiltered query', () async {
    bloc.add(const HistoryFilterChanged(ExpenseFilter(categoryId: 'food')));
    await _settle();
    bloc.add(
      HistoryFilterChanged(bloc.state.filter.copyWith(categoryId: () => null)),
    );
    await _settle();
    expect(repo.queries.last.filter.hasFilters, isFalse);
    expect(bloc.state.activeFilterCount, 0);
  });

  test('a late answer from a superseded filter is ignored', () async {
    bloc.add(const HistoryStarted());
    await _settle();
    bloc.add(const HistoryFilterChanged(ExpenseFilter(categoryId: 'food')));
    await _settle();

    // The first (unfiltered) query answers after the filter changed.
    repo.at(0).add(ExpensePage([_e('stale')], hasMore: false));
    await _settle();
    expect(bloc.state.items, isEmpty);
    expect(bloc.state.status, LoadStatus.loading);

    repo.at(1).add(ExpensePage([_e('fresh')], hasMore: false));
    await _settle();
    expect(bloc.state.items.map((e) => e.id), ['fresh']);
  });

  test('changing filters while paginated resets the page size', () async {
    bloc.add(const HistoryStarted());
    await _settle();
    repo.last.add(
      ExpensePage(
        List.generate(HistoryBloc.pageSize, (i) => _e('$i')),
        hasMore: true,
      ),
    );
    await _settle();
    bloc.add(const HistoryLoadMore());
    await _settle();
    expect(repo.queries.last.limit, HistoryBloc.pageSize * 2);

    bloc.add(
      HistoryFilterChanged(
        ExpenseFilter(
          range: DateRange(LocalDate(2025, 10, 1), LocalDate(2025, 10, 31)),
          categoryId: 'food',
        ),
      ),
    );
    await _settle();
    expect(repo.queries.last.limit, HistoryBloc.pageSize);
    expect(bloc.state.hasMore, isFalse);
    expect(bloc.state.activeFilterCount, 2);
  });

  test(
    'load more keeps one live list, so items are never duplicated',
    () async {
      bloc.add(const HistoryStarted());
      await _settle();
      final first = List.generate(HistoryBloc.pageSize, (i) => _e('$i'));
      repo.last.add(ExpensePage(first, hasMore: true));
      await _settle();
      bloc.add(const HistoryLoadMore());
      await _settle();
      final more = [...first, _e('extra')];
      repo.last.add(ExpensePage(more, hasMore: false));
      await _settle();
      final ids = bloc.state.items.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.length, HistoryBloc.pageSize + 1);
    },
  );

  test('search works together with filters', () async {
    bloc.add(const HistoryFilterChanged(ExpenseFilter(categoryId: 'food')));
    await _settle();
    repo.last.add(
      ExpensePage([
        _e('a', note: 'Lunch with team'),
        _e('b', note: 'Groceries'),
      ], hasMore: false),
    );
    await _settle();
    bloc.add(const HistorySearchChanged('lunch'));
    await _settle();
    expect(bloc.state.visible.map((e) => e.id), ['a']);
    expect(bloc.state.activeFilterCount, 2);
  });

  test('clear filters removes every filter and the search text', () async {
    bloc.add(
      HistoryFilterChanged(
        ExpenseFilter(
          categoryId: 'food',
          paymentMethod: PaymentMethod.cash,
          range: DateRange(LocalDate(2025, 10, 1), LocalDate(2025, 10, 31)),
          newestFirst: false,
        ),
      ),
    );
    bloc.add(const HistorySearchChanged('coffee'));
    await _settle();
    expect(bloc.state.activeFilterCount, 4);

    bloc.add(const HistoryFiltersCleared());
    await _settle();
    expect(bloc.state.activeFilterCount, 0);
    expect(bloc.state.query, isEmpty);
    expect(repo.queries.last.filter.hasFilters, isFalse);
    expect(
      repo.queries.last.filter.newestFirst,
      isFalse,
      reason: 'sort order is a preference, not a filter',
    );
  });

  test('empty results are a ready state, not an error', () async {
    bloc.add(const HistoryStarted());
    await _settle();
    repo.last.add(const ExpensePage([], hasMore: false));
    await _settle();
    expect(bloc.state.status, LoadStatus.ready);
    expect(bloc.state.visible, isEmpty);
  });

  test('a failed query shows an error and retry queries again', () async {
    bloc.add(const HistoryStarted());
    await _settle();
    repo.last.addError(AppFailure.network);
    await _settle();
    expect(bloc.state.status, LoadStatus.failure);
    expect(bloc.state.error, AppFailure.network.message);

    bloc.add(const HistoryRetried());
    await _settle();
    expect(repo.queries, hasLength(2));
    expect(bloc.state.status, LoadStatus.loading);

    repo.last.add(ExpensePage([_e('a')], hasMore: false));
    await _settle();
    expect(bloc.state.status, LoadStatus.ready);
    expect(bloc.state.error, isNull);
  });
}
