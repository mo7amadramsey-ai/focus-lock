import 'package:flutter/material.dart';

// Shared look of the whole app (dark, calm, red accent)
const kAccent = Color(0xFFFF4D4D);
const kBg = Color(0xFF0E0E10);
const kSurface = Color(0xFF1A1A1D);
const kSurface2 = Color(0xFF26262A);
const kOutline = Color(0xFF2E2E33);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final shape24 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      primary: kAccent,
      secondary: kAccent,
      surface: kSurface,
      surfaceContainerHighest: kSurface2,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: shape24,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: kOutline),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: shape24,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kSurface2,
      selectedColor: kAccent.withOpacity(.25),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: Colors.white),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAccent,
      foregroundColor: Colors.white,
    ),
    listTileTheme: const ListTileThemeData(iconColor: kAccent),
  );
}

/// Rounded card used by lists everywhere
BoxDecoration cardBox([double r = 18]) => BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: kOutline),
    );
