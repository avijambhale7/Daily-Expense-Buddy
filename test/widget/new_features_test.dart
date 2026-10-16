import 'package:daily/app/app_gate.dart';
import 'package:daily/services/sound/sound_effects.dart';
import 'package:daily/features/auth/presentation/onboarding_page.dart';
import 'package:flutter_test/flutter_test.dart';
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

Finder _navItem(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  group('Intro slides', () {
    testWidgets('first-time visitors see the intro once, then the welcome', (
      tester,
    ) async {
      final h = await createHarness(signedIn: false, withOnboarding: true);
      await pumpApp(tester, h);
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Log expenses in seconds'), findsOneWidget);

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
      expect(find.text('Clear filters'), findsNothing);
      expect(find.text('Groceries'), findsWidgets);

      // Pick a category from the sheet.
      await _tap(tester, find.text('All categories'));
      await _tap(tester, find.text('Food and Drinks').last);
      expect(find.text('Clear filters'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.textContaining('This view needs'), findsNothing);

      // "All categories" in the sheet removes the filter again.
      await _tap(tester, find.text('Food and Drinks').first);
      await _tap(tester, find.text('All categories').last);
      expect(find.text('Groceries'), findsWidgets);

      // Combine two filters, then clear them in one tap.
      await _tap(tester, find.text('All categories'));
      await _tap(tester, find.text('Shopping').last);
      await _tap(tester, find.text('Any payment'));
      await _tap(tester, find.text('Card').last);
      expect(find.text('Clear filters'), findsOneWidget);
      await _tap(tester, find.text('Clear filters'));
      expect(find.text('Clear filters'), findsNothing);
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
      await tester.enterText(find.byType(TextField).last, '200');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text(r'$300.00'), findsWidgets);
      final after = await tester.runAsync(
        () => h.db.collection('users/$testUid/loans').get(),
      );
      expect(after!.docs.single.data()['repaidMinor'], 20000);
      // A partial repayment doesn't settle the loan, so no celebration.
      expect(h.sounds.played, isNot(contains(Sfx.celebrate)));
    });
  });
}
