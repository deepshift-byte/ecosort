import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EcoColors {
  static const forest = Color(0xFF0F766E);
  static const mint = Color(0xFF34D399);
  static const leaf = Color(0xFF10B981);
  static const sand = Color(0xFFF6FBF8);
  static const ink = Color(0xFF0B2B26);
  static const night = Color(0xFF0B1512);
  static const nightCard = Color(0xFF13221E);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F766E), Color(0xFF10B981), Color(0xFF6EE7B7)],
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: EcoColors.forest,
    brightness: brightness,
    primary: dark ? EcoColors.mint : EcoColors.forest,
    secondary: EcoColors.leaf,
    surface: dark ? EcoColors.night : EcoColors.sand,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final text = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
    bodyColor: dark ? Colors.white : EcoColors.ink,
    displayColor: dark ? Colors.white : EcoColors.ink,
  );
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      foregroundColor: dark ? Colors.white : EcoColors.ink,
    ),
    cardTheme: CardThemeData(
      color: dark ? EcoColors.nightCard : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? EcoColors.nightCard : Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
      labelTextStyle: WidgetStatePropertyAll(
        text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? EcoColors.nightCard : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
  );
}
