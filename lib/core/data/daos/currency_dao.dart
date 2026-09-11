import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'currency_dao.g.dart';

/// Akses baca/tulis tabel `currencies`.
@DriftAccessor(tables: [Currencies])
class CurrencyDao extends DatabaseAccessor<AppDatabase>
    with _$CurrencyDaoMixin {
  CurrencyDao(super.db);

  /// Semua mata uang, urut berdasarkan kode.
  Future<List<Currency>> getAll() =>
      (select(currencies)..orderBy([(c) => OrderingTerm.asc(c.code)])).get();

  /// Stream semua mata uang (auto-update).
  Stream<List<Currency>> watchAll() =>
      (select(currencies)..orderBy([(c) => OrderingTerm.asc(c.code)])).watch();

  /// Ambil satu mata uang berdasarkan kode, atau null bila tidak ada.
  Future<Currency?> getByCode(String code) =>
      (select(currencies)..where((c) => c.code.equals(code))).getSingleOrNull();

  /// Insert atau update (replace) satu mata uang.
  Future<void> upsert(CurrenciesCompanion currency) =>
      into(currencies).insertOnConflictUpdate(currency);
}
