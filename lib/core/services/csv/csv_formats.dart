/// Helper murni untuk parsing angka & tanggal dari CSV Expense IQ.
///
/// Tanpa dependency Flutter/Drift — murni Dart, jadi mudah di-unit-test.
/// Semua aturan diturunkan dari PRD §7 "Parsing angka".
library;

/// Format tanggal yang didukung, dalam urutan percobaan.
///
/// Expense IQ export beragam regional; MVP mendukung urutan yang paling umum.
/// [CsvDateParser] mencoba format satu per satu sampai cocok.
const List<String> kSupportedDateFormats = <String>[
  'yyyy-MM-dd',
  'dd/MM/yyyy',
  'dd-MM-yyyy',
  'MM/dd/yyyy',
  'dd/MM/yy',
];

/// Minor unit per kode mata uang (ISO 4217) — satu-satunya sumber skala nominal.
///
/// PRD §6: IDR/JPY = 0 (integer biasa), USD/SGD/MYR/THB = 2, USDT = 6.
/// Disuntikkan ke [CsvNumberParser] supaya parser tetap murni (tidak baca DB).
const Map<String, int> kCurrencyMinorUnits = <String, int>{
  'IDR': 0,
  'JPY': 0,
  'USD': 2,
  'SGD': 2,
  'MYR': 2,
  'THB': 2,
  'USDT': 6,
};

/// Parser nominal dari string ke integer minor unit currency.
///
/// Aturan (PRD §7):
/// - Simbol mata uang (`Rp`, `$`, `¥`, `₮`, `IDR`, dst.) di-strip.
/// - Separator ribuan titik/spasi (`1.500.000`, `1 500 000`) diabaikan.
/// - Separator desimal: koma ATAU titik. Disambiguasi dengan aturan digit
///   terakhir — grup 3 digit terakhir berarti separator ribuan, bukan desimal.
///   Contoh: `1.500` -> 1500 (bulat); `1.50` -> 1.50 (desimal); `1500000.50`.
/// - Skala mengikuti minor unit currency: `25000` IDR -> 25000, bukan 2500000.
/// - Digit di luar minor unit dibulatkan half-up (`25000.50` IDR -> 25001).
/// - Aritmetika integer, tidak lewat `double` (menghindari galat pembulatan).
/// - Tanda negatif `-` atau dalam kurung `(1500)` dianggap pengeluaran
///   (nilai dikembalikan positif + flag [isNegative]).
class CsvNumberParser {
  const CsvNumberParser({
    this.minorUnitsByCurrency = kCurrencyMinorUnits,
    this.fallbackMinorUnit = 2,
  });

  /// Peta minor unit per kode mata uang (default [kCurrencyMinorUnits]).
  final Map<String, int> minorUnitsByCurrency;

  /// Dipakai bila currency tidak ada di [minorUnitsByCurrency]
  /// (ISO 4217 default = 2).
  final int fallbackMinorUnit;

  /// Minor unit untuk [currency] (case-insensitive).
  int minorUnitFor(String currency) =>
      minorUnitsByCurrency[currency.trim().toUpperCase()] ?? fallbackMinorUnit;

  /// Hasil parse: [minorUnits] selalu positif, [isNegative] menandai negatif.
  ///
  /// [currency] wajib: skala nominal bergantung padanya (IDR/JPY 0 desimal).
  ({int minorUnits, bool isNegative}) parse(
    String raw, {
    required String currency,
  }) {
    var s = raw.trim();
    var negative = false;

    if (s.isEmpty) {
      throw const FormatException('Nominal kosong');
    }

    // Tanda dalam kurung: "(1500)" = negatif.
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1).trim();
    }

    // Strip simbol & kode mata uang (huruf), pertahankan digit & pemisah.
    s = s.replaceAll(RegExp(r'[A-Za-z]'), '');
    s = s.replaceAll(RegExp(r'[^0-9.,\-\s]'), '').trim();

    if (s.isEmpty) {
      throw const FormatException('Nominal tidak mengandung angka');
    }

    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1).trim();
    }

    // Hapus spasi pemisah ribuan.
    s = s.replaceAll(' ', '');

    // Normalisasi pemisah: tentukan mana desimal mana ribuan.
    final hasComma = s.contains(',');
    final hasDot = s.contains('.');

    if (hasComma && hasDot) {
      // Keduanya ada: yang terakhir = desimal, yang lain = ribuan.
      final lastComma = s.lastIndexOf(',');
      final lastDot = s.lastIndexOf('.');
      if (lastComma > lastDot) {
        s = _normalize(s, decimalChar: ',');
      } else {
        s = _normalize(s, decimalChar: '.');
      }
    } else if (hasComma) {
      final parts = s.split(',');
      if (parts.length > 1 && parts.last.length == 3) {
        // "1,500" ambigu; anggap ribuan bila persis 3 digit (gaya ID).
        s = parts.join('');
      } else {
        s = _normalize(s, decimalChar: ',');
      }
    } else if (hasDot) {
      final parts = s.split('.');
      if (parts.length > 1 && parts.last.length == 3) {
        s = parts.join('');
      } else {
        s = _normalize(s, decimalChar: '.');
      }
    }

    if (s.isEmpty) {
      throw const FormatException('Nominal tidak valid setelah normalisasi');
    }

    // Skala ke minor unit currency — aritmetika integer, TANPA `double`.
    final minorUnits = _toMinorUnits(s, minorUnitFor(currency));

    return (minorUnits: minorUnits, isNegative: negative);
  }

  /// Konversi desimal ternormalisasi (separator `.`) ke minor unit.
  ///
  /// [scale] = jumlah digit minor (IDR/JPY 0, USD 2, USDT 6). Digit di luar
  /// [scale] dibulatkan half-up. Throws [FormatException] kalau bukan angka /
  /// di luar rentang integer 64-bit.
  static int _toMinorUnits(String normalized, int scale) {
    final dot = normalized.indexOf('.');
    final whole = dot < 0 ? normalized : normalized.substring(0, dot);
    final frac = dot < 0 ? '' : normalized.substring(dot + 1);

    if (!_isDigits(whole) || !_isDigits(frac)) {
      throw FormatException('Nominal tidak valid: $normalized');
    }

    // Ambil tepat `scale` digit pecahan; sisanya hanya dipakai untuk rounding.
    final kept = frac.padRight(scale, '0').substring(0, scale);
    final digits = '${whole.isEmpty ? '0' : whole}$kept';
    var value = int.tryParse(digits);
    if (value == null) {
      throw FormatException('Nominal di luar rentang: $normalized');
    }

    if (frac.length > scale && frac.codeUnitAt(scale) >= 0x35 /* '5' */ ) {
      value += 1; // half-up
    }
    return value;
  }

  static bool _isDigits(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  static String _normalize(String s, {required String decimalChar}) {
    final other = decimalChar == ',' ? '.' : ',';
    final withoutThousands = s.replaceAll(other, '');
    return withoutThousands.replaceAll(decimalChar, '.');
  }
}

/// Parser tanggal CSV.
class CsvDateParser {
  const CsvDateParser();

  /// Parse string tanggal; return DateTime date-only (UTC) atau throw.
  ///
  /// Format yang didukung terdokumentasi di [kSupportedDateFormats].
  static DateTime parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      throw const FormatException('Tanggal kosong');
    }

    for (final fmt in kSupportedDateFormats) {
      final dt = _tryParse(s, fmt);
      if (dt != null) return DateTime.utc(dt.year, dt.month, dt.day);
    }
    throw FormatException('Format tanggal tidak dikenal: "$raw"');
  }

  static DateTime? _tryParse(String s, String fmt) {
    final parts = s.split(RegExp(r'[-/]'));
    final fmtParts = fmt.split(RegExp(r'[-/]'));
    if (parts.length != 3 || fmtParts.length != 3) return null;

    int? year, month, day;
    for (var i = 0; i < 3; i++) {
      final token = fmtParts[i];
      final value = int.tryParse(parts[i]);
      if (value == null) return null;
      if (token == 'yyyy' || token == 'yy') {
        year = token == 'yy' ? (value < 100 ? 2000 + value : value) : value;
      } else if (token == 'MM') {
        month = value;
      } else if (token == 'dd') {
        day = value;
      }
    }

    if (year == null || month == null || day == null) return null;
    if (year < 1900 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;

    // Validasi overflow tanggal (mis. 31 Feb).
    final dt = DateTime.utc(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;

    return dt;
  }
}
