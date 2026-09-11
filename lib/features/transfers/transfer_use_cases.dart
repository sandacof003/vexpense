import 'package:drift/drift.dart';

import '../../core/data/database.dart';
import '../../core/data/enums.dart';

/// Use case: transfer antar akun SAME-CURRENCY (batas MVP).
///
/// Representasi konsisten dengan schema: satu baris `transactions` bertipe
/// `transfer` dengan `account_id` = akun asal (debit) dan `to_account_id` =
/// akun tujuan (kredit). Efek ledger dihitung dua arah dari baris tunggal ini.
/// `category_id` NULL (constraint transfer). Seluruh operasi dalam satu DB
/// transaction.
class CreateTransferUseCase {
  CreateTransferUseCase(this._db);

  final AppDatabase _db;

  Future<Transaction> call({
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
    return _db.transaction(() async {
      final from = await _db.accountDao.getById(fromAccountId);
      final to = await _db.accountDao.getById(toAccountId);
      if (from == null || to == null) {
        throw ArgumentError('Akun asal/tujuan tidak ditemukan');
      }
      if (from.currency != to.currency) {
        throw ArgumentError('Transfer beda currency belum didukung di MVP');
      }
      final id = await _db.transactionDao.insert(
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
      return (await _db.transactionDao.getById(id))!;
    });
  }
}

/// Use case: hapus transfer secara atomik.
///
/// Transfer = satu baris yang merepresentasikan kedua sisi, jadi menghapus baris
/// berarti kedua sisi hilang sekaligus tanpa orphan. Bukan transfer → ditolak.
class DeleteTransferUseCase {
  DeleteTransferUseCase(this._db);

  final AppDatabase _db;

  Future<void> call(int id) {
    return _db.transaction(() async {
      final tx = await _db.transactionDao.getById(id);
      if (tx == null) return;
      if (tx.type != TransactionType.transfer) {
        throw ArgumentError('Transaksi #$id bukan transfer');
      }
      await _db.transactionDao.remove(id);
    });
  }
}
