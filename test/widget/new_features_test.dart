import 'package:daily/app/app_gate.dart';
import 'package:daily/services/sound/sound_effects.dart';
import 'package:daily/features/auth/presentation/onboarding_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

Future<void> _seedExpenses(TestHarness h) async {
  final col = h.db.collection('users/$testUid/expenses');
  final rows = [
    ['e1', '2025-10-14', 4500, 'food', 'card'],
    ['e2', '2025-10-13', 23000, 'groceries', 'cash'],
    ['e3', '2025-10-12', 8990, 'shopping', 'card'],
  ];
  for (final r in rows) {
    await col.doc(r[0] as String).set({
      'amountMinor': r[2],
      'currency': 'USD',
      'categoryId': r[3],
      'date': r[1],
      'paymentMethod': r[4],
      'createdAt': DateTime(2025, 10, 14),
      'updatedAt': DateTime(2025, 10, 14),
      'version': 1,
    });
  }
}

/// Scrolls [finder] into view (e.g. a chip in a horizontal row) and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Finder _check(String label) => find.widgetWithText(CheckboxListTile, label);

Finder _navItem(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Finder _dialogField(int i) => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .at(i);

void main() {
  group('Intro slides', () {
    testWidgets('first-time visitors see the intro once, then the welcome', (
      tester,
    ) async {
      final h = await createHarness(signedIn: false, withOnboarding: true);
      await pumpApp(tester, h);
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Every Expense, Under Control'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await settle(tester, frames: 30);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.text('Create a free account'), findsOneWidget);
      expect(h.prefs.getBool(SharedPreferencesOnboardingStore.key), isTrue);
    });

    testWidgets('signed-in users never see the intro', (tester) async {
      final h = await createHarness(withOnboarding: true);
      await pumpApp(tester, h);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.textContaining('Good evening'), findsOneWidget);
    });
  });

  group('History filters', () {
    testWidgets('filter by category, switch back to all, and clear filters', (
      tester,
    ) async {
      final h = await createHarness();
      await tester.runAsync(() => _seedExpenses(h));
      await pumpApp(tester, h);
      await tester.tap(_navItem('History'));
      await settle(tester);
      expect(find.textContaining('Clear filters'), findsNothing);
      expect(find.text('Groceries'), findsWidgets);

      // Pick a category from the multi-select sheet.
      await _tap(tester, find.text('All categories'));
      await _tap(tester, _check('Food and Drinks'));
      await _tap(tester, find.text('Apply (1)'));
      expect(find.text('Clear filters (1)'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.textContaining('This view needs'), findsNothing);

      // Add a second category: both show, the third doesn't.
      await _tap(tester, find.text('Food and Drinks').first);
      await _tap(tester, _check('Shopping'));
      await _tap(tester, find.text('Apply (2)'));
      expect(find.text('Clear filters (2)'), findsOneWidget);
      expect(find.text('Shopping'), findsWidgets);
      expect(find.text('Groceries'), findsNothing);

      // Each selected value can be removed on its own.
      await _tap(
        tester,
        find.descendant(
          of: find.widgetWithText(InputChip, 'Food and Drinks'),
          matching: find.byTooltip('Remove filter'),
        ),
      );
      expect(find.text('Clear filters (1)'), findsOneWidget);

      // "Clear" in the sheet goes back to all categories.
      await _tap(tester, find.text('Shopping').first);
      await _tap(tester, find.text('Clear'));
      await _tap(tester, find.text('Show all'));
      expect(find.text('Groceries'), findsWidgets);
      expect(find.textContaining('Clear filters'), findsNothing);

      // Combine category and payment filters, then clear them in one tap.
      await _tap(tester, find.text('All categories'));
      await _tap(tester, _check('Shopping'));
      await _tap(tester, find.text('Apply (1)'));
      await _tap(tester, find.text('Any payment'));
      await _tap(tester, _check('Card'));
      await _tap(tester, find.text('Apply (1)'));
      expect(find.text('Clear filters (2)'), findsOneWidget);
      // Search counts as a filter and is cleared with the rest.
      await tester.enterText(
        find.widgetWithText(TextField, 'Search notes and merchants'),
        'zzz',
      );
      await settle(tester);
      expect(find.text('Clear filters (3)'), findsOneWidget);
      await _tap(tester, find.text('Clear filters (3)'));
      expect(find.textContaining('Clear filters'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(find.text('Groceries'), findsWidgets);
      expect(find.text('Shopping'), findsWidgets);
    });
  });

  group('Loans', () {
    testWidgets('add a loan, record a repayment and see the totals', (
      tester,
    ) async {
      final h = await createHarness();
      await pumpApp(tester, h);
      await tester.tap(_navItem('More'));
      await settle(tester);
      // Centre the entry so the translucent navigation bar doesn't cover it.
      await tester.runAsync(
        () => Scrollable.ensureVisible(
          tester.element(find.text('Loans')),
          alignment: 0.5,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Loans'));
      await settle(tester);
      expect(find.text('No active loans'), findsOneWidget);

      await tester.tap(find.text('Add loan'));
      await settle(tester);
      // Validation: amount and name are required.
      await tester.tap(find.text('Save loan'));
      await tester.pump();
      expect(find.text('Enter a name'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '500');
      await tester.enterText(find.byType(TextField).at(1), 'Rahul');
      await tester.tap(find.text('Save loan'));
      await settle(tester);

      expect(find.text('Rahul'), findsOneWidget);
      expect(find.text(r'$500.00'), findsWidgets);
      final stored = await tester.runAsync(
        () => h.db.collection('users/$testUid/loans').get(),
      );
      expect(stored!.docs.single.data()['direction'], 'lent');

      // Record part of it as paid back.
      await tester.tap(find.text('Rahul'));
      await settle(tester);
      await tester.tap(find.text('Record money received'));
      await settle(tester);
      // More than is owed is refused in the dialog.
      await tester.enterText(_dialogField(0), '600');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.textContaining('more than the'), findsOneWidget);

      await tester.enterText(_dialogField(0), '200');
      await tester.enterText(_dialogField(1), 'First instalment');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text(r'$300.00'), findsWidgets);
      expect(find.text('Partially repaid'), findsOneWidget);
      final loans = await tester.runAsync(
        () => h.db.collection('users/$testUid/loans').get(),
      );
      final loan = loans!.docs.single;
      expect(loan.data()['repaidMinor'], 20000);
      expect(loan.data()['settled'], isFalse);
      // The repayment is kept as history under the loan.
      final history = await tester.runAsync(
        () => loan.reference.collection('repayments').get(),
      );
      expect(history!.docs.single.data()['amountMinor'], 20000);
      expect(history.docs.single.data()['note'], 'First instalment');
      // A partial repayment doesn't settle the loan, so no celebration.
      expect(h.sounds.played, isNot(contains(Sfx.celebrate)));

      // Paying the rest closes it, records the final repayment and
      // celebrates.
      await tester.tap(find.text('Rahul'));
      await settle(tester);
      expect(find.text('Repayment history'), findsOneWidget);
      expect(find.textContaining('First instalment'), findsOneWidget);
      await tester.tap(find.text('Mark as fully repaid'));
      await settle(tester);
      final closed = await tester.runAsync(() => loan.reference.get());
      expect(closed!.data()!['repaidMinor'], 50000);
      expect(closed.data()!['settled'], isTrue);
      final full = await tester.runAsync(
        () => loan.reference.collection('repayments').get(),
      );
      expect(full!.docs.map((d) => d.data()['amountMinor']).toSet(), {
        20000,
        30000,
      });
      expect(h.sounds.played, contains(Sfx.celebrate));
      expect(find.text('No active loans'), findsOneWidget);
    });

    testWidgets('borrowed loans, cancelling, search and filters', (
      tester,
    ) async {
      final h = await createHarness();
      final loans = h.db.collection('users/$testUid/loans');
      Map<String, Object?> loan(String name, String direction, int amount) => {
        'direction': direction,
        'personName': name,
        'amountMinor': amount,
        'repaidMinor': 0,
        'currency': 'USD',
        'date': '2025-10-10',
        'settled': false,
      };
      await loans.doc('a').set(loan('Asha', 'lent', 10000));
      await loans.doc('b').set(loan('Ben', 'borrowed', 25000));
      await pumpApp(tester, h);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/loans');
      await settle(tester);

      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('Money borrowed'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Borrowed'));
      await settle(tester);
      expect(find.text('Asha'), findsNothing);
      expect(find.text('Ben'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Search by name'),
        'ash',
      );
      await settle(tester);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Ben'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search by name'),
        '',
      );
      await settle(tester);

      // Cancelling closes the loan without pretending it was repaid.
      await tester.tap(find.text('Ben'));
      await settle(tester);
      expect(find.text('You owe Ben'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel loan'));
      await tester.tap(find.text('Cancel loan'));
      await settle(tester);
      final ben = await tester.runAsync(() => loans.doc('b').get());
      expect(ben!.data()!['cancelled'], isTrue);
      expect(ben.data()!['repaidMinor'], 0);
      expect(find.text('Ben'), findsNothing);
      expect(h.sounds.played, isNot(contains(Sfx.celebrate)));
    });
  });
}
