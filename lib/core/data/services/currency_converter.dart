import 'dart:math' as math;

import '../daos/currency_dao.dart';
import '../daos/exchange_rate_dao.dart';

/// Status konversi mata uang.
enum CurrencyConversionStatus {
  /// Konversi berhasil; [CurrencyConversion.amountMinorUnit] valid.
  success,

  /// Kurs `from -> to` tidak ada di tabel exchange_rates.
  missingRate,

  /// Salah satu kode mata uang tidak dikenal di tabel currencies.
  unknownCurrency,
}

/// Hasil konversi satu nominal.
class CurrencyConversion {
  const CurrencyConversion.success({
    required this.amountMinorUnit,
    required this.rate,
    required this.fromCurrency,
    required this.toCurrency,
  }) : status = CurrencyConversionStatus.success;

  const CurrencyConversion.missingRate({
    required this.fromCurrency,
    required this.toCurrency,
  }) : amountMinorUnit = 0,
       rate = null,
       status = CurrencyConversionStatus.missingRate;

  const CurrencyConversion.unknownCurrency({
    required this.fromCurrency,
    required this.toCurrency,
  }) : amountMinorUnit = 0,
       rate = null,
       status = CurrencyConversionStatus.unknownCurrency;

  final CurrencyConversionStatus status;

  /// Nilai hasil dalam minor unit mata uang tujuan. 0 bila bukan [success].
  final int amountMinorUnit;

  /// Kurs yang dipakai (`to` per 1 `from`). Null bila bukan [success].
  final double? rate;

  final String fromCurrency;
  final String toCurrency;

  bool get isSuccess => status == CurrencyConversionStatus.success;
}

/// Konversi nominal antar mata uang, minor unit -> minor unit.
///
/// [rate] = jumlah satuan mata uang `to` per 1 satuan `from` (multiplier,
/// sama seperti kolom `exchange_rates.rate`). Hasil dibulatkan ke minor unit
/// terdekat karena `rate` bertipe REAL.
int convertMinorUnit({
  required int amount,
  required int fromMinorUnit,
  required int toMinorUnit,
  required double rate,
}) {
  if (amount == 0) return 0;
  final exponent = toMinorUnit - fromMinorUnit;
  final scaled = amount * rate * math.pow(10, exponent).toDouble();
  return scaled.round();
}

/// Layanan konversi mata uang (display-only, offline).
///
/// Hanya membaca rate dari tabel `exchange_rates` lokal. Konversi terjadi saat
/// query/presentasi — transaksi MVP TIDAK menyimpan rate historis (PRD §6).
class CurrencyConverter {
  const CurrencyConverter(this._currencyDao, this._exchangeRateDao);

  final CurrencyDao _currencyDao;
  final ExchangeRateDao _exchangeRateDao;

  /// Konversi [amount] (minor unit `from`) ke minor unit `to`.
  Future<CurrencyConversion> convert(
    int amount, {
    required String from,
    required String to,
  }) async {
    if (from == to) {
      return CurrencyConversion.success(
        amountMinorUnit: amount,
        rate: 1,
        fromCurrency: from,
        toCurrency: to,
      );
    }

    final fromCurrency = await _currencyDao.getByCode(from);
    final toCurrency = await _currencyDao.getByCode(to);
    if (fromCurrency == null || toCurrency == null) {
      return CurrencyConversion.unknownCurrency(
        fromCurrency: from,
        toCurrency: to,
      );
    }

    final pair = await _exchangeRateDao.getPair(from, to);
    if (pair == null) {
      return CurrencyConversion.missingRate(fromCurrency: from, toCurrency: to);
    }

    return CurrencyConversion.success(
      amountMinorUnit: convertMinorUnit(
        amount: amount,
        fromMinorUnit: fromCurrency.minorUnit,
        toMinorUnit: toCurrency.minorUnit,
        rate: pair.rate,
      ),
      rate: pair.rate,
      fromCurrency: from,
      toCurrency: to,
    );
  }
}
