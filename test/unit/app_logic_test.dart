import 'package:daily/app/router.dart';
import 'package:daily/app/routes.dart';
import 'package:daily/core/theme/app_palette.dart';
import 'package:daily/core/theme/theme_cubit.dart';
import 'package:daily/core/validation/validators.dart';
import 'package:daily/domain/models/user_profile.dart';
import 'package:daily/features/auth/cubit/auth_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeCubit persistence', () {
    test('defaults to system mode and standard palette', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cubit = ThemeCubit(SharedPreferencesThemeStorage(prefs));
      expect(cubit.state.mode, ThemeMode.system);
      expect(cubit.state.paletteId, 'standard');
      await cubit.close();
    });

    test('persists mode and palette and restores them', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cubit = ThemeCubit(SharedPreferencesThemeStorage(prefs));
      await cubit.setMode(ThemeMode.dark);
      cubit.setPremiumUnlocked(true);
      expect(await cubit.setPalette('ocean'), isTrue);
      await cubit.close();

      final restored = ThemeCubit(SharedPreferencesThemeStorage(prefs));
      expect(restored.state.mode, ThemeMode.dark);
      expect(restored.state.paletteId, 'ocean');
      // Premium is not persisted locally; until the entitlement is confirmed
      // the standard palette is rendered.
      expect(restored.state.effectivePalette.id, AppPalettes.standard.id);
      restored.setPremiumUnlocked(true);
      expect(restored.state.effectivePalette.id, 'ocean');
      await restored.close();
    });

    test('premium palettes are refused without entitlement', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cubit = ThemeCubit(SharedPreferencesThemeStorage(prefs));
      expect(await cubit.setPalette('midnight'), isFalse);
      expect(cubit.state.paletteId, 'standard');
      await cubit.close();
    });

    test('unknown stored values fall back safely', () async {
      SharedPreferences.setMockInitialValues({
        'theme.mode': 'weird',
        'theme.palette': 'nope',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = SharedPreferencesThemeStorage(prefs).load();
      expect(s.mode, ThemeMode.system);
      expect(s.paletteId, 'standard');
    });
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('person@example.com'), isNull);
    });

    test('new password policy', () {
      expect(Validators.newPassword('short1'), isNotNull);
      expect(Validators.newPassword('lettersonly'), isNotNull);
      expect(Validators.newPassword('12345678'), isNotNull);
      expect(Validators.newPassword('goodpass1'), isNull);
      expect(Validators.confirmPassword('a', 'b'), isNotNull);
    });
  });

  group('Route guard', () {
    const verified = UserProfile(
      uid: 'u',
      email: 'u@x.com',
      emailVerified: true,
    );
    const unverified = UserProfile(
      uid: 'u',
      email: 'u@x.com',
      emailVerified: false,
    );

    String? go(AuthState auth, String location, {bool ready = true}) {
      final uri = Uri.parse(location);
      return resolveRedirect(
        auth: auth,
        firebaseReady: ready,
        uri: uri,
        matchedLocation: uri.path,
      );
    }

    test('unconfigured Firebase always shows setup', () {
      expect(
        go(const AuthState.unauthenticated(), '/dashboard', ready: false),
        Routes.setup,
      );
      expect(
        go(const AuthState.unauthenticated(), '/setup', ready: false),
        isNull,
      );
    });

    test('protected routes require authentication (including typed URLs)', () {
      expect(
        go(const AuthState.unauthenticated(), '/history'),
        '/welcome?from=${Uri.encodeComponent('/history')}',
      );
      expect(go(const AuthState.unauthenticated(), '/login'), isNull);
      expect(
        go(const AuthState.unknown(), '/reports'),
        '/splash?from=${Uri.encodeComponent('/reports')}',
      );
    });

    test('unverified users go to email verification', () {
      expect(
        go(AuthState.fromUser(unverified), '/dashboard'),
        Routes.verifyEmail,
      );
      expect(go(AuthState.fromUser(unverified), '/verify-email'), isNull);
    });

    test(
      'authenticated users leave auth screens, honouring safe return paths',
      () {
        final auth = AuthState.fromUser(verified);
        expect(go(auth, '/login'), Routes.dashboard);
        expect(go(auth, '/login?from=%2Freports'), '/reports');
        expect(go(auth, '/dashboard'), isNull);
      },
    );

    test('open redirects are rejected', () {
      expect(Routes.safeReturnPath('https://evil.example'), isNull);
      expect(Routes.safeReturnPath('//evil.example'), isNull);
      expect(Routes.safeReturnPath('/login'), isNull);
      expect(
        Routes.safeReturnPath('/calendar/day/2025-10-01'),
        '/calendar/day/2025-10-01',
      );
      final auth = AuthState.fromUser(verified);
      expect(
        go(auth, '/login?from=https%3A%2F%2Fevil.example'),
        Routes.dashboard,
      );
    });
  });
}
