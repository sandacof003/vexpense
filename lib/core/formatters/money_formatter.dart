import 'app_locale.dart';
import 'currency_format.dart';

/// Format & parse nilai uang minor-unit TANPA floating point.
///
/// Nilai uang di V Expense disimpan sebagai integer minor unit
/// (lihat `currencies.minor_unit`: IDR/JPY = 0, USD = 2, USDT = 6).
/// Semua konversi tampil↔simpan di sini murni operasi integer/string,
/// tidak pernah `double`, supaya tidak ada error pembulatan.
class MoneyFormatter {
  const MoneyFormatter({this.locale = AppLocale.id});

  final AppLocale locale;

  /// Format minor unit jadi nominal tanpa simbol.
  ///
  /// Contoh (locale ID): IDR 1500000 minor → `1.500.000`;
  /// USD 2550 minor → `25,50`; USDT 1500000 minor → `1,500000`.
  String formatMinor(int minorUnit, CurrencyFormat currency) {
    final negative = minorUnit < 0;
    final abs = minorUnit.abs();
    final factor = _pow10(currency.minorUnit);
    final major = abs ~/ factor;
    final frac = abs % factor;
    final buf = StringBuffer();
    if (negative) buf.write('-');
    buf.write(_groupDigits(major.toString(), locale.groupSeparator));
    if (currency.minorUnit > 0) {
      buf.write(locale.decimalSeparator);
      buf.write(frac.toString().padLeft(currency.minorUnit, '0'));
    }
    return buf.toString();
  }

  /// Format minor unit lengkap dengan simbol currency, mis. `Rp 1.500.000`.
  String format(int minorUnit, CurrencyFormat currency) =>
      '${currency.symbol} ${formatMinor(minorUnit, currency)}';

  /// Parse teks nominal lokal jadi minor unit integer.
  ///
  /// - `1.500.000` (locale ID, IDR) → `1500000`
  /// - `25,50` (locale ID, USD) → `2550`
  /// - `1,500,000` (locale EN, IDR) → `1500000`
  ///
  /// Simbol currency dan spasi diabaikan. Throw [FormatException] bila input
  /// bukan angka, fraksi melebihi [CurrencyFormat.minorUnit], atau currency
  /// minor-unit 0 (IDR/JPY) diberi fraksi.
  int parseMinor(String input, CurrencyFormat currency) {
    var text = input.trim();
    text = text.replaceAll(currency.symbol, '').trim();
    if (text.isEmpty) {
      throw FormatException('Nominal kosong', input);
    }
    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1).trim();
    } else if (text.startsWith('+')) {
      text = text.substring(1).trim();
    }
    // Buang separator ribuan; sisakan digit dan (maksimal satu) separator desimal.
    text = text.replaceAll(locale.groupSeparator, '');
    text = text.replaceAll(' ', '');
    if (text.isEmpty) {
      throw FormatException('Nominal kosong', input);
    }
    final parts = text.split(locale.decimalSeparator);
    if (parts.length > 2) {
      throw FormatException('Separator desimal lebih dari satu', input);
    }
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final fracPart = parts.length == 2 ? parts[1] : '';
    if (!_allDigits(intPart)) {
      throw FormatException('Bukan angka valid', input);
    }
    if (fracPart.isNotEmpty) {
      if (currency.minorUnit == 0) {
        throw FormatException(
          '${currency.code} tidak memakai desimal',
          input,
        );
      }
      if (!_allDigits(fracPart)) {
        throw FormatException('Bukan angka valid', input);
      }
      if (fracPart.length > currency.minorUnit) {
        throw FormatException(
          'Desimal ${currency.code} maksimal ${currency.minorUnit} digit',
          input,
        );
      }
    }
    final major = int.parse(intPart.isEmpty ? '0' : intPart);
    final frac = fracPart.isEmpty
        ? 0
        : int.parse(fracPart.padRight(currency.minorUnit, '0'));
    final minor = major * _pow10(currency.minorUnit) + frac;
    return negative ? -minor : minor;
  }

  static bool _allDigits(String s) {
    if (s.isEmpty) return false;
    for (final c in s.codeUnits) {
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  static int _pow10(int n) {
    var result = 1;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }

  static String _groupDigits(String digits, String separator) {
    if (digits.length <= 3) return digits;
    final buf = StringBuffer();
    var count = 0;
    for (var i = digits.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write(separator);
      buf.write(digits[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }
}
