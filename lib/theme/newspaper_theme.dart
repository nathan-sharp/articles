import 'package:flutter/material.dart';

/// Design tokens and Material ThemeData configuring the print newspaper aesthetic.
class NewspaperTheme {
  NewspaperTheme._();

  // User-specified Color Palette Tokens
  static const Color newsprintBackground = Color(0xFFE8CDAF);
  static const Color cardSurface = Color(0xFFECD5BD);
  static const Color containerAccent = Color(0xFFDFBF9C);
  static const Color inputSurface = Color(0xFFF2E2D2);
  static const Color inkBlack = Color(0xFF232436);
  static const Color inkSecondary = Color(0xFF4E506B);
  static const Color inkMuted = Color(0xFF757796);
  static const Color ruleLine = Color(0xFF232436);
  static const Color editorialAccent = Color(0xFF8B2C24);
  static const Color unreadDotColor = Color(0xFF8B2C24);

  // Typography Family Definitions
  static const String serifFamily = 'Georgia';
  static const String monospaceFamily = 'Courier New';

  /// Primary ThemeData representing classic print newspaper styling.
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: newsprintBackground,
      colorScheme: const ColorScheme.light(
        primary: inkBlack,
        onPrimary: newsprintBackground,
        secondary: editorialAccent,
        onSecondary: newsprintBackground,
        surface: cardSurface,
        onSurface: inkBlack,
        error: editorialAccent,
        onError: newsprintBackground,
      ),
      dividerColor: ruleLine,
      dividerTheme: const DividerThemeData(
        color: ruleLine,
        thickness: 1.0,
        space: 1.0,
      ),
      cardTheme: const CardThemeData(
        color: cardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ruleLine, width: 1.0),
          borderRadius: BorderRadius.zero,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: newsprintBackground,
        foregroundColor: inkBlack,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: serifFamily,
          fontSize: 22.0,
          fontWeight: FontWeight.bold,
          color: inkBlack,
          letterSpacing: 1.5,
        ),
        shape: Border(
          bottom: BorderSide(color: ruleLine, width: 2.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: inkBlack,
          foregroundColor: newsprintBackground,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          textStyle: const TextStyle(
            fontFamily: monospaceFamily,
            fontSize: 13.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkBlack,
          side: const BorderSide(color: ruleLine, width: 1.5),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          textStyle: const TextStyle(
            fontFamily: monospaceFamily,
            fontSize: 13.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: inkBlack,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          textStyle: const TextStyle(
            fontFamily: monospaceFamily,
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: inputSurface,
        contentPadding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: ruleLine, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: ruleLine, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: inkBlack, width: 2.0),
        ),
        labelStyle: TextStyle(
          fontFamily: monospaceFamily,
          color: inkSecondary,
          fontSize: 13.0,
        ),
        hintStyle: TextStyle(
          fontFamily: serifFamily,
          color: inkMuted,
          fontSize: 13.0,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: newsprintBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ruleLine, width: 2.0),
          borderRadius: BorderRadius.zero,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: newsprintBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ruleLine, width: 2.0),
          borderRadius: BorderRadius.zero,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: serifFamily,
          fontSize: 34.0,
          fontWeight: FontWeight.w900,
          color: inkBlack,
          letterSpacing: 2.0,
          height: 1.1,
        ),
        headlineLarge: TextStyle(
          fontFamily: serifFamily,
          fontSize: 26.0,
          fontWeight: FontWeight.bold,
          color: inkBlack,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          fontFamily: serifFamily,
          fontSize: 20.0,
          fontWeight: FontWeight.bold,
          color: inkBlack,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontFamily: serifFamily,
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
          color: inkBlack,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          fontFamily: serifFamily,
          fontSize: 15.0,
          fontWeight: FontWeight.bold,
          color: inkBlack,
        ),
        bodyLarge: TextStyle(
          fontFamily: serifFamily,
          fontSize: 16.0,
          color: inkBlack,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          fontFamily: serifFamily,
          fontSize: 14.0,
          color: inkBlack,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontFamily: monospaceFamily,
          fontSize: 11.0,
          color: inkSecondary,
          letterSpacing: 0.5,
        ),
        labelLarge: TextStyle(
          fontFamily: monospaceFamily,
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          color: inkBlack,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
