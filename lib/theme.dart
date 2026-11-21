import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Focus Lock design language — "Obsidian & Ember"
//
// Warm graphite surfaces, ONE ember accent, a gold highlight and a mint "all clear".
// The signature element is the safe-dial (see design/focus_dial.dart): the app is a
// vault for your attention, and the dial is the combination you turn to enter it.
//
// Every screen reads these tokens, so changing them here re-skins the whole app.
// ─────────────────────────────────────────────────────────────────────────────
const kAccent = Color(0xFFFF8A3D); // ember
const kAccentDeep = Color(0xFFC2410C); // cooled ember (gradients, pressed states)
const kGold = Color(0xFFFFC857); // highlight, lit dial ticks
const kMint = Color(0xFF6FD8B0); // ready / safe
const kBg = Color(0xFF0D0B0A);
const kSurface = Color(0xFF171413);
const kSurface2 = Color(0xFF221E1C);
const kOutline = Color(0xFF342E2B);
const kText = Color(0xFFF5EFE9);
const kTextDim = Color(0xFFA89F97);
const kOnAccent = Color(0xFF1B0F06); // dark text on ember (white on ember fails contrast)
const kFont = 'IBMPlexSansArabic';

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: kFont);
  final shape24 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    colorScheme: const ColorScheme.dark(
      primary: kAccent,
      onPrimary: kOnAccent,
      secondary: kGold,
      onSecondary: kOnAccent,
      surface: kSurface,
      onSurface: kText,
      surfaceContainerHighest: kSurface2,
      outline: kOutline,
      error: Color(0xFFFF6B6B),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 20, fontWeight: FontWeight.w700, color: kText),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: kOnAccent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: shape24,
        textStyle: const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: kOutline),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: shape24,
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kAccent)),
    chipTheme: ChipThemeData(
      backgroundColor: kSurface2,
      selectedColor: kAccent.withOpacity(.25),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontFamily: kFont, color: kText),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurface2,
      contentTextStyle: const TextStyle(fontFamily: kFont, color: kText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kAccent, width: 1.4),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAccent,
      foregroundColor: kOnAccent,
    ),
    listTileTheme: const ListTileThemeData(iconColor: kAccent),
    dividerTheme: const DividerThemeData(color: kOutline, space: 1, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccent, linearTrackColor: kSurface2),
    sliderTheme: const SliderThemeData(
      activeTrackColor: kAccent,
      thumbColor: kAccent,
      inactiveTrackColor: kOutline,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kSurface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: kAccent, selectionHandleColor: kAccent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? kOnAccent : kTextDim),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? kAccent : kSurface2),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

/// Rounded card used by lists everywhere
BoxDecoration cardBox([double r = 18]) => BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: kOutline),
    );
