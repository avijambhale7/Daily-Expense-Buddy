// End-to-end test against the Firebase Emulator Suite (NOT production).
//
//   firebase emulators:start --only auth,firestore --project demo-daily-expense-buddy
//   flutter test integration_test -d <android-device> \
//     --dart-define=USE_FIREBASE_EMULATOR=true
//
// The test signs up a fresh user, verifies the email through the Auth
// emulator's REST API, and exercises the main workflows.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily/app/firebase_initializer.dart';
import 'package:daily/main.dart' as app;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

const _project = FirebaseInitializer.demoProjectId;

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<Map<String, dynamic>> _http(
  String method,
  String url, {
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    req.headers.set('Authorization', 'Bearer owner');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      throw HttpException('$method $url -> ${res.statusCode}: $text');
    }
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> _verifyEmailViaEmulator(String email) async {
  final host = FirebaseInitializer.emulatorHost;
  final codes = await _http(
    'GET',
    'http://$host:9099/emulator/v1/projects/$_project/oobCodes',
  );
  final list = (codes['oobCodes'] as List).cast<Map<String, dynamic>>();
  final code = list.lastWhere(
    (c) => c['email'] == email && c['requestType'] == 'VERIFY_EMAIL',
  );
  final link = (code['oobLink'] as String)
      .replaceFirst('127.0.0.1', host)
      .replaceFirst('localhost', host);
  await _http('GET', link);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'sign up, track expenses, reports, theme, logout and session restore',
    (tester) async {
      final email = 'e2e-${DateTime.now().millisecondsSinceEpoch}@example.com';
      const password = 'testpass123';

      await app.main();
      await _waitFor(tester, find.text('Create a free account'));

      // 1. Sign up.
      await tester.tap(find.text('Create a free account'));
      await _waitFor(tester, find.byKey(const Key('signup-name')));
      await tester.enterText(
        find.byKey(const Key('signup-name')),
        'E2E Tester',
      );
      await tester.enterText(find.byKey(const Key('signup-email')), email);
      await tester.enterText(
        find.byKey(const Key('signup-password')),
        password,
      );
      await tester.enterText(find.byKey(const Key('signup-confirm')), password);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await _waitFor(tester, find.text('Verify your email'));

      // 2. Verify email (emulator) and continue.
      await _verifyEmailViaEmulator(email);
      await tester.tap(find.text("I've verified my email"));
      await _waitFor(tester, find.textContaining('Good '));
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // 3. Add an expense.
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add Your First Expense').first,
      );
      await _waitFor(tester, find.text('Save expense'));
      await tester.enterText(find.byType(TextField).first, '250');
      await tester.ensureVisible(find.text('Groceries'));
      await tester.tap(find.text('Groceries'));
      await tester.tap(find.text('Save expense'));
      await _waitFor(tester, find.widgetWithText(FilledButton, 'Add expense'));
      final snap = await FirebaseFirestore.instance
          .collection('users/$uid/expenses')
          .get();
      expect(snap.docs.single.data()['amountMinor'], greaterThan(0));
      final currency = snap.docs.single.data()['currency'] as String;

      // 4. Edit it from the recent list.
      await tester.ensureVisible(find.text('Groceries').first);
      await tester.tap(find.text('Groceries').first);
      await _waitFor(tester, find.text('Save changes'));
      await tester.enterText(find.byType(TextField).first, '300');
      await tester.tap(find.text('Save changes'));
      await _pumpFor(tester, const Duration(seconds: 2));
      final edited = await FirebaseFirestore.instance
          .collection('users/$uid/expenses')
          .get();
      final editedData = edited.docs.single.data();
      expect(editedData['version'], 2);
      final digits = currency == 'JPY' ? 0 : 2;
      expect(editedData['amountMinor'], 300 * (digits == 0 ? 1 : 100));

      // 5. A change from "another device" (written directly to the server)
      //    appears through the live listener.
      final today = DateTime.now();
      final iso =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final host = FirebaseInitializer.emulatorHost;
      final nowTs = DateTime.now().toUtc().toIso8601String();
      await _http(
        'POST',
        'http://$host:8080/v1/projects/$_project/databases/(default)/documents/users/$uid/expenses?documentId=remote-device',
        body: {
          'fields': {
            'amountMinor': {'integerValue': '${100 * (digits == 0 ? 1 : 100)}'},
            'currency': {'stringValue': currency},
            'categoryId': {'stringValue': 'transport'},
            'date': {'stringValue': iso},
            'createdAt': {'timestampValue': nowTs},
            'updatedAt': {'timestampValue': nowTs},
            'version': {'integerValue': '1'},
          },
        },
      );
      // Today's total on the home screen now includes the synced expense.
      await _waitFor(tester, find.textContaining('400'));

      // 6. Reports reflect the data.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Reports'),
        ),
      );
      await _waitFor(tester, find.text('Total spent'));
      expect(find.text('2'), findsWidgets); // transactions tile

      // 7. Theme switching.
      await tester.tap(find.text('More'));
      await _waitFor(tester, find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(
        Theme.of(tester.element(find.text('Settings').first)).brightness,
        Brightness.dark,
      );

      // 8. Delete an expense.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('History'),
        ),
      );
      await _waitFor(tester, find.text('Transportation'));
      await tester.tap(find.text('Transportation').first);
      await _waitFor(tester, find.text('Save changes'));
      await tester.tap(find.byTooltip('Delete expense'));
      await _waitFor(tester, find.text('Delete this expense?'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(
        (await FirebaseFirestore.instance
                .collection('users/$uid/expenses')
                .get())
            .docs
            .length,
        1,
      );

      // 9. Log out.
      await tester.tap(find.text('More'));
      await _waitFor(tester, find.text('Log out'));
      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await _waitFor(tester, find.widgetWithText(FilledButton, 'Log out'));
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await _waitFor(tester, find.text('Create a free account'));
      expect(FirebaseAuth.instance.currentUser, isNull);

      // 10. Log back in: data is restored from the server.
      await tester.tap(find.text('Log in'));
      await _waitFor(tester, find.byKey(const Key('login-email')));
      await tester.enterText(find.byKey(const Key('login-email')), email);
      await tester.enterText(find.byKey(const Key('login-password')), password);
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await _waitFor(tester, find.widgetWithText(FilledButton, 'Add expense'));
    },
  );
}
