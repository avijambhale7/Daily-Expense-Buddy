import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers on this device whether the intro slides were shown.
abstract interface class OnboardingStore {
  bool get seen;
  Future<void> markSeen();
}

class SharedPreferencesOnboardingStore implements OnboardingStore {
  SharedPreferencesOnboardingStore(this._prefs);

  static const key = 'onboarding.seen';
  final SharedPreferences _prefs;

  @override
  bool get seen => _prefs.getBool(key) ?? false;

  @override
  Future<void> markSeen() => _prefs.setBool(key, true);
}

/// Lets screens finish the intro without listening to the gate (providers
/// may not expose a [ChangeNotifier] directly).
class OnboardingActions {
  const OnboardingActions(this._gate);
  final AppGate _gate;

  Future<void> complete() => _gate.completeOnboarding();
}

/// Pre-login flow state the router needs besides authentication: whether
/// the animated splash has finished and whether the intro was seen.
class AppGate extends ChangeNotifier {
  AppGate({required Duration splash, this.onboardingStore})
    : _splashDone = splash <= Duration.zero {
    if (!_splashDone) {
      _timer = Timer(splash, () {
        _splashDone = true;
        notifyListeners();
      });
    }
  }

  final OnboardingStore? onboardingStore;
  Timer? _timer;
  bool _splashDone;

  bool get splashDone => _splashDone;

  /// Without a store (tests, web previews) the intro counts as seen.
  bool get onboardingSeen => onboardingStore?.seen ?? true;

  Future<void> completeOnboarding() async {
    await onboardingStore?.markSeen();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
