import '../../services/csv/csv_import_models.dart';
import '../database.dart';
import '../enums.dart';
import '../daos/transaction_dao.dart';
import 'dashboard_repository.dart';

abstract interface class AccountsRepository {
  Future<List<Account>> getAll();
  Stream<List<Account>> watchAll();
  Future<Account?> getById(int id);
  Future<Account> create({
    required String name,
    required AccountType type,
    String currency,
    int openingBalance,
  });
  Future<void> update(Account account, {required String newName});
  Future<void> delete(int id);
}

abstract interface class CategoriesRepository {
  Future<List<Category>> getAll();
  Stream<List<Category>> watchAll();
  Future<List<Category>> getByType(CategoryType type);
  Future<Category?> getById(int id);
  Future<Category> create({
    required String name,
    required CategoryType type,
    String? color,
    String? icon,
  });
  Future<void> update(
    Category category, {
    required String newName,
    String? color,
    String? icon,
  });
  Future<void> delete(int id);
}

abstract interface class TransactionsRepository {
  Future<List<Transaction>> getFiltered(
    TransactionFilter filter, {
    TransactionSort sort,
  });
  Stream<List<Transaction>> watchFiltered(
    TransactionFilter filter, {
    TransactionSort sort,
  });
  Future<Transaction?> getById(int id);
  Future<Transaction> add({
    required TransactionType type,
    required int amount,
    required int accountId,
    required int categoryId,
    required DateTime date,
    String? description,
  });
  Future<Transaction> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amount,
    required DateTime date,
    String? description,
  });
  Future<void> delete(int id);
  Future<int> balanceForAccount(int accountId);
  Future<int> totalIncome({DateTime? from, DateTime? to});
  Future<int> totalExpense({DateTime? from, DateTime? to});
}

abstract interface class DashboardData {
  Future<BalanceSummary> totalBalance(String targetCurrency);
  Future<List<Transaction>> recentTransactions(int limit);
}

/// Entry point import CSV end-to-end (PRD §7).
///
/// Dedupe selalu dihitung dari DB di dalam transaksi import, bukan dari data
/// yang disuplai caller — import ulang file yang sama tidak boleh menggandakan
/// transaksi, walau caller tidak mengirim daftar hash apa pun.
abstract interface class CsvImportRepository {
  /// Parse + validasi + dedupe DB + rencana mapping akun/kategori.
  /// Read-only: tidak ada tulisan ke database.
  Future<CsvImportPreview> preview({
    required List<int> bytes,
    String? fileName,
  });

  /// Import atomik: mapping akun/kategori, dedupe dari DB, dan seluruh insert
  /// dijalankan dalam SATU `AppDatabase.transaction`. Gagal di tengah batch
  /// melempar exception dan rollback penuh (tidak ada transaksi separuh masuk).
  Future<CsvImportReport> importBytes({
    required List<int> bytes,
    String? fileName,
  });
}
