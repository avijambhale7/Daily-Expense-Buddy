import 'package:daily/core/dates/local_date.dart';
import 'package:daily/core/errors/app_failure.dart';
import 'package:daily/data/firebase/firestore_expense_repository.dart';
import 'package:daily/data/firebase/firestore_repositories.dart';
import 'package:daily/domain/models/loan.dart';
import 'package:daily/data/firebase/firestore_loan_repository.dart';
import 'package:daily/data/firebase/firestore_user_store.dart';
import 'package:daily/data/firebase/write_tracker.dart';
import 'package:daily/domain/models/daily_status.dart';
import 'package:daily/domain/models/expense.dart';
import 'package:daily/domain/models/expense_category.dart';
import 'package:daily/domain/models/expense_filter.dart';
import 'package:daily/domain/repositories/repositories.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late WriteTracker tracker;

  FirestoreExpenseRepository expensesFor(String uid) =>
      FirestoreExpenseRepository(FirestoreUserStore(db, uid), tracker);

  Expense expense(
    FirestoreExpenseRepository repo,
    String date,
    int amount, {
    String cat = 'food',
    PaymentMethod? method,
    String? merchant,
  }) => Expense(
    id: repo.newId(),
    amountMinor: amount,
    currencyCode: 'INR',
    categoryId: cat,
    date: LocalDate.parse(date),
    paymentMethod: method,
    merchant: merchant,
  );

  setUp(() {
    db = FakeFirebaseFirestore();
    tracker = WriteTracker(SyncIssueReporter());
  });

  group('FirestoreExpenseRepository', () {
    test('creates, reads, updates and deletes an expense', () async {
      final repo = expensesFor('alice');
      final e = expense(repo, '2025-10-14', 12050, merchant: 'Cafe');
      expect(await repo.create(e), SaveOutcome.synced);

      final stored = await repo.watchExpense(e.id).first;
      expect(stored!.amountMinor, 12050);
      expect(stored.date, LocalDate(2025, 10, 14));
      expect(stored.merchant, 'Cafe');
      expect(stored.version, 1);

      final raw = await db.doc('users/alice/expenses/${e.id}').get();
      expect(raw.data()!['date'], '2025-10-14');
      expect(raw.data()!['amountMinor'], 12050);
      expect(
        raw.data()!.containsKey('uid'),
        isFalse,
        reason: 'ownership comes from the path',
      );

      await repo.update(
        stored.copyWith(amountMinor: 9900, merchant: () => null),
      );
      final updated = await repo.watchExpense(e.id).first;
      expect(updated!.amountMinor, 9900);
      expect(updated.merchant, isNull);
      expect(updated.version, 2);

      await repo.delete(e.id);
      expect(await repo.watchExpense(e.id).first, isNull);
    });

    test('re-submitting the same id does not create a duplicate', () async {
      final repo = expensesFor('alice');
      final e = expense(repo, '2025-10-14', 500);
      await repo.create(e);
      await repo.create(e);
      final all = await repo.fetch(const ExpenseFilter());
      expect(all.length, 1);
    });

    test(
      'watchRange returns only expenses within the inclusive range',
      () async {
        final repo = expensesFor('alice');
        for (final d in [
          '2025-09-30',
          '2025-10-01',
          '2025-10-31',
          '2025-11-01',
        ]) {
          await repo.create(expense(repo, d, 100));
        }
        final list = await repo
            .watchRange(
              DateRange(LocalDate(2025, 10, 1), LocalDate(2025, 10, 31)),
            )
            .first;
        expect(list.map((e) => e.date.toIso()).toList()..sort(), [
          '2025-10-01',
          '2025-10-31',
        ]);
      },
    );

    test("one user's data is never visible to another user", () async {
      final alice = expensesFor('alice');
      final bob = expensesFor('bob');
      await alice.create(expense(alice, '2025-10-14', 100));
      await bob.create(expense(bob, '2025-10-14', 200));

      final range = DateRange(LocalDate(2025, 1, 1), LocalDate(2025, 12, 31));
      final aliceList = await alice.watchRange(range).first;
      final bobList = await bob.watchRange(range).first;
      expect(aliceList.map((e) => e.amountMinor), [100]);
      expect(bobList.map((e) => e.amountMinor), [200]);
      expect(await alice.fetch(const ExpenseFilter()), hasLength(1));
    });

    test('history is paginated and filterable', () async {
      final repo = expensesFor('alice');
      for (var i = 1; i <= 5; i++) {
        await repo.create(
          expense(
            repo,
            '2025-10-0$i',
            i * 100,
            cat: i.isEven ? 'transport' : 'food',
            method: i == 3 ? PaymentMethod.cash : null,
          ),
        );
      }
      final page = await repo
          .watchHistory(const ExpenseFilter(), limit: 3)
          .first;
      expect(page.items.length, 3);
      expect(page.hasMore, isTrue);
      expect(
        page.items.first.date,
        LocalDate(2025, 10, 5),
        reason: 'newest first',
      );

      final all = await repo
          .watchHistory(const ExpenseFilter(), limit: 10)
          .first;
      expect(all.hasMore, isFalse);

      final oldest = await repo
          .watchHistory(const ExpenseFilter(newestFirst: false), limit: 1)
          .first;
      expect(oldest.items.single.date, LocalDate(2025, 10, 1));

      final transport = await repo
          .watchHistory(
            const ExpenseFilter(categoryIds: {'transport'}),
            limit: 10,
          )
          .first;
      expect(transport.items.map((e) => e.amountMinor).toSet(), {200, 400});

      final cash = await repo
          .watchHistory(
            const ExpenseFilter(paymentMethods: {PaymentMethod.cash}),
            limit: 10,
          )
          .first;
      expect(cash.items.single.amountMinor, 300);

      // Filtered queries honour the page limit on the server and keep the
      // newest-first order, so "load more" works with filters too.
      final firstFood = await repo
          .watchHistory(const ExpenseFilter(categoryIds: {'food'}), limit: 1)
          .first;
      expect(firstFood.items.single.amountMinor, 500);
      expect(firstFood.hasMore, isTrue);

      // Category, payment method and date range combine.
      final combined = await repo
          .watchHistory(
            ExpenseFilter(
              categoryIds: {'food'},
              range: DateRange(LocalDate(2025, 10, 2), LocalDate(2025, 10, 4)),
            ),
            limit: 10,
          )
          .first;
      expect(combined.items.map((e) => e.amountMinor), [300]);
      final none = await repo
          .watchHistory(
            const ExpenseFilter(
              categoryIds: {'transport'},
              paymentMethods: {PaymentMethod.cash},
            ),
            limit: 10,
          )
          .first;
      expect(none.items, isEmpty);
      expect(none.hasMore, isFalse);

      // Several categories and several payment methods at once.
      final both = await repo
          .watchHistory(
            const ExpenseFilter(categoryIds: {'food', 'transport'}),
            limit: 10,
          )
          .first;
      expect(both.items, hasLength(5));
      final multi = await repo
          .watchHistory(
            const ExpenseFilter(
              categoryIds: {'food', 'transport'},
              paymentMethods: {PaymentMethod.cash, PaymentMethod.card},
            ),
            limit: 10,
          )
          .first;
      expect(multi.items.map((e) => e.amountMinor), [300]);

      expect(await repo.isCategoryUsed('transport'), isTrue);
      expect(await repo.isCategoryUsed('travel'), isFalse);
    });

    test(
      'malformed documents are skipped instead of crashing the list',
      () async {
        final repo = expensesFor('alice');
        await repo.create(expense(repo, '2025-10-14', 100));
        await db.collection('users/alice/expenses').add({
          'amountMinor': 'oops',
        });
        final list = await repo.fetch(const ExpenseFilter());
        expect(list.length, 1);
      },
    );
  });

  group('Other repositories', () {
    test(
      'categories merge built-ins with overrides; built-ins cannot be deleted',
      () async {
        final store = FirestoreUserStore(db, 'alice');
        final repo = FirestoreCategoryRepository(store, tracker);
        final food = DefaultCategories.all.first;
        await repo.save(food.copyWith(name: 'Dining', isArchived: true));
        final custom = ExpenseCategory(
          id: repo.newId(),
          name: 'Pets',
          iconKey: 'pets',
          colorIndex: 2,
          sortOrder: 200,
        );
        await repo.save(custom);

        final list = await repo.watchAll().first;
        expect(list.firstWhere((c) => c.id == food.id).name, 'Dining');
        expect(list.firstWhere((c) => c.id == food.id).isArchived, isTrue);
        expect(list.any((c) => c.name == 'Pets'), isTrue);
        expect(() => repo.delete(food.id), throwsA(isA<AppFailure>()));
        await repo.delete(custom.id);
        expect(
          (await repo.watchAll().first).any((c) => c.name == 'Pets'),
          isFalse,
        );
      },
    );

    test('daily statuses are stored separately and can be cleared', () async {
      final repo = FirestoreDailyStatusRepository(
        FirestoreUserStore(db, 'alice'),
        tracker,
      );
      final day = LocalDate(2025, 10, 13);
      await repo.setStatus(day, StoredDayStatus.noExpenses);
      final range = DateRange(LocalDate(2025, 10, 1), LocalDate(2025, 10, 31));
      expect(
        (await repo.watchRange(range).first)[day],
        StoredDayStatus.noExpenses,
      );
      await repo.clearStatus(day);
      expect((await repo.watchRange(range).first).containsKey(day), isFalse);
      // Another user's statuses are separate.
      final bob = FirestoreDailyStatusRepository(
        FirestoreUserStore(db, 'bob'),
        tracker,
      );
      await repo.setStatus(day, StoredDayStatus.completed);
      expect(await bob.watchRange(range).first, isEmpty);
    });

    test(
      'preferences fall back to locale defaults and persist changes',
      () async {
        final repo = FirestorePreferencesRepository(
          FirestoreUserStore(db, 'alice'),
          tracker,
          'en_IN',
        );
        final defaults = await repo.watch().first;
        expect(defaults.currencyCode, 'INR');
        await repo.ensureInitialized();
        expect(
          (await db.doc('users/alice/settings/preferences').get()).exists,
          isTrue,
        );
        await repo.save(
          defaults.copyWith(currencyCode: 'EUR', weekStart: DateTime.monday),
        );
        final saved = await repo.watch().first;
        expect(saved.currencyCode, 'EUR');
        expect(saved.weekStart, DateTime.monday);
      },
    );

    test('budget alerts are claimed only once per threshold', () async {
      final repo = FirestoreBudgetRepository(
        FirestoreUserStore(db, 'alice'),
        tracker,
      );
      expect(
        await repo.claimAlert(
          monthKey: '2025-10',
          budgetId: 'overall',
          threshold: 80,
        ),
        isTrue,
      );
      expect(
        await repo.claimAlert(
          monthKey: '2025-10',
          budgetId: 'overall',
          threshold: 80,
        ),
        isFalse,
      );
      expect(
        await repo.claimAlert(
          monthKey: '2025-10',
          budgetId: 'overall',
          threshold: 100,
        ),
        isTrue,
      );
      expect(
        await repo.claimAlert(
          monthKey: '2025-11',
          budgetId: 'overall',
          threshold: 80,
        ),
        isTrue,
      );
    });

    test('entitlement defaults to free when no server record exists', () async {
      final repo = FirestoreEntitlementRepository(
        FirestoreUserStore(db, 'alice'),
      );
      final e = await repo.watch().first;
      expect(e.isPremium(DateTime(2025)), isFalse);
      await db.doc('users/alice/entitlements/premium').set({
        'active': true,
        'source': 'manual',
      });
      expect((await repo.watch().first).isPremium(DateTime(2025)), isTrue);
    });

    test(
      'deleteAllUserData removes every collection and the profile',
      () async {
        final store = FirestoreUserStore(db, 'alice');
        final repo = FirestoreUserDataRepository(store);
        final expenses = FirestoreExpenseRepository(store, tracker);
        await store.userDoc.set({'displayName': 'A'});
        for (var i = 0; i < 5; i++) {
          await expenses.create(expense(expenses, '2025-10-0${i + 1}', 100));
        }
        await FirestoreDailyStatusRepository(
          store,
          tracker,
        ).setStatus(LocalDate(2025, 10, 1), StoredDayStatus.completed);
        await db.doc('users/bob/expenses/x').set({'amountMinor': 1});

        final report = await repo.deleteAllUserData();
        expect(report.isComplete, isTrue);
        expect(report.deletedDocuments, 7);
        expect((await store.expenses.get()).docs, isEmpty);
        expect((await store.userDoc.get()).exists, isFalse);
        expect(
          (await db.doc('users/bob/expenses/x').get()).exists,
          isTrue,
          reason: 'other users untouched',
        );
      },
    );
  });

  group('FirestoreLoanRepository', () {
    FirestoreLoanRepository loansFor(String uid) =>
        FirestoreLoanRepository(FirestoreUserStore(db, uid), tracker);

    Loan loan(FirestoreLoanRepository repo, {int amount = 500000}) => Loan(
      id: repo.newId(),
      direction: LoanDirection.lent,
      personName: 'Rahul',
      amountMinor: amount,
      currencyCode: 'INR',
      date: LocalDate(2025, 10, 1),
    );

    LoanRepayment pay(FirestoreLoanRepository repo, Loan l, int amount) =>
        LoanRepayment(
          id: repo.newRepaymentId(l.id),
          amountMinor: amount,
          date: LocalDate(2025, 10, 5),
        );

    test(
      'partial then full repayment keeps history and totals in step',
      () async {
        final repo = loansFor('alice');
        var l = loan(repo);
        await repo.create(l);

        await repo.addRepayment(l, pay(repo, l, 200000));
        l = (await repo.watchAll().first).single;
        expect(l.repaidMinor, 200000);
        expect(l.status, LoanStatus.partiallyRepaid);

        await repo.addRepayment(l, pay(repo, l, 300000));
        l = (await repo.watchAll().first).single;
        expect(l.status, LoanStatus.fullyRepaid);
        expect(l.settled, isTrue);

        final history = await repo.watchRepayments(l.id).first;
        expect(history.map((r) => r.amountMinor).toSet(), {200000, 300000});
        expect(
          history.fold<int>(0, (sum, r) => sum + r.amountMinor),
          l.repaidMinor,
        );
      },
    );

    test('over-payments are refused before anything is written', () async {
      final repo = loansFor('alice');
      final l = loan(repo, amount: 1000);
      await repo.create(l);
      expect(
        () => repo.addRepayment(l, pay(repo, l, 1001)),
        throwsArgumentError,
      );
      expect(await repo.watchRepayments(l.id).first, isEmpty);
      expect((await repo.watchAll().first).single.repaidMinor, 0);
    });

    test('deleting a loan removes its repayment history', () async {
      final repo = loansFor('alice');
      final l = loan(repo);
      await repo.create(l);
      await repo.addRepayment(l, pay(repo, l, 1000));
      await repo.delete(l.id);
      expect(await repo.watchAll().first, isEmpty);
      final left = await db
          .collection('users/alice/loans/${l.id}/repayments')
          .get();
      expect(left.docs, isEmpty);
    });

    test("one user's loans are never visible to another", () async {
      final alice = loansFor('alice');
      final bob = loansFor('bob');
      final l = loan(alice);
      await alice.create(l);
      await alice.addRepayment(l, pay(alice, l, 1000));
      expect(await bob.watchAll().first, isEmpty);
      expect(await bob.watchRepayments(l.id).first, isEmpty);
    });
  });
}
