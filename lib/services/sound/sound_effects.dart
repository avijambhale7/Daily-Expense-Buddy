import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Sfx {
  /// Soft pop after an expense is saved.
  expenseSaved('sounds/expense_saved.wav'),

  /// Rising chime when a day is marked complete or a loan is settled.
  celebrate('sounds/day_complete.wav');

  const Sfx(this.asset);
  final String asset;
}

/// Short in-app sound effects, switchable in Settings.
abstract class SoundEffects {
  ValueListenable<bool> get enabled;
  Future<void> setEnabled(bool value);

  /// Plays [sfx] if enabled. Never throws: sounds are decoration only.
  Future<void> play(Sfx sfx);

  /// No sound at all (tests, unsupported platforms).
  static final SoundEffects silent = SilentSoundEffects();
}

class SilentSoundEffects implements SoundEffects {
  final _enabled = ValueNotifier(true);
  final played = <Sfx>[];

  @override
  ValueListenable<bool> get enabled => _enabled;

  @override
  Future<void> setEnabled(bool value) async => _enabled.value = value;

  @override
  Future<void> play(Sfx sfx) async {
    if (_enabled.value) played.add(sfx);
  }
}

class AudioSoundEffects implements SoundEffects {
  AudioSoundEffects(this._prefs)
    : _enabled = ValueNotifier(_prefs.getBool(key) ?? true);

  static const key = 'sound.effects';

  final SharedPreferences _prefs;
  final ValueNotifier<bool> _enabled;
  final _players = <Sfx, AudioPlayer>{};

  /// Plays as a UI sound: follows the system/notification volume and silent
  /// mode, and mixes with music instead of pausing it.
  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  @override
  ValueListenable<bool> get enabled => _enabled;

  @override
  Future<void> setEnabled(bool value) async {
    _enabled.value = value;
    await _prefs.setBool(key, value);
  }

  @override
  Future<void> play(Sfx sfx) async {
    if (!_enabled.value) return;
    try {
      final player = _players[sfx] ??= await _create();
      await player.stop();
      await player.play(AssetSource(sfx.asset));
    } catch (e) {
      debugPrint('Sound effect failed: $e');
    }
  }

  Future<AudioPlayer> _create() async {
    final p = AudioPlayer();
    await p.setAudioContext(_context);
    await p.setReleaseMode(ReleaseMode.stop);
    return p;
  }
}
