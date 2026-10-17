import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/formatting/app_format.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/theme_cubit.dart';
import '../data/firebase/firebase_auth_repository.dart';
import '../services/notifications/local_notification_service.dart';
import '../services/app_lock/app_lock.dart';
import '../services/sound/sound_effects.dart';
import 'app.dart';
import 'app_gate.dart';
import 'app_dependencies.dart';
import 'firebase_initializer.dart';
import 'session/user_session.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _lockPhonesToPortrait();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error(
      'Flutter',
      'Framework error',
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Platform', 'Uncaught error', error, stack);
    return true;
  };

  await initializeDateFormatting();
  final locale = AppFormat.verifyLocale(
    Intl.canonicalizedLocale(PlatformDispatcher.instance.locale.toString()),
  );
  Intl.defaultLocale = locale;

  final prefs = await SharedPreferences.getInstance();
  final firebase = await FirebaseInitializer.initialize();

  final notifications = LocalNotificationService();
  await notifications.initialize();

  var version = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version} (${info.buildNumber})';
  } catch (e) {
    AppLogger.warn('Bootstrap', 'Package info unavailable', e);
  }

  final dependencies = AppDependencies(
    firebase: firebase,
    themeStorage: SharedPreferencesThemeStorage(prefs),
    notifications: notifications,
    locale: locale,
    appVersion: version,
    onboarding: SharedPreferencesOnboardingStore(prefs),
    splashDuration: const Duration(milliseconds: 1900),
    sounds: AudioSoundEffects(prefs),
    appLock: SharedPreferencesAppLockStore(prefs),
    biometrics: LocalBiometricAuth(),
    authRepository: firebase.isReady
        ? FirebaseAuthRepository(FirebaseAuth.instance)
        : null,
    sessionFactory: firebase.isReady
        ? firestoreSessionFactory(
            db: FirebaseFirestore.instance,
            locale: locale,
          )
        : null,
    clearLocalData: firebase.isReady
        ? FirebaseInitializer.clearLocalCache
        : null,
    hasPendingWrites: firebase.isReady
        ? FirebaseInitializer.hasPendingWrites
        : null,
  );

  if (kDebugMode) {
    AppLogger.info(
      'Bootstrap',
      'Firebase: ${firebase.status.name}, emulators: ${firebase.usingEmulators}',
    );
  }

  runApp(DailyExpenseBuddyApp(dependencies: dependencies));
}

/// Phones use the portrait layout only. Tablets, desktops and the web keep
/// free rotation because their wider layouts are designed for landscape.
Future<void> _lockPhonesToPortrait() async {
  if (kIsWeb) return;
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return;
  final view = views.first;
  final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
  if (shortestSide < 600) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
}
