import 'package:drift/drift.dart';

import '../../../core/data/database.dart';
import '../../../core/data/enums.dart';

/// Use case: catat transaksi biasa (income / expense).
///
/// Semua write dibungkus satu DB transaction (`AppDatabase.transaction`) supaya
/// tidak ada partial write. Validasi domain dijalankan SEBELUM menulis, jadi
/// error di tahap mana pun membatalkan seluruh operasi (rollback penuh).
class CreateTransactionUseCase {
  CreateTransactionUseCase(this._db);

  final AppDatabase _db;

  Future<Transaction> call({
    required TransactionType type,
    required int amount,
    required int accountId,
    required int categoryId,
    required DateTime date,
    String? description,
  }) async {
    if (type == TransactionType.transfer) {
      throw ArgumentError('Transfer memakai CreateTransferUseCase, bukan ini');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'harus > 0');
    }
    // income/expense wajib kategori (selaras CHECK constraint di tabel).
    return _db.transaction(() async {
      final id = await _db.transactionDao.insert(
        TransactionsCompanion.insert(
          type: type,
          amount: amount,
          accountId: accountId,
          categoryId: Value(categoryId),
          date: date,
          description: Value(description),
        ),
      );
      return (await _db.transactionDao.getById(id))!;
    });
  }
}

/// Use case: edit transaksi biasa (income / expense).
///
/// Edit = reversal efek lama + apply nilai baru dalam SATU DB transaction.
/// Karena saldo dihitung dari ledger (tabel `transactions`, tanpa kolom
/// balance), "reversal + apply" secara praktis = mengganti baris secara atomik:
/// efek baris lama hilang dan efek baris baru berlaku sekaligus, sehingga saldo
/// akhir selalu sama dengan ledger dari data baru. Bila replace gagal (misal
/// FK melanggar), transaction di-rollback dan baris lama tetap utuh.
class EditTransactionUseCase {
  EditTransactionUseCase(this._db);

  final AppDatabase _db;

  Future<Transaction> call(Transaction updated) async {
    return _db.transaction(() async {
      final existing = await _db.transactionDao.getById(updated.id);
      if (existing == null) {
        throw StateError('Transaksi #${updated.id} tidak ditemukan');
      }
      _validate(updated);
      await _db.transactionDao.replace(
        updated.copyWith(updatedAt: DateTime.now()),
      );
      return (await _db.transactionDao.getById(updated.id))!;
    });
  }

  void _validate(Transaction tx) {
    if (tx.type == TransactionType.transfer) {
      throw ArgumentError('Transfer tidak diedit lewat use case ini (MVP)');
    }
    if (tx.amount <= 0) {
      throw ArgumentError.value(tx.amount, 'amount', 'harus > 0');
    }
    if (tx.categoryId == null) {
      throw ArgumentError('Income/expense wajib punya kategori');
    }
  }
}

/// Use case: hapus transaksi biasa. Rollback penuh bila error. Idempotent
/// (id tidak ada = no-op). Transfer wajib dihapus lewat [DeleteTransferUseCase].
class DeleteTransactionUseCase {
  DeleteTransactionUseCase(this._db);

  final AppDatabase _db;

  Future<void> call(int id) {
    return _db.transaction(() async {
      final tx = await _db.transactionDao.getById(id);
      if (tx == null) return;
      if (tx.type == TransactionType.transfer) {
        throw ArgumentError('Gunakan DeleteTransferUseCase untuk transfer');
      }
      await _db.transactionDao.remove(id);
    });
  }
}
