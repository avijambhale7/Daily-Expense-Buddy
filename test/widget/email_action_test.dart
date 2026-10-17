import 'package:daily/app/routes.dart';
import 'package:daily/core/errors/app_failure.dart';
import 'package:daily/data/firebase/firebase_auth_repository.dart';
import 'package:daily/domain/models/user_profile.dart';
import 'package:daily/features/auth/cubit/auth_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Real repository over the auth mock, with scripted Firebase answers for
/// the action-code calls the mock does not implement.
class _ScriptedAuth extends FirebaseAuthRepository {
  _ScriptedAuth(super.auth, this.answers);

  /// Each call to [applyEmailActionCode] takes the next answer: null means
  /// success, an [AppFailure] is thrown.
  final List<AppFailure?> answers;
  final applied = <String>[];
  bool _verified = false;

  @override
  Future<void> applyEmailActionCode(String code) async {
    applied.add(code);
    final next = answers.isEmpty ? null : answers.removeAt(0);
    if (next != null) throw next;
    _verified = true;
  }

  /// Firebase reports the account as verified only after the code applied.
  @override
  Future<UserProfile?> reloadUser() async {
    final u = currentUser;
    if (u == null) return null;
    return UserProfile(
      uid: u.uid,
      email: u.email,
      emailVerified: _verified,
      displayName: u.displayName,
      createdAt: u.createdAt,
    );
  }
}

const _expired = AppFailure(FailureKind.expiredLink, 'expired');
const _invalid = AppFailure(FailureKind.invalidLink, 'invalid');

Future<_ScriptedAuth> _open(
  WidgetTester tester, {
  required List<AppFailure?> answers,
  bool signedIn = true,
  String link = '${Routes.emailAction}?mode=verifyEmail&oobCode=abc123',
}) async {
  late _ScriptedAuth repo;
  final h = await createHarness(
    signedIn: signedIn,
    verified: false,
    authFactory: (auth) => repo = _ScriptedAuth(auth, answers),
  );
  await pumpApp(tester, h);
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(link);
  await settle(tester);
  return repo;
}

String _location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path;

AuthState _auth(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first).read<AuthCubit>().state;

void main() {
  testWidgets('a valid link verifies through Firebase and continues', (
    tester,
  ) async {
    final repo = await _open(tester, answers: [null]);
    expect(repo.applied, ['abc123']);
    expect(find.text('Email verified'), findsOneWidget);
    expect(_auth(tester).status, AuthStatus.authenticated);

    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(_location(tester), Routes.dashboard);
    expect(_auth(tester).status, AuthStatus.authenticated);
  });

  testWidgets('an expired link says so and does not verify', (tester) async {
    await _open(tester, answers: [_expired]);
    expect(find.text('This link has expired'), findsOneWidget);
    expect(_auth(tester).status, AuthStatus.unverified);
  });

  testWidgets('an invalid or used link is explained', (tester) async {
    await _open(tester, answers: [_invalid]);
    expect(find.text("This link can't be used"), findsOneWidget);
    expect(_auth(tester).status, AuthStatus.unverified);
  });

  testWidgets('a link without a code is rejected without calling Firebase', (
    tester,
  ) async {
    final repo = await _open(
      tester,
      answers: [],
      link: '${Routes.emailAction}?mode=verifyEmail',
    );
    expect(repo.applied, isEmpty);
    expect(find.text("This link can't be used"), findsOneWidget);
  });

  testWidgets('a network failure offers a retry that works', (tester) async {
    final repo = await _open(tester, answers: [AppFailure.network, null]);
    expect(find.text("We couldn't finish that"), findsOneWidget);
    expect(_auth(tester).status, AuthStatus.unverified);

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(repo.applied, hasLength(2));
    expect(find.text('Email verified'), findsOneWidget);
    expect(_auth(tester).status, AuthStatus.authenticated);
  });

  testWidgets('opened while signed out (e.g. in a browser) it still verifies', (
    tester,
  ) async {
    final repo = await _open(tester, answers: [null], signedIn: false);
    expect(repo.applied, ['abc123']);
    expect(find.text('Email verified'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(_location(tester), Routes.login);
    expect(_auth(tester).status, AuthStatus.unauthenticated);
  });
}
