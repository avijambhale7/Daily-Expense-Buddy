import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily/features/admin/presentation/admin_console.dart';
import 'package:daily/features/membership/presentation/suspended_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

Future<void> _seedRequests(TestHarness h) async {
  final col = h.db.collection('premium_requests');
  Map<String, Object?> req(String uid, String type, int day, {String? ref}) => {
    'uid': uid,
    'email': '$uid@example.com',
    'displayName': 'User $uid',
    'type': type,
    'status': 'pending',
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, day)),
    'upiRef': ?ref,
    if (ref != null) 'amountPaise': 9900,
  };
  await col.doc('r1').set({...req('u1', 'trial', 1), 'status': 'rejected'});
  await col.doc('r2').set(req('u1', 'trial', 2));
  await col.doc('r3').set(req('u2', 'payment', 3, ref: '412345678901'));
}

/// Centres [finder] first so the navigation bar never covers it.
Future<void> _tapCentred(WidgetTester tester, Finder finder) async {
  await tester.runAsync(
    () => Scrollable.ensureVisible(tester.element(finder), alignment: 0.5),
  );
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  testWidgets('admins get the admin console instead of the app', (
    tester,
  ) async {
    final h = await createHarness(admin: true);
    await tester.runAsync(() => _seedRequests(h));
    await pumpApp(tester, h);

    expect(find.byType(AdminConsole), findsOneWidget);
    expect(find.text('Admin console'), findsOneWidget);
    expect(find.text('Pending (2)'), findsOneWidget);
    // u1's second request is flagged as a repeat.
    expect(find.text('Request #2 from this user'), findsOneWidget);
    expect(find.text('UPI ref: 412345678901'), findsOneWidget);
    expect(find.textContaining('Good evening'), findsNothing);
  });

  testWidgets('approving a trial grants premium for the trial length', (
    tester,
  ) async {
    final h = await createHarness(admin: true);
    await tester.runAsync(() => _seedRequests(h));
    await pumpApp(tester, h);

    final card = find.ancestor(
      of: find.text('Request #2 from this user'),
      matching: find.byType(RequestCard),
    );
    await tester.tap(find.descendant(of: card, matching: find.text('Approve')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await settle(tester);

    final request = await tester.runAsync(
      () => h.db.doc('premium_requests/r2').get(),
    );
    expect(request!.data()!['status'], 'approved');
    final ent = await tester.runAsync(
      () => h.db.doc('users/u1/entitlements/premium').get(),
    );
    expect(ent!.data()!['active'], isTrue);
    expect(ent.data()!['source'], 'trial');
    final until = (ent.data()!['expiresAt'] as Timestamp).toDate();
    final days = until.difference(DateTime.now()).inHours / 24;
    expect(days, closeTo(3, 0.1));
  });

  testWidgets('approving a payment grants a year', (tester) async {
    final h = await createHarness(admin: true);
    await tester.runAsync(() => _seedRequests(h));
    await pumpApp(tester, h);

    final card = find.ancestor(
      of: find.text('UPI ref: 412345678901'),
      matching: find.byType(RequestCard),
    );
    await tester.ensureVisible(card);
    await tester.tap(find.descendant(of: card, matching: find.text('Approve')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await settle(tester);

    final ent = await tester.runAsync(
      () => h.db.doc('users/u2/entitlements/premium').get(),
    );
    expect(ent!.data()!['source'], 'upi');
    expect(ent.data()!['pricePaise'], 9900);
    final until = (ent.data()!['expiresAt'] as Timestamp).toDate();
    expect(until.difference(DateTime.now()).inDays, inInclusiveRange(364, 365));
  });

  testWidgets('a banned user only sees the suspension notice', (tester) async {
    final h = await createHarness();
    await tester.runAsync(
      () => h.db.doc('bans/$testUid').set({'reason': 'Spam requests'}),
    );
    await pumpApp(tester, h);
    expect(find.byType(SuspendedPage), findsOneWidget);
    expect(find.text('Account suspended'), findsOneWidget);
    expect(find.text('Reason: Spam requests'), findsOneWidget);
    expect(find.textContaining('Good evening'), findsNothing);
  });

  testWidgets('users can request a free trial from the Premium page', (
    tester,
  ) async {
    final h = await createHarness();
    await pumpApp(tester, h);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/settings/premium');
    await settle(tester);

    expect(find.text('Try premium free for 3 days'), findsOneWidget);
    expect(find.text('Payments will open soon.'), findsOneWidget);
    await _tapCentred(tester, find.text('Request free trial'));
    await settle(tester);
    await tester.tap(find.text('Send request'));
    await settle(tester);

    final sent = await tester.runAsync(
      () => h.db.collection('premium_requests').get(),
    );
    final doc = sent!.docs.single.data();
    expect(doc['uid'], testUid);
    expect(doc['type'], 'trial');
    expect(doc['status'], 'pending');
    expect(find.text('Your request is waiting for approval.'), findsOneWidget);
  });

  testWidgets('a payment request needs the UPI reference', (tester) async {
    final h = await createHarness();
    await tester.runAsync(
      () => h.db.doc('app_config/premium').set({
        'pricePaise': 9900,
        'upiId': 'buddy@okaxis',
        'payeeName': 'Buddy',
        'trialDays': 3,
      }),
    );
    await pumpApp(tester, h);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/settings/premium');
    await settle(tester);

    expect(find.text('buddy@okaxis'), findsOneWidget);
    await _tapCentred(tester, find.text("I've paid – activate premium"));
    await settle(tester);
    expect(find.textContaining('Enter the UPI transaction ID'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'UPI transaction ID'),
      '412345678901',
    );
    await _tapCentred(tester, find.text("I've paid – activate premium"));
    await settle(tester);
    final sent = await tester.runAsync(
      () => h.db.collection('premium_requests').get(),
    );
    final doc = sent!.docs.single.data();
    expect(doc['type'], 'payment');
    expect(doc['upiRef'], '412345678901');
    expect(doc['amountPaise'], 9900);
  });
}
