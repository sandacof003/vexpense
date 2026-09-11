import 'package:flutter/material.dart';

/// Tema aplikasi V Expense.
///
/// Dark theme adalah default DAN satu-satunya tema di MVP (PRD v0.4.1:
/// "Dark mode default"). Tidak ada light theme — [ThemeMode.dark] dipakai
/// permanen supaya instalasi baru selalu membuka tema gelap.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF4CAF50);

  /// Satu instance dipakai app-wide (MaterialApp.theme/darkTheme).
  static final ThemeData dark = _buildDark();

  static ThemeData _buildDark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
    );
  }
}
