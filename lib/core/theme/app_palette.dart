import 'package:material_ui/material_ui.dart';

/// A named colour palette. Every palette is rendered through the same
/// [AppTheme.build] pipeline, so all components, charts and states adapt.
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.seed,
    required this.secondary,
    required this.tertiary,
    required this.preview,
    this.isPremium = false,
    this.forcedBrightness,
    this.darkSurface,
  });

  final String id;
  final String name;
  final Color seed;
  final Color secondary;
  final Color tertiary;

  /// Swatch shown in the theme picker.
  final List<Color> preview;
  final bool isPremium;

  /// Palettes such as Midnight are always dark.
  final Brightness? forcedBrightness;

  /// Optional base surface for dark mode.
  final Color? darkSurface;
}

abstract final class AppPalettes {
  /// Brand palette: wallet blue, coin gold, growth green.
  static const standard = AppPalette(
    id: 'standard',
    name: 'Buddy Blue',
    seed: Color(0xFF1E63E9),
    secondary: Color(0xFF1FA463),
    tertiary: Color(0xFFF4B400),
    preview: [Color(0xFF1E63E9), Color(0xFF1FA463), Color(0xFFF4B400)],
  );

  static const ocean = AppPalette(
    id: 'ocean',
    name: 'Ocean Blue',
    seed: Color(0xFF0077B6),
    secondary: Color(0xFF00A6C8),
    tertiary: Color(0xFF48CAE4),
    preview: [Color(0xFF0077B6), Color(0xFF00A6C8), Color(0xFF90E0EF)],
    isPremium: true,
  );

  static const forest = AppPalette(
    id: 'forest',
    name: 'Forest Green',
    seed: Color(0xFF2E7D32),
    secondary: Color(0xFF6D8B3A),
    tertiary: Color(0xFF8D6E63),
    preview: [Color(0xFF2E7D32), Color(0xFF6D8B3A), Color(0xFF8D6E63)],
    isPremium: true,
  );

  static const sunset = AppPalette(
    id: 'sunset',
    name: 'Sunset',
    seed: Color(0xFFE8590C),
    secondary: Color(0xFFD6336C),
    tertiary: Color(0xFFF59F00),
    preview: [Color(0xFFE8590C), Color(0xFFD6336C), Color(0xFFF59F00)],
    isPremium: true,
  );

  static const lavender = AppPalette(
    id: 'lavender',
    name: 'Lavender',
    seed: Color(0xFF7C4DFF),
    secondary: Color(0xFF9775FA),
    tertiary: Color(0xFFE599F7),
    preview: [Color(0xFF7C4DFF), Color(0xFF9775FA), Color(0xFFE599F7)],
    isPremium: true,
  );

  static const midnight = AppPalette(
    id: 'midnight',
    name: 'Midnight',
    seed: Color(0xFF3D5AFE),
    secondary: Color(0xFF4DD0E1),
    tertiary: Color(0xFFFFD54F),
    preview: [Color(0xFF0B1020), Color(0xFF3D5AFE), Color(0xFF4DD0E1)],
    isPremium: true,
    forcedBrightness: Brightness.dark,
    darkSurface: Color(0xFF0B1020),
  );

  static const all = [standard, ocean, forest, sunset, lavender, midnight];

  static AppPalette byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => standard);
}
