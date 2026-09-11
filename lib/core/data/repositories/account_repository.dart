import 'package:drift/drift.dart';

import '../database.dart';
import '../enums.dart';
import '../daos/account_dao.dart';
import '../daos/transaction_dao.dart';
import 'repository_contracts.dart';

/// Error domain untuk operasi yang ditolak karena constraint data.
sealed class DataException implements Exception {
  final String message;
  const DataException(this.message);

  @override
  String toString() => message;
}

/// Akun masih punya transaksi → tidak bisa dihapus.
class AccountInUseException extends DataException {
  const AccountInUseException() : super('Akun masih punya transaksi');
}

/// Nama kategori/akun sudah dipakai.
class DuplicateNameException extends DataException {
  const DuplicateNameException(super.message);
}

/// Repository akun: operasi CRUD + validasi bisnis di atas DAO.
///
/// Widget/FE hanya boleh pakai repository, bukan DAO/Drift langsung.
class AccountRepository implements AccountsRepository {
  AccountRepository(this._db, this._accountDao, this._transactionDao);

  final AppDatabase _db;
  final AccountDao _accountDao;
  final TransactionDao _transactionDao;

  @override
  Future<List<Account>> getAll() => _accountDao.getAll();
  @override
  Stream<List<Account>> watchAll() => _accountDao.watchAll();
  @override
  Future<Account?> getById(int id) => _accountDao.getById(id);

  /// Buat akun baru. Nama harus unik (case-insensitive).
  @override
  Future<Account> create({
    required String name,
    required AccountType type,
    String currency = 'IDR',
    int openingBalance = 0,
  }) async {
    final existing = await _accountDao.getByName(name);
    if (existing != null) {
      throw const DuplicateNameException('Nama akun sudah dipakai');
    }
    final id = await _accountDao.insert(
      AccountsCompanion.insert(
        name: name,
        type: type,
        currency: currency,
        openingBalance: Value(openingBalance),
      ),
    );
    return (await _accountDao.getById(id))!;
  }

  /// Update akun (termasuk ganti nama). Nama baru tidak boleh bentrok.
  Future<void> update(Account account, {required String newName}) async {
    final existing = await _accountDao.getByName(newName);
    if (existing != null && existing.id != account.id) {
      throw const DuplicateNameException('Nama akun sudah dipakai');
    }
    await _accountDao.replace(account.copyWith(name: newName));
  }

  /// Hapus akun. Ditolak bila masih punya transaksi (ON DELETE RESTRICT).
  @override
  Future<void> delete(int id) async {
    await _db.transaction(() async {
      final count = await _transactionDao.getByAccount(id);
      if (count.isNotEmpty) {
        throw const AccountInUseException();
      }
      await _accountDao.remove(id);
    });
  }
}
