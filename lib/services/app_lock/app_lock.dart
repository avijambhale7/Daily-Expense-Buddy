import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-only PIN (and optional fingerprint) lock for the app.
///
/// Only a salted SHA-256 hash of the PIN is stored, never the PIN itself.
/// The lock is per device and is cleared on sign-out, so the next person to
/// sign in on this device is never locked out by someone else's PIN.
abstract interface class AppLockStore {
  bool get enabled;
  bool get biometric;
  bool verify(String pin);
  Future<void> setPin(String pin);
  Future<void> setBiometric(bool on);
  Future<void> clear();
}

class SharedPreferencesAppLockStore implements AppLockStore {
  SharedPreferencesAppLockStore(this._prefs);

  static const _hashKey = 'appLock.hash';
  static const _saltKey = 'appLock.salt';
  static const _bioKey = 'appLock.biometric';

  final SharedPreferences _prefs;

  static String hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  @override
  bool get enabled => _prefs.getString(_hashKey) != null;

  @override
  bool get biometric => enabled && (_prefs.getBool(_bioKey) ?? false);

  @override
  bool verify(String pin) {
    final h = _prefs.getString(_hashKey);
    final salt = _prefs.getString(_saltKey);
    return h != null && salt != null && hash(pin, salt) == h;
  }

  @override
  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => rnd.nextInt(256)));
    await _prefs.setString(_saltKey, salt);
    await _prefs.setString(_hashKey, hash(pin, salt));
  }

  @override
  Future<void> setBiometric(bool on) => _prefs.setBool(_bioKey, on);

  @override
  Future<void> clear() async {
    await _prefs.remove(_hashKey);
    await _prefs.remove(_saltKey);
    await _prefs.remove(_bioKey);
  }
}

/// Fingerprint / face unlock. Unavailable on the web.
abstract interface class BiometricAuth {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuth implements BiometricAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Exposes the session's [AppLockController] (or null) to the widget tree.
/// A plain holder, because providers must not hand out listenables.
class AppLockHandle {
  const AppLockHandle(this.controller);
  final AppLockController? controller;
}

/// Whether the app is currently locked.
class AppLockController extends ChangeNotifier {
  AppLockController(
    this.store, {
    this.biometrics,
    DateTime Function()? now,
    this.relockAfter = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now,
       _locked = store.enabled;

  final AppLockStore store;
  final BiometricAuth? biometrics;
  final Duration relockAfter;
  final DateTime Function() _now;

  bool _locked;
  DateTime? _backgroundedAt;

  bool get locked => _locked && store.enabled;

  /// Tries [pin]; unlocks and returns true when it matches.
  bool unlockWithPin(String pin) {
    if (!store.verify(pin)) return false;
    _set(false);
    return true;
  }

  Future<bool> unlockWithBiometrics() async {
    final b = biometrics;
    if (b == null || !store.biometric) return false;
    final ok = await b.authenticate('Unlock Daily Expense Buddy');
    if (ok) _set(false);
    return ok;
  }

  /// Call when the app goes to the background.
  void paused() => _backgroundedAt = _now();

  /// Call when the app returns; locks again after [relockAfter] away.
  void resumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (store.enabled &&
        since != null &&
        _now().difference(since) >= relockAfter) {
      _set(true);
    }
  }

  /// After the PIN was set or removed in settings.
  void settingsChanged() => notifyListeners();

  void _set(bool v) {
    if (_locked == v) return;
    _locked = v;
    notifyListeners();
  }
}
