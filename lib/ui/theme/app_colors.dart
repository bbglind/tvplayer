import 'package:flutter/painting.dart';

/// The colour tokens from docs/design.md. Use these (or the theme built from
/// them) instead of hard-coded colours.
abstract final class AppColors {
  /// App background.
  static const background = Color(0xFF262423);

  /// Sidebar, panels, search field, inactive chips.
  static const surface = Color(0xFF393533);

  /// Cards, list rows, poster placeholders.
  static const card = Color(0xFF44403D);

  /// Hover, selected row, active nav item, secondary buttons, progress
  /// track, dividers.
  static const hover = Color(0xFF524C48);

  /// Video area / player background, overlays (with opacity for fades).
  static const scrim = Color(0xFF1A1918);

  /// Main text and icons.
  static const textPrimary = Color(0xFFEEE9E1);

  /// Secondary text, inactive nav items, descriptions.
  static const textSecondary = Color(0xFFC3BCB3);

  /// Labels and meta lines (year, genre, "until 21:00").
  static const textMuted = Color(0xFFADA69D);

  /// Placeholders, disabled, inactive pager dots.
  static const textDisabled = Color(0xFF85807A);

  /// Focus ring, active marker, primary button, progress fill, selected chip.
  static const accent = Color(0xFFD4AE6A);

  /// Hover / pressed state of accent elements and links.
  static const accentHover = Color(0xFFDEBE84);

  /// Text and icons on accent (and on live/success badges).
  static const onAccent = Color(0xFF262423);

  /// LIVE badge, recording indicator; also used for errors.
  static const live = Color(0xFFD8735F);

  /// Downloaded, recorded, watched, OK.
  static const success = Color(0xFF9DB48A);
}
