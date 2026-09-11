import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'account_dao.g.dart';

/// Akses baca/tulis tabel `accounts`.
@DriftAccessor(tables: [Accounts])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  /// Semua akun, urut berdasarkan nama.
  Future<List<Account>> getAll() =>
      (select(accounts)..orderBy([(a) => OrderingTerm.asc(a.name)])).get();

  Stream<List<Account>> watchAll() =>
      (select(accounts)..orderBy([(a) => OrderingTerm.asc(a.name)])).watch();

  Future<Account?> getById(int id) =>
      (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Cari akun berdasarkan nama (case-insensitive, exact match).
  Future<Account?> getByName(String name) => (select(
    accounts,
  )..where((a) => a.name.lower().equals(name.toLowerCase()))).getSingleOrNull();

  /// Insert akun. Return id baru.
  Future<int> insert(AccountsCompanion account) =>
      into(accounts).insert(account);

  /// Update akun. Return true bila ada baris yang diubah.
  Future<bool> replace(Account account) => update(accounts).replace(account);

  /// Hapus akun. Gagal (lempar exception) bila masih punya transaksi karena
  /// `ON DELETE RESTRICT` di tabel transactions.
  Future<int> remove(int id) =>
      (delete(accounts)..where((a) => a.id.equals(id))).go();
}
