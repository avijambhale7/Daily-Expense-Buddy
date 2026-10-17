import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily/features/app_lock/app_lock_gate.dart';
import 'package:daily/services/app_lock/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

Future<void> _grantPremium(TestHarness h) =>
    h.db.doc('users/$testUid/entitlements/premium').set({
      'active': true,
      'expiresAt': Timestamp.fromDate(testNow().add(const Duration(days: 3))),
      'source': 'trial',
    });

void _go(WidgetTester tester, String path) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);

void main() {
  testWidgets('free users see an upgrade prompt on premium screens', (
    tester,
  ) async {
    final h = await createHarness();
    await pumpApp(tester, h);
    for (final path in [
      '/settings/recurring',
      '/settings/goals',
      '/settings/advanced-reports',
    ]) {
      _go(tester, path);
      await settle(tester);
      expect(find.text('Unlock with Premium'), findsWidgets, reason: path);
    }
  });

  testWidgets('premium users get due recurring expenses added once', (
    tester,
  ) async {
    final h = await createHarness();
    await tester.runAsync(() async {
      await _grantPremium(h);
      // Rent on the 1st since September: Sep and Oct are due on 14 Oct.
      await h.db.doc('users/$testUid/recurring/rent').set({
        'amountMinor': 1500000,
        'currency': 'USD',
        'categoryId': 'accommodation',
        'frequency': 'monthly',
        'startDate': '2025-09-01',
        'merchant': 'Rent',
        'active': true,
      });
    });
    await pumpApp(tester, h);
    await settle(tester, frames: 20);

    final expenses = await tester.runAsync(
      () => h.db.collection('users/$testUid/expenses').get(),
    );
    expect(expenses!.docs.map((d) => d.id).toSet(), {
      'rec_rent_2025-09-01',
      'rec_rent_2025-10-01',
    });
    final template = await tester.runAsync(
      () => h.db.doc('users/$testUid/recurring/rent').get(),
    );
    expect(template!.data()!['lastPostedDate'], '2025-10-01');

    _go(tester, '/settings/recurring');
    await settle(tester);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.textContaining('Next'), findsOneWidget);
  });

  testWidgets('premium users create a savings goal and add money', (
    tester,
  ) async {
    final h = await createHarness();
    await tester.runAsync(() => _grantPremium(h));
    await pumpApp(tester, h);
    _go(tester, '/settings/goals');
    await settle(tester);

    await tester.tap(find.text('Create a goal'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Goal name'), 'Trip');
    await tester.enterText(
      find.widgetWithText(TextField, 'Target amount'),
      '1000',
    );
    await tester.tap(find.text('Create goal'));
    await settle(tester);
    expect(find.text('Trip'), findsOneWidget);

    await tester.tap(find.text('Add money'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '250');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);
    final goals = await tester.runAsync(
      () => h.db.collection('users/$testUid/goals').get(),
    );
    expect(goals!.docs.single.data()['savedMinor'], 25000);
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('with a PIN set the app opens on the lock screen', (
    tester,
  ) async {
    final h = await createHarness(withAppLock: true);
    await SharedPreferencesAppLockStore(h.prefs).setPin('2580');
    await pumpApp(tester, h);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('Enter your PIN'), findsOneWidget);

    for (final d in ['1', '1', '1', '1']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);

    for (final d in ['2', '5', '8', '0']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await settle(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.textContaining('Good evening'), findsOneWidget);
  });

  testWidgets('logging out removes the PIN from the device', (tester) async {
    final h = await createHarness(withAppLock: true);
    final store = SharedPreferencesAppLockStore(h.prefs);
    await store.setPin('2580');
    await pumpApp(tester, h);
    await tester.tap(find.text('Forgot PIN?'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await settle(tester);
    expect(store.enabled, isFalse);
  });
}
