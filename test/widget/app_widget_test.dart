import 'package:daily/app/session/user_session.dart';
import 'package:daily/core/theme/theme_cubit.dart';
import 'package:daily/core/widgets/common.dart';
import 'package:daily/features/dashboard/presentation/dashboard_page.dart';
import 'package:daily/services/sound/sound_effects.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  group('Without Firebase configuration', () {
    testWidgets('shows the setup screen instead of faking sign-in', (
      tester,
    ) async {
      final h = await createHarness(firebaseReady: false);
      await pumpApp(tester, h);
      expect(find.text('Firebase setup required'), findsOneWidget);
    });
  });

  group('Authentication screens', () {
    testWidgets('signed-out users land on the welcome screen', (tester) async {
      final h = await createHarness(signedIn: false);
      await pumpApp(tester, h);
      expect(find.text('Create a free account'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
    });

    testWidgets('login form validates input', (tester) async {
      final h = await createHarness(signedIn: false);
      await pumpApp(tester, h);
      await tester.tap(find.text('Log in'));
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pump();
      expect(find.text('Enter your email address'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('login-email')),
        'not-an-email',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('sign-up form validates password rules and confirmation', (
      tester,
    ) async {
      final h = await createHarness(signedIn: false);
      await pumpApp(tester, h);
      await tester.tap(find.text('Create a free account'));
      await settle(tester);

      await tester.enterText(find.byKey(const Key('signup-name')), 'Avery');
      await tester.enterText(
        find.byKey(const Key('signup-email')),
        'avery@example.com',
      );
      await tester.enterText(find.byKey(const Key('signup-password')), 'short');
      await tester.enterText(
        find.byKey(const Key('signup-confirm')),
        'different',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('unverified users are sent to email verification', (
      tester,
    ) async {
      final h = await createHarness(verified: false);
      await pumpApp(tester, h);
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text("I've verified my email"), findsOneWidget);
    });
  });

  group('Signed in', () {
    testWidgets('dashboard shows a helpful empty state', (tester) async {
      final h = await createHarness();
      await pumpApp(tester, h);
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.textContaining('Good evening, Avery'), findsOneWidget);
      expect(find.text('Today not completed yet'), findsOneWidget);
      expect(find.text('Add Your First Expense'), findsWidgets);
      expect(find.text(r'$0.00'), findsWidgets);
    });

    testWidgets('quick amounts add up and the description is saved', (
      tester,
    ) async {
      final h = await createHarness();
      await pumpApp(tester, h);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add Your First Expense').first,
      );
      await settle(tester);

      await tester.tap(find.text(r'+$100'));
      await tester.pump();
      await tester.tap(find.text(r'+$50'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '150.00',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Lunch, Uber, Flipkart (optional)'),
        'Lunch',
      );
      await tester.tap(find.text('Save expense'));
      await settle(tester);
      final docs = await h.db.collection('users/$testUid/expenses').get();
      expect(docs.docs.single.data()['amountMinor'], 15000);
      expect(docs.docs.single.data()['merchant'], 'Lunch');
    });

    testWidgets('the home header shows today without the budget ring', (
      tester,
    ) async {
      final h = await createHarness();
      await pumpApp(tester, h);
      expect(find.text('Spent today'), findsOneWidget);
      expect(find.text('No expenses recorded yet'), findsOneWidget);
      expect(find.textContaining('over budget'), findsNothing);
      expect(find.textContaining('left today'), findsNothing);
    });

    testWidgets('adding an expense validates input and updates the dashboard', (
      tester,
    ) async {
      final h = await createHarness();
      await pumpApp(tester, h);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Add Your First Expense').first,
      );
      await settle(tester);
      expect(find.text('Save expense'), findsOneWidget);

      // Empty submit shows a validation error and does not save.
      await tester.tap(find.text('Save expense'));
      await tester.pump();
      expect(find.text('Enter an amount'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '12.345');
      await tester.tap(find.text('Save expense'));
      await tester.pump();
      expect(
        find.textContaining('allows up to 2 decimal places'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, '120.50');
      await tester.ensureVisible(find.text('Groceries'));
      await tester.tap(find.text('Groceries'));
      await tester.pump();
      await tester.tap(find.text('Save expense'));
      await settle(tester);

      // Let the page transition finish.
      await tester.pump(const Duration(seconds: 1));
      // Back on the dashboard with recalculated totals.
      expect(find.text('Save expense'), findsNothing);
      expect(find.text(r'$120.50'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Add expense'), findsOneWidget);
      final docs = await h.db.collection('users/$testUid/expenses').get();
      expect(docs.docs.single.data()['amountMinor'], 12050);
      expect(docs.docs.single.data()['categoryId'], 'groceries');
      expect(docs.docs.single.data()['date'], '2025-10-14');
      expect(h.sounds.played, [Sfx.expenseSaved]);

      // Completing the day plays the celebration chime.
      await tester.tap(find.text('Done').first);
      await settle(tester);
      expect(find.text('Day marked as complete'), findsOneWidget);
      expect(h.sounds.played.last, Sfx.celebrate);
    });

    testWidgets('bottom navigation switches screens on phones', (tester) async {
      final h = await createHarness();
      await pumpApp(tester, h);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('History'),
        ),
      );
      await settle(tester);
      expect(find.text('No expenses yet'), findsOneWidget);

      await tester.tap(find.text('Reports'));
      await settle(tester);
      expect(find.text('Total spent'), findsOneWidget);

      await tester.tap(find.text('More'));
      await settle(tester);
      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets(
      'desktop width uses a sidebar instead of a stretched phone layout',
      (tester) async {
        final h = await createHarness();
        await pumpApp(tester, h, size: const Size(1400, 900));
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Add expense'), findsWidgets);
        expect(find.text('Budgets'), findsOneWidget);
        expect(find.text('Categories'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tablet width uses a navigation rail', (tester) async {
      final h = await createHarness();
      await pumpApp(tester, h, size: const Size(800, 1000));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching to dark mode updates the theme and persists it', (
      tester,
    ) async {
      final h = await createHarness();
      await pumpApp(tester, h);
      await tester.tap(find.text('More'));
      await settle(tester);

      await tester.tap(find.text('Dark'));
      await settle(tester);

      final context = tester.element(find.text('Settings').first);
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(h.prefs.getString('theme.mode'), 'dark');
      expect(context.read<ThemeCubit>().state.mode, ThemeMode.dark);
    });

    testWidgets(
      'dashboard shows an error state with retry when loading fails',
      (tester) async {
        final h = await createHarness(
          overrideSession: (base) => UserSession(
            user: base.user,
            expenses: FailingExpenseRepository(base.expenses),
            categories: base.categories,
            budgets: base.budgets,
            dailyStatus: base.dailyStatus,
            loans: base.loans,
            preferences: base.preferences,
            entitlements: base.entitlements,
            userData: base.userData,
            syncIssues: base.syncIssues,
            membership: base.membership,
            admin: base.admin,
            recurring: base.recurring,
            goals: base.goals,
          ),
        );
        await pumpApp(tester, h);
        expect(find.byType(ErrorView), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      },
    );

    testWidgets('signing out returns to the welcome screen', (tester) async {
      final h = await createHarness();
      await pumpApp(tester, h);
      await tester.tap(find.text('More'));
      await settle(tester);
      await tester.ensureVisible(find.text('Log out'));
      await tester.pump();
      await tester.tap(find.text('Log out'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await settle(tester);
      expect(find.text('Create a free account'), findsOneWidget);
    });
  });

  testWidgets('loading view exposes an accessible label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoadingView(label: 'Loading data')),
    );
    expect(find.bySemanticsLabel('Loading data'), findsOneWidget);
  });
}
