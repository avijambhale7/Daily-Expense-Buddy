import '../core/theme/theme_cubit.dart';
import '../domain/repositories/repositories.dart';
import '../services/app_lock/app_lock.dart';
import '../services/notifications/notification_service.dart';
import '../services/sound/sound_effects.dart';
import 'app_gate.dart';
import 'firebase_initializer.dart';
import 'session/user_session.dart';

/// Composition root: all external dependencies, injectable for tests.
class AppDependencies {
  const AppDependencies({
    required this.firebase,
    required this.themeStorage,
    required this.notifications,
    required this.locale,
    required this.appVersion,
    this.authRepository,
    this.sessionFactory,
    this.clearLocalData,
    this.hasPendingWrites,
    this.now = DateTime.now,
    this.onboarding,
    this.splashDuration = Duration.zero,
    this.sounds,
    this.appLock,
    this.biometrics,
  });

  final FirebaseSetupResult firebase;
  final ThemeStorage themeStorage;
  final NotificationService notifications;

  /// Device locale, e.g. `en_IN`.
  final String locale;
  final String appVersion;

  /// Null when Firebase is not configured.
  final AuthRepository? authRepository;
  final UserSessionFactory? sessionFactory;

  /// Clears cached user data from the device after sign-out.
  final Future<void> Function()? clearLocalData;

  /// Returns true when local changes have not reached the server yet.
  final Future<bool> Function()? hasPendingWrites;

  final DateTime Function() now;

  /// Remembers whether the intro slides were shown; null skips them.
  final OnboardingStore? onboarding;

  /// Minimum time the animated splash stays on screen at launch.
  final Duration splashDuration;

  /// In-app sound effects; null plays nothing.
  final SoundEffects? sounds;

  SoundEffects get soundEffects => sounds ?? SoundEffects.silent;

  /// Premium PIN lock; null disables the feature (tests, previews).
  final AppLockStore? appLock;

  /// Fingerprint / face unlock; null when unavailable.
  final BiometricAuth? biometrics;
}
