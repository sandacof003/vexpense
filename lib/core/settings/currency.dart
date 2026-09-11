/// Currency yang didukung V Expense (PRD v0.4.1 §Region/F6).
///
/// [minorUnits] mengikuti aturan PRD: uang disimpan INTEGER dalam minor unit
/// currency masing-masing (IDR/JPY = 0, USD = 2, USDT = 6).
enum AppCurrency {
  idr('IDR', 0, 'Rupiah Indonesia'),
  jpy('JPY', 0, 'Yen Jepang'),
  myr('MYR', 2, 'Ringgit Malaysia'),
  sgd('SGD', 2, 'Dolar Singapura'),
  thb('THB', 2, 'Baht Thailand'),
  usd('USD', 2, 'Dolar AS'),
  usdt('USDT', 6, 'Tether');

  const AppCurrency(this.code, this.minorUnits, this.displayName);

  final String code;
  final int minorUnits;
  final String displayName;

  /// Resolve currency dari kode tersimpan; fallback ke [AppCurrency.idr]
  /// bila kosong/tidak dikenal (default PRD: IDR).
  static AppCurrency fromCode(String? code) {
    for (final currency in AppCurrency.values) {
      if (currency.code == code) return currency;
    }
    return AppCurrency.idr;
  }
}
