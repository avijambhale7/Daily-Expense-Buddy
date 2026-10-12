/// Spacing scale (logical pixels).
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

abstract final class IconSizes {
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 28;
}

/// Responsive breakpoints (width of the available area).
abstract final class Breakpoints {
  /// Below this: phone layout with bottom navigation.
  static const double medium = 600;

  /// At/above this: desktop layout with a permanent sidebar.
  static const double expanded = 1024;

  /// Max width for readable single-column content (forms, settings).
  static const double formMaxWidth = 560;

  /// Max width of dashboard content on very wide screens.
  static const double contentMaxWidth = 1280;
}

enum WindowSize { compact, medium, expanded }

WindowSize windowSizeFor(double width) {
  if (width >= Breakpoints.expanded) return WindowSize.expanded;
  if (width >= Breakpoints.medium) return WindowSize.medium;
  return WindowSize.compact;
}
