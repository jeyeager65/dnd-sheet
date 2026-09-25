import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's visual identity: a dark leather-bound ledger-book cover,
/// parchment ink, and a teal accent - chosen over Forge/Field Manual
/// mockups earlier. Kept as named constants (not just baked into
/// ThemeData) because several custom widgets (ExpandableRow, StatGrid,
/// Tally) need direct access to these colors beyond what
/// Theme.of(context) exposes.
class AppColors {
  AppColors._();

  static const paper = Color(0xFF1B1E29);
  static const paper2 = Color(0xFF252A38);
  static const ink = Color(0xFFE9E4D3);
  static const inkDim = Color(0xFF9A9686);
  static const rule = Color(0xFF3A3F4E);
  static const accent = Color(0xFF4A8B86);
  static const accentSoft = Color(0xFF35635F);
  static const danger = Color(0xFFE05A4E);
  static const onAccent = Color(0xFFF0ECDD);
}

class AppTheme {
  AppTheme._();

  /// The character's name on the sheet header uses this - a sturdy upright
  /// slab serif, picked after two rejected alternatives (a typewriter face,
  /// then an italic serif) landed as too flippant or too formal.
  static TextStyle nameStyle({double fontSize = 22}) => GoogleFonts.bitter(
    fontWeight: FontWeight.w800,
    fontSize: fontSize,
    color: AppColors.ink,
    letterSpacing: 0.3,
  );

  /// Numbers that need to line up in columns (stat grids, currency, dice
  /// math) use JetBrains Mono with tabular figures.
  static TextStyle dataStyle({
    double fontSize = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: weight,
    color: color ?? AppColors.ink,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static ThemeData get data {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.paper,
      fontFamily: GoogleFonts.sourceSans3().fontFamily,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.paper,
        primary: AppColors.accent,
        onPrimary: AppColors.onAccent,
        secondary: AppColors.accentSoft,
        error: AppColors.danger,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.sourceSans3TextTheme(base.textTheme)
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: nameStyle(fontSize: 19),
        shape: const Border(
          bottom: BorderSide(color: AppColors.rule, width: 3),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.paper2,
        indicatorColor: AppColors.accent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.sourceSans3(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: selected ? AppColors.onAccent : AppColors.inkDim,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.onAccent : AppColors.inkDim,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.rule,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          textStyle: GoogleFonts.sourceSans3(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accentSoft),
          textStyle: GoogleFonts.sourceSans3(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.sourceSans3(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paper2,
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.inkDim, width: 2),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.rule),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        labelStyle: GoogleFonts.sourceSans3(
          fontSize: 16,
          color: AppColors.inkDim,
        ),
        // A dropdown always has a value, so its label is always in the
        // floating (shrunk) state - unlike a blank text field, which
        // shows labelStyle at full size until you type into it. Without
        // this, the floated label derives its size from labelStyle via
        // Flutter's default shrink, which read as illegibly tiny.
        floatingLabelStyle: GoogleFonts.sourceSans3(
          fontSize: 14,
          letterSpacing: 0.4,
          color: AppColors.inkDim,
        ),
      ),
    );
  }
}
