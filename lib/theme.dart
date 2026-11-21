import 'package:flutter/material.dart';

// Look of the whole app: calm, rounded, red accent. Day and night palettes.
// Colors are read through getters, so the whole app switches with [Pal.dark] (see rebuildAll in main.dart).
class Pal {
  static bool dark = true;
  static Color pick(int light, int night) => Color(dark ? night : light);
}

Color get kAccent => Pal.pick(0xFFE23B3B, 0xFFFF5A5A); // red accent (a bit deeper in daylight for contrast)
Color get kBg => Pal.pick(0xFFF6F6F9, 0xFF0E0E10); // page
Color get kSurface => Pal.pick(0xFFFFFFFF, 0xFF1A1A1D); // cards
Color get kSurface2 => Pal.pick(0xFFEDEDF2, 0xFF26262A); // chips, fields, tracks
Color get kOutline => Pal.pick(0xFFE1E1E8, 0xFF2E2E33);
Color get kInk => Pal.pick(0xFF17171C, 0xFFF4F4F6); // main text
Color get kSoft => Pal.pick(0xB317171C, 0xB3FFFFFF); // secondary text
Color get kMuted => Pal.pick(0x8A17171C, 0x99FFFFFF); // hints
Color get kFaint => Pal.pick(0x6117171C, 0x61FFFFFF); // very light hints
Color get kOk => Pal.pick(0xFF1E9E5A, 0xFF4ADE80); // done / success
Color get kWarn => Pal.pick(0xFFC9780B, 0xFFFFB347); // warning

ThemeData buildTheme() {
  final b = Pal.dark ? Brightness.dark : Brightness.light;
  final base = ThemeData(brightness: b, useMaterial3: true);
  final r24 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFFF4D4D), brightness: b).copyWith(
    primary: kAccent,
    onPrimary: Colors.white,
    secondary: kAccent,
    surface: kSurface,
    onSurface: kInk,
    outline: kOutline,
    surfaceContainerHighest: kSurface2,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    textTheme: base.textTheme.apply(bodyColor: kInk, displayColor: kInk),
    dividerColor: kOutline,
    dividerTheme: DividerThemeData(color: kOutline, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: kAccent.withOpacity(.16),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500, color: s.contains(WidgetState.selected) ? kAccent : kMuted)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? kAccent : kMuted)),
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: kOutline)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: r24,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: BorderSide(color: kOutline),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: r24,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kSurface2,
      selectedColor: kAccent.withOpacity(.22),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: kInk),
    ),
    dialogTheme: DialogThemeData(backgroundColor: kSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Pal.dark ? kSurface2 : const Color(0xFF2A2A30),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      hintStyle: TextStyle(color: kMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: kAccent, foregroundColor: Colors.white),
    listTileTheme: ListTileThemeData(iconColor: kAccent, textColor: kInk),
    tabBarTheme: TabBarThemeData(labelColor: kAccent, unselectedLabelColor: kMuted, indicatorColor: kAccent, dividerColor: Colors.transparent),
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kAccent : null)),
    switchTheme: SwitchThemeData(trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kAccent : null)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: kAccent, linearTrackColor: kSurface2, circularTrackColor: kSurface2),
  );
}

/// Rounded card used by lists everywhere
BoxDecoration cardBox([double r = 18]) => BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: kOutline),
    );

/// Rebuilds every widget (after the day / night mode changes) without losing the navigation
void rebuildAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
