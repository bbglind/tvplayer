import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'widgets.dart';

/// Corner radii from docs/design.md.
abstract final class AppRadius {
  /// Buttons, nav items, small tiles.
  static const small = 10.0;

  /// Cards, rows, posters.
  static const card = 12.0;

  /// Large panels.
  static const panel = 14.0;

  /// Dialogs and hero areas.
  static const large = 16.0;

  /// Chips and search fields.
  static const pill = 999.0;
}

/// Spacing from docs/design.md.
abstract final class AppSpacing {
  /// Page padding: 28 top, 40 sides.
  static const page = EdgeInsets.fromLTRB(40, 28, 40, 28);

  /// Between sections.
  static const section = 36.0;

  /// From a section title to its content.
  static const inSection = 16.0;
}

/// The app's dark Material 3 theme, built from [AppColors].
abstract final class AppTheme {
  static const fontFamily = 'Figtree';

  /// Width of the keyboard focus ring.
  static const focusWidth = 2.5;

  static const colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    primaryContainer: AppColors.hover,
    onPrimaryContainer: AppColors.textPrimary,
    secondary: AppColors.accentHover,
    onSecondary: AppColors.onAccent,
    secondaryContainer: AppColors.hover,
    onSecondaryContainer: AppColors.textPrimary,
    tertiary: AppColors.success,
    onTertiary: AppColors.onAccent,
    tertiaryContainer: AppColors.hover,
    onTertiaryContainer: AppColors.textPrimary,
    error: AppColors.live,
    onError: AppColors.onAccent,
    errorContainer: AppColors.live,
    onErrorContainer: AppColors.onAccent,
    surface: AppColors.background,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceDim: AppColors.scrim,
    surfaceBright: AppColors.hover,
    surfaceContainerLowest: AppColors.scrim,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.card,
    surfaceContainerHighest: AppColors.hover,
    outline: AppColors.textDisabled,
    outlineVariant: AppColors.hover,
    shadow: Colors.transparent,
    scrim: AppColors.scrim,
    inverseSurface: AppColors.textPrimary,
    onInverseSurface: AppColors.background,
    inversePrimary: AppColors.accent,
    surfaceTint: Colors.transparent,
  );

  static TextStyle _style(
    double size,
    FontWeight weight, {
    Color color = AppColors.textPrimary,
    double? letterSpacing,
    double height = 1.3,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );

  /// Roles from the typography table in docs/design.md:
  /// displayMedium = hero, headlineMedium = page title, headlineSmall =
  /// panel title, titleLarge = section title, titleMedium/titleSmall = card
  /// titles, body* = body/meta, labelMedium = overline, labelSmall = badge.
  static final textTheme = TextTheme(
    displayLarge: _style(48, FontWeight.w700, height: 1.15),
    displayMedium: _style(40, FontWeight.w700, height: 1.15),
    displaySmall: _style(34, FontWeight.w700, height: 1.15),
    headlineLarge: _style(32, FontWeight.w700, height: 1.2),
    headlineMedium: _style(30, FontWeight.w700, height: 1.2),
    headlineSmall: _style(22, FontWeight.w700, height: 1.25),
    titleLarge: _style(20, FontWeight.w600),
    titleMedium: _style(15, FontWeight.w600),
    titleSmall: _style(14, FontWeight.w600),
    bodyLarge: _style(15, FontWeight.w400, height: 1.45),
    bodyMedium: _style(15, FontWeight.w400, height: 1.4),
    bodySmall: _style(13, FontWeight.w400, color: AppColors.textMuted),
    labelLarge: _style(15, FontWeight.w600),
    labelMedium: _style(
      13,
      FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 1.3,
    ),
    labelSmall: _style(11, FontWeight.w700, letterSpacing: 0.9),
  );

  /// Overlay for hover/press on neutral surfaces. Focus shows as a ring
  /// instead, so it gets no overlay.
  static final _neutralOverlay = WidgetStateProperty.resolveWith<Color?>((s) {
    if (s.contains(WidgetState.pressed)) {
      return AppColors.textPrimary.withValues(alpha: 0.12);
    }
    if (s.contains(WidgetState.hovered)) {
      return AppColors.textPrimary.withValues(alpha: 0.07);
    }
    return null;
  });

  static const _buttonShape = WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
    ),
  );

  static const _buttonPadding = WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  );

  static const _buttonMinSize = WidgetStatePropertyAll(Size(64, 44));

  /// Primary button: accent background, onAccent text, 600.
  static final _primaryButton = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return AppColors.hover;
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) {
        return AppColors.accentHover;
      }
      return AppColors.accent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? AppColors.textDisabled
          : AppColors.onAccent,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? AppColors.textDisabled
          : AppColors.onAccent,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    // The ring sits on the accent fill, so it is drawn in textPrimary to
    // stay visible.
    backgroundBuilder: focusRingLayer(AppColors.textPrimary),
    textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
    shape: _buttonShape,
    padding: _buttonPadding,
    minimumSize: _buttonMinSize,
    elevation: const WidgetStatePropertyAll(0),
  );

  /// Secondary button: hover background, textPrimary text, 500.
  static final _secondaryButton = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? AppColors.surface
          : AppColors.hover,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? AppColors.textDisabled
          : AppColors.textPrimary,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? AppColors.textDisabled
          : AppColors.textPrimary,
    ),
    overlayColor: _neutralOverlay,
    backgroundBuilder: focusRingLayer(AppColors.accent),
    textStyle: WidgetStatePropertyAll(
      textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    shape: _buttonShape,
    padding: _buttonPadding,
    minimumSize: _buttonMinSize,
    elevation: const WidgetStatePropertyAll(0),
  );

  static final _textButton = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return AppColors.textDisabled;
      if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) {
        return AppColors.accentHover;
      }
      return AppColors.accent;
    }),
    overlayColor: _neutralOverlay,
    backgroundBuilder: focusRingLayer(AppColors.accent),
    textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
    shape: _buttonShape,
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    minimumSize: _buttonMinSize,
  );

  static final _iconButton = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return AppColors.textDisabled;
      if (s.contains(WidgetState.selected)) return AppColors.accent;
      return AppColors.textPrimary;
    }),
    overlayColor: _neutralOverlay,
    backgroundBuilder: focusRingLayer(AppColors.accent),
    shape: _buttonShape,
  );

  static final _chipLabel = WidgetStateColor.resolveWith((s) {
    if (s.contains(WidgetState.disabled)) return AppColors.textDisabled;
    if (s.contains(WidgetState.selected)) return AppColors.onAccent;
    return AppColors.textSecondary;
  });

  static const _inputRadius = BorderRadius.all(
    Radius.circular(AppRadius.small),
  );

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      cardColor: AppColors.card,
      dividerColor: AppColors.hover,
      disabledColor: AppColors.textDisabled,
      hoverColor: AppColors.textPrimary.withValues(alpha: 0.07),
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: AppColors.textPrimary.withValues(alpha: 0.08),
      splashFactory: InkRipple.splashFactory,
      shadowColor: Colors.transparent,
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
        actionsIconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _primaryButton),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _secondaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _secondaryButton),
      textButtonTheme: TextButtonThemeData(style: _textButton),
      iconButtonTheme: IconButtonThemeData(style: _iconButton),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppColors.textDisabled;
            if (s.contains(WidgetState.selected)) return AppColors.onAccent;
            return AppColors.textSecondary;
          }),
          iconColor: const WidgetStatePropertyAll(AppColors.onAccent),
          overlayColor: _neutralOverlay,
          side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused)
                ? const BorderSide(color: AppColors.textPrimary, width: 2)
                : const BorderSide(color: AppColors.hover),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          minimumSize: _buttonMinSize,
          shape: const WidgetStatePropertyAll(StadiumBorder()),
        ),
      ),
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return s.contains(WidgetState.hovered)
                ? AppColors.accentHover
                : AppColors.accent;
          }
          return s.contains(WidgetState.hovered)
              ? AppColors.card
              : AppColors.surface;
        }),
        labelStyle: textTheme.labelLarge?.copyWith(color: _chipLabel),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.onAccent,
        ),
        iconTheme: const IconThemeData(
          size: 18,
          color: AppColors.textSecondary,
        ),
        checkmarkColor: AppColors.onAccent,
        showCheckmark: false,
        // The focus ring comes from a FocusRing around the chip, which
        // shows only in keyboard mode.
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        elevation: 0,
        pressElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hoverColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.accent,
        ),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: const OutlineInputBorder(
          borderRadius: _inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: _inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: _inputRadius,
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: _inputRadius,
          borderSide: BorderSide(color: AppColors.live),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: _inputRadius,
          borderSide: BorderSide(color: AppColors.live, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent.withValues(alpha: 0.35),
        selectionHandleColor: AppColors.accent,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        selectedColor: AppColors.textPrimary,
        selectedTileColor: AppColors.hover,
        titleTextStyle: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
        leadingAndTrailingTextStyle: textTheme.bodySmall,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
        ),
        minVerticalPadding: 10,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hover,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.hover,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.hover,
        thumbColor: AppColors.accent,
        overlayColor: Color(0x29D4AE6A),
        valueIndicatorColor: AppColors.card,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return AppColors.textDisabled;
          return s.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.hover,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused)
              ? AppColors.accent
              : Colors.transparent,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(focusWidth),
        overlayColor: _neutralOverlay,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accent
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.onAccent),
        side: const BorderSide(color: AppColors.textMuted, width: 2),
      ),
      radioTheme: const RadioThemeData(
        fillColor: WidgetStatePropertyAll(AppColors.accent),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: AppColors.accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        dividerColor: AppColors.hover,
        overlayColor: _neutralOverlay,
      ),
      // The phone layout's bottom bar, like the sidebar: `hover` behind the
      // selected icon, unselected entries in `textSecondary`.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.hover,
        overlayColor: _neutralOverlay,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => textTheme.labelLarge?.copyWith(
            fontSize: 12,
            color: s.contains(WidgetState.selected)
                ? AppColors.textPrimary
                : AppColors.textSecondary,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: AppColors.textDisabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.large),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.large)),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
        ),
        textStyle: textTheme.bodyMedium,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => textTheme.bodyMedium?.copyWith(
            color: s.contains(WidgetState.disabled)
                ? AppColors.textDisabled
                : AppColors.textPrimary,
          ),
        ),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.card),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.card),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      // Accent thumb so scrollbars stand out on the dark surfaces; the
      // track (only drawn where a scrollbar asks for it) stays subtle.
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged)
              ? AppColors.accentHover
              : AppColors.accent,
        ),
        trackColor: const WidgetStatePropertyAll(AppColors.surface),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(AppRadius.pill),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.card,
        contentTextStyle: textTheme.bodyMedium,
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
        ),
      ),
    );
  }
}
