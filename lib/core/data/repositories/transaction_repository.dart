import 'package:drift/drift.dart';

import '../database.dart';
import '../enums.dart';
import '../daos/account_dao.dart';
import '../daos/transaction_dao.dart';
import 'repository_contracts.dart';

/// Repository transaksi: CRUD + ledger + transfer atomik.
///
/// Ledger (source of truth saldo, PRD §6):
///   saldo = opening_balance + income − expense − transfer_keluar + transfer_masuk
/// Tidak ada kolom `balance`; selalu dihitung dari transaksi.
class TransactionRepository implements TransactionsRepository {
  TransactionRepository(this._db, this._transactionDao, this._accountDao);

  final AppDatabase _db;
  final TransactionDao _transactionDao;
  final AccountDao _accountDao;

  @override
  Future<List<Transaction>> getFiltered(
    TransactionFilter filter, {
    TransactionSort sort = TransactionSort.dateDesc,
  }) => _transactionDao.getFiltered(filter, sort: sort);

  @override
  Stream<List<Transaction>> watchFiltered(
    TransactionFilter filter, {
    TransactionSort sort = TransactionSort.dateDesc,
  }) => _transactionDao.watchFiltered(filter, sort: sort);

  @override
  Future<Transaction?> getById(int id) => _transactionDao.getById(id);

  /// Tambah transaksi income/expense. Validasi + insert dalam 1 transaksi DB.
  @override
  Future<Transaction> add({
    required TransactionType type,
    required int amount,
    required int accountId,
    required int categoryId,
    required DateTime date,
    String? description,
  }) async {
    if (type == TransactionType.transfer) {
      throw ArgumentError('Gunakan transfer() untuk transaksi transfer');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'harus > 0');
    }
    final id = await _transactionDao.insert(
      TransactionsCompanion.insert(
        type: type,
        amount: amount,
        accountId: accountId,
        categoryId: Value(categoryId),
        date: date,
        description: Value(description),
      ),
    );
    return (await _transactionDao.getById(id))!;
  }

  /// Transfer antar akun same-currency. Satu baris (debit asal + kredit tujuan),
  /// efek ledger dihitung dua arah. Validasi asal != tujuan + amount > 0.
  @override
  Future<Transaction> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amount,
    required DateTime date,
    String? description,
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Akun asal dan tujuan tidak boleh sama');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'harus > 0');
    }
    // Same-currency MVP: pastikan kedua akun pakai currency yang sama.
    final from = await _accountDao.getById(fromAccountId);
    final to = await _accountDao.getById(toAccountId);
    if (from == null || to == null) {
      throw ArgumentError('Akun asal/tujuan tidak ditemukan');
    }
    if (from.currency != to.currency) {
      throw ArgumentError('Transfer beda currency belum didukung di MVP');
    }

    final id = await _transactionDao.insert(
      TransactionsCompanion.insert(
        type: TransactionType.transfer,
        amount: amount,
        accountId: fromAccountId,
        toAccountId: Value(toAccountId),
        categoryId: const Value.absent(),
        date: date,
        description: Value(description),
      ),
    );
    return (await _transactionDao.getById(id))!;
  }

  /// Edit transaksi = hapus efek lama + apply nilai baru, atomik.
  /// Cukup replace baris (ledger dihitung ulang dari data final).
  Future<void> update(Transaction tx) async {
    await _db.transaction(() async {
      await _transactionDao.replace(tx.copyWith(updatedAt: DateTime.now()));
    });
  }

  /// Hapus transaksi. Transfer dihapus sebagai satu baris (kedua sisi hilang).
  @override
  Future<void> delete(int id) async {
    await _db.transaction(() async {
      await _transactionDao.remove(id);
    });
  }

  // --- Ledger & agregasi ---

  /// Saldo satu akun dalam minor unit currency akun.
  @override
  Future<int> balanceForAccount(int accountId) async {
    final account = await _accountDao.getById(accountId);
    if (account == null) throw ArgumentError('Akun tidak ditemukan');
    return _balance(
      account,
      await _transactionDao.getByAccount(accountId),
      await _transactionDao.getIncomingTransfers(accountId),
    );
  }

  int _balance(
    Account account,
    List<Transaction> outgoing,
    List<Transaction> incoming,
  ) {
    var balance = account.openingBalance;
    for (final t in outgoing) {
      switch (t.type) {
        case TransactionType.income:
          balance += t.amount;
        case TransactionType.expense:
          balance -= t.amount;
        case TransactionType.transfer:
          balance -= t.amount; // keluar dari akun asal
      }
    }
    for (final t in incoming) {
      balance += t.amount; // masuk ke akun tujuan
    }
    return balance;
  }

  /// Total income dalam rentang tanggal (minor unit). 0 bila tidak ada.
  @override
  Future<int> totalIncome({DateTime? from, DateTime? to}) =>
      _transactionDao.totalIncome(from: from, to: to).then((v) => v ?? 0);

  /// Total expense dalam rentang tanggal (minor unit). 0 bila tidak ada.
  @override
  Future<int> totalExpense({DateTime? from, DateTime? to}) =>
      _transactionDao.totalExpense(from: from, to: to).then((v) => v ?? 0);

  /// Expense per kategori → (categoryId, total), untuk pie chart.
  Future<List<(int, int)>> expenseByCategory({DateTime? from, DateTime? to}) =>
      _transactionDao.expenseByCategory(from: from, to: to);
}
