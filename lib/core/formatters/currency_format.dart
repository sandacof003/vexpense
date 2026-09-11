/// Metadata format sebuah currency: kode, minor unit, dan simbol.
///
/// Sumber kebenaran di runtime adalah tabel `currencies` (kolom `minor_unit`
/// dan `symbol`) — bangun instance dari baris DB:
/// `CurrencyFormat(code: c.code, minorUnit: c.minorUnit, symbol: c.symbol)`.
/// [kDefaultCurrencyFormats] hanya fallback offline (nilainya identik dengan
/// seed DB di `database.dart`) supaya formatter bisa dipakai tanpa DB
/// (mis. unit test atau layar sebelum DB siap).
class CurrencyFormat {
  const CurrencyFormat({
    required this.code,
    required this.minorUnit,
    required this.symbol,
  });

  /// Kode ISO-ish, mis. 'IDR'.
  final String code;

  /// Jumlah digit desimal penyimpanan (IDR/JPY = 0, USD = 2, USDT = 6).
  /// Nilai tersimpan = minor unit integer, JANGAN pernah double.
  final int minorUnit;

  /// Simbol tampil, mis. 'Rp'.
  final String symbol;

  /// Fallback dari kode; default IDR bila tidak dikenal (selaras PRD).
  factory CurrencyFormat.fromCode(String? code) =>
      kDefaultCurrencyFormats[code] ?? kDefaultCurrencyFormats['IDR']!;
}

/// Identik dengan `_seedCurrencies` di `lib/core/data/database.dart`.
const Map<String, CurrencyFormat> kDefaultCurrencyFormats = {
  'IDR': CurrencyFormat(code: 'IDR', minorUnit: 0, symbol: 'Rp'),
  'USD': CurrencyFormat(code: 'USD', minorUnit: 2, symbol: r'$'),
  'JPY': CurrencyFormat(code: 'JPY', minorUnit: 0, symbol: '¥'),
  'USDT': CurrencyFormat(code: 'USDT', minorUnit: 6, symbol: '₮'),
  'SGD': CurrencyFormat(code: 'SGD', minorUnit: 2, symbol: r'S$'),
  'MYR': CurrencyFormat(code: 'MYR', minorUnit: 2, symbol: 'RM'),
  'THB': CurrencyFormat(code: 'THB', minorUnit: 2, symbol: '฿'),
};
