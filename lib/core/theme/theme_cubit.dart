import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import 'app_palette.dart';

class ThemeSettings extends Equatable {
  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.paletteId = 'standard',
    this.premiumUnlocked = false,
  });

  final ThemeMode mode;

  /// The palette the user chose (persisted even if premium lapses).
  final String paletteId;

  /// Whether premium palettes may be applied (from the server entitlement;
  /// not persisted).
  final bool premiumUnlocked;

  /// The palette actually rendered: premium palettes fall back to the
  /// standard palette when not unlocked.
  AppPalette get effectivePalette {
    final p = AppPalettes.byId(paletteId);
    return p.isPremium && !premiumUnlocked ? AppPalettes.standard : p;
  }

  ThemeSettings copyWith({
    ThemeMode? mode,
    String? paletteId,
    bool? premiumUnlocked,
  }) => ThemeSettings(
    mode: mode ?? this.mode,
    paletteId: paletteId ?? this.paletteId,
    premiumUnlocked: premiumUnlocked ?? this.premiumUnlocked,
  );

  @override
  List<Object?> get props => [mode, paletteId, premiumUnlocked];
}

/// Device-local persistence for the theme. Stored locally (not in Firestore)
/// so the correct theme is applied instantly at launch, before sign-in.
abstract interface class ThemeStorage {
  ThemeSettings load();
  Future<void> save(ThemeSettings settings);
}

class SharedPreferencesThemeStorage implements ThemeStorage {
  SharedPreferencesThemeStorage(this._prefs);

  final SharedPreferences _prefs;
  static const _modeKey = 'theme.mode';
  static const _paletteKey = 'theme.palette';

  @override
  ThemeSettings load() {
    final mode = switch (_prefs.getString(_modeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ThemeSettings(
      mode: mode,
      paletteId: AppPalettes.byId(_prefs.getString(_paletteKey)).id,
    );
  }

  @override
  Future<void> save(ThemeSettings settings) async {
    await _prefs.setString(_modeKey, settings.mode.name);
    await _prefs.setString(_paletteKey, settings.paletteId);
  }
}

class ThemeCubit extends Cubit<ThemeSettings> {
  ThemeCubit(this._storage) : super(_storage.load());

  final ThemeStorage _storage;

  Future<void> _persist() async {
    try {
      await _storage.save(state);
    } catch (e) {
      AppLogger.warn('Theme', 'Could not persist theme', e);
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    emit(state.copyWith(mode: mode));
    await _persist();
  }

  /// Selects [paletteId]. Premium palettes are only accepted when unlocked.
  Future<bool> setPalette(String paletteId) async {
    final palette = AppPalettes.byId(paletteId);
    if (palette.isPremium && !state.premiumUnlocked) return false;
    emit(state.copyWith(paletteId: palette.id));
    await _persist();
    return true;
  }

  void setPremiumUnlocked(bool unlocked) {
    if (unlocked != state.premiumUnlocked) {
      emit(state.copyWith(premiumUnlocked: unlocked));
    }
  }
}
