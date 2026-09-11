/// Locale presentasi yang didukung V Expense (ID/EN).
///
/// Sengaja enum sendiri (bukan `Locale` dari dart:ui) supaya formatter tetap
/// pure Dart dan gampang di-unit-test tanpa binding Flutter.
enum AppLocale {
  id,
  en;

  /// Separator ribuan untuk locale ini.
  String get groupSeparator => this == AppLocale.id ? '.' : ',';

  /// Separator desimal untuk locale ini.
  String get decimalSeparator => this == AppLocale.id ? ',' : '.';
}
