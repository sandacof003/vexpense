import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'exchange_rate_dao.g.dart';

/// Akses baca/tulis tabel `exchange_rates` (display-only, konversi dashboard).
@DriftAccessor(tables: [ExchangeRates])
class ExchangeRateDao extends DatabaseAccessor<AppDatabase>
    with _$ExchangeRateDaoMixin {
  ExchangeRateDao(super.db);

  Future<List<ExchangeRate>> getAll() => (select(
    exchangeRates,
  )..orderBy([(e) => OrderingTerm.asc(e.fromCurrency)])).get();

  Stream<List<ExchangeRate>> watchAll() => (select(
    exchangeRates,
  )..orderBy([(e) => OrderingTerm.asc(e.fromCurrency)])).watch();

  /// Kurs untuk pasangan mata uang tertentu.
  Future<ExchangeRate?> getPair(String from, String to) =>
      (select(exchangeRates)..where(
            (e) => e.fromCurrency.equals(from) & e.toCurrency.equals(to),
          ))
          .getSingleOrNull();

  /// Insert atau update kurs (unique key = from+to).
  Future<void> upsert(ExchangeRatesCompanion rate) =>
      into(exchangeRates).insertOnConflictUpdate(rate);
}
