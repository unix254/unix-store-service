import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand colours
  static const Color primary   = Color(0xFF00796B); // Teal 700 – premium, halal-friendly
  static const Color secondary = Color(0xFFFFA000); // Amber 700 – warmth, East Africa
  static const Color surface   = Color(0xFFFFFFFF);
  static const Color scaffold  = Color(0xFFF4F6F8);
  static const Color sidebar   = Color(0xFF1A1A2E); // Dark navy – premium sidecar
  static const Color debtRed   = Color(0xFFD32F2F);
  static const Color paidGreen = Color(0xFF388E3C);
  static const Color pinBg     = Color(0xFF1A1A2E);
  static const Color pinTeal   = Color(0xFF4DB6AC);
  static const Color pinSlate  = Color(0xFF263238);
  static const Color pinMuted  = Color(0xFF90A4AE);

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        surface: surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: scaffold,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        filled: true,
        fillColor: const Color(0xFFF0F2F4),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
