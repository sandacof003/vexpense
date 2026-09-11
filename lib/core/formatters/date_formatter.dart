import 'app_locale.dart';

/// Gaya tampilan tanggal.
enum DateStyle {
  /// `5 Agustus 2026` / `August 5, 2026`
  full,

  /// `5 Agu 2026` / `Aug 5, 2026`
  medium,

  /// `05/08/2026` (dd/MM/yyyy, universal)
  short,

  /// `2026-08-05`
  iso,
}

/// Format tanggal lokal ID/EN tanpa package intl (pure Dart, mudah ditest).
class DateFormatter {
  const DateFormatter({this.locale = AppLocale.id});

  final AppLocale locale;

  static const List<String> _monthsId = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];
  static const List<String> _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _daysId = [
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
  ];
  static const List<String> _daysEn = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  String _monthName(int month, {bool short = false}) {
    final names = locale == AppLocale.id ? _monthsId : _monthsEn;
    final full = names[month - 1];
    return short ? full.substring(0, 3) : full;
  }

  /// Nama hari (Senin/Monday). `DateTime.weekday`: 1 = Senin … 7 = Minggu.
  String dayName(DateTime date) {
    final names = locale == AppLocale.id ? _daysId : _daysEn;
    return names[date.weekday - 1];
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  /// Format tanggal sesuai [style] dan locale formatter ini.
  String format(DateTime date, {DateStyle style = DateStyle.medium}) {
    switch (style) {
      case DateStyle.full:
        return locale == AppLocale.id
            ? '${date.day} ${_monthName(date.month)} ${date.year}'
            : '${_monthName(date.month)} ${date.day}, ${date.year}';
      case DateStyle.medium:
        return locale == AppLocale.id
            ? '${date.day} ${_monthName(date.month, short: true)} ${date.year}'
            : '${_monthName(date.month, short: true)} ${date.day}, ${date.year}';
      case DateStyle.short:
        return '${_two(date.day)}/${_two(date.month)}/${date.year}';
      case DateStyle.iso:
        return '${date.year}-${_two(date.month)}-${_two(date.day)}';
    }
  }

  /// Format tanggal + jam, mis. `5 Agu 2026 14.30` (ID) / `Aug 5, 2026 14:30` (EN).
  String formatDateTime(DateTime date) {
    final sep = locale == AppLocale.id ? '.' : ':';
    return '${format(date)} ${_two(date.hour)}$sep${_two(date.minute)}';
  }
}
