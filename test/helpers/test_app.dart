import 'package:daily/app/app.dart';
import 'package:daily/app/app_dependencies.dart';
import 'package:daily/app/firebase_initializer.dart';
import 'package:daily/app/session/user_session.dart';
import 'package:daily/core/dates/local_date.dart';
import 'package:daily/core/errors/app_failure.dart';
import 'package:daily/core/theme/theme_cubit.dart';
import 'package:daily/data/firebase/firebase_auth_repository.dart';
import 'package:daily/domain/models/expense.dart';
import 'package:daily/domain/repositories/repositories.dart';
import 'package:daily/services/notifications/notification_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show UserMetadata;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fixed "now" for deterministic tests: Tuesday 14 Oct 2025, 18:30.
DateTime testNow() => DateTime(2025, 10, 14, 18, 30);

const testUid = 'user-a';

MockUser testUser({bool verified = true, String uid = testUid}) => MockUser(
  uid: uid,
  email: '$uid@example.com',
  displayName: 'Avery Tester',
  isEmailVerified: verified,
  metadata: UserMetadata(
    DateTime(2025, 1, 1).millisecondsSinceEpoch,
    DateTime(2025, 10, 1).millisecondsSinceEpoch,
  ),
);

class TestHarness {
  TestHarness({
    required this.auth,
    required this.db,
    required this.dependencies,
    required this.prefs,
  });

  final MockFirebaseAuth auth;
  final FakeFirebaseFirestore db;
  final AppDependencies dependencies;
  final SharedPreferences prefs;
}

/// Builds app dependencies using the real Firebase repositories over
/// in-memory fakes (no network, no real credentials).
Future<TestHarness> createHarness({
  bool signedIn = true,
  bool verified = true,
  bool firebaseReady = true,
  Map<String, Object> initialPrefs = const {},
  UserSession Function(UserSession base)? overrideSession,
}) async {
  await initializeDateFormatting('en_US');
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final auth = MockFirebaseAuth(
    signedIn: signedIn,
    mockUser: testUser(verified: verified),
  );
  final db = FakeFirebaseFirestore();
  final baseFactory = firestoreSessionFactory(db: db, locale: 'en_US');
  final deps = AppDependencies(
    firebase: FirebaseSetupResult(
      firebaseReady
          ? FirebaseSetupStatus.ready
          : FirebaseSetupStatus.notConfigured,
    ),
    themeStorage: SharedPreferencesThemeStorage(prefs),
    notifications: NoopNotificationService(),
    locale: 'en_US',
    appVersion: '1.0.0 (test)',
    authRepository: firebaseReady ? FirebaseAuthRepository(auth) : null,
    sessionFactory: firebaseReady
        ? (user) {
            final base = baseFactory(user);
            return overrideSession == null ? base : overrideSession(base);
          }
        : null,
    clearLocalData: () async {},
    hasPendingWrites: () async => false,
    now: testNow,
  );
  return TestHarness(auth: auth, db: db, dependencies: deps, prefs: prefs);
}

Future<void> pumpApp(
  WidgetTester tester,
  TestHarness harness, {
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    DailyExpenseBuddyApp(dependencies: harness.dependencies),
  );
  await settle(tester);
}

/// Pumps frames until async Firestore fakes and navigation have settled.
Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Repository whose streams always fail, for error-state tests.
class FailingExpenseRepository implements ExpenseRepository {
  FailingExpenseRepository(this.inner);
  final ExpenseRepository inner;

  @override
  Stream<List<Expense>> watchRange(DateRange range) =>
      Stream.error(AppFailure.network);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
