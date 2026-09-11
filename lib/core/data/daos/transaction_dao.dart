import 'package:drift/drift.dart';

import '../database.dart';
import '../enums.dart';
import '../tables.dart';

part 'transaction_dao.g.dart';

/// Parameter filter + sorting untuk query transaksi.
class TransactionFilter {
  final TransactionType? type;
  final int? accountId;
  final int? categoryId;
  final DateTime? fromDate; // inklusif
  final DateTime? toDate; // inklusif
  final String? search; // cocok di description (case-insensitive)

  const TransactionFilter({
    this.type,
    this.accountId,
    this.categoryId,
    this.fromDate,
    this.toDate,
    this.search,
  });
}

/// Urutan sorting transaksi.
enum TransactionSort { dateDesc, dateAsc, amountDesc, amountAsc }

/// Akses baca/tulis tabel `transactions`, plus query agregasi.
@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  SimpleSelectStatement<$TransactionsTable, Transaction> _filtered(
    TransactionFilter filter,
  ) {
    final q = select(transactions);
    if (filter.type != null) {
      q.where((t) => t.type.equalsValue(filter.type!));
    }
    if (filter.accountId != null) {
      q.where((t) => t.accountId.equals(filter.accountId!));
    }
    if (filter.categoryId != null) {
      q.where((t) => t.categoryId.equals(filter.categoryId!));
    }
    if (filter.fromDate != null) {
      q.where((t) => t.date.isBiggerOrEqualValue(filter.fromDate!));
    }
    if (filter.toDate != null) {
      q.where((t) => t.date.isSmallerOrEqualValue(filter.toDate!));
    }
    if (filter.search != null && filter.search!.isNotEmpty) {
      q.where(
        (t) => t.description.lower().contains(filter.search!.toLowerCase()),
      );
    }
    return q;
  }

  /// Ambil transaksi dengan filter + sorting.
  Future<List<Transaction>> getFiltered(
    TransactionFilter filter, {
    TransactionSort sort = TransactionSort.dateDesc,
  }) {
    final q = _filtered(filter);
    q.orderBy([(t) => _sortTerm(sort, t)]);
    return q.get();
  }

  Stream<List<Transaction>> watchFiltered(
    TransactionFilter filter, {
    TransactionSort sort = TransactionSort.dateDesc,
  }) {
    final q = _filtered(filter);
    q.orderBy([(t) => _sortTerm(sort, t)]);
    return q.watch();
  }

  OrderingTerm _sortTerm(TransactionSort sort, $TransactionsTable t) {
    switch (sort) {
      case TransactionSort.dateDesc:
        return OrderingTerm.desc(t.date);
      case TransactionSort.dateAsc:
        return OrderingTerm.asc(t.date);
      case TransactionSort.amountDesc:
        return OrderingTerm.desc(t.amount);
      case TransactionSort.amountAsc:
        return OrderingTerm.asc(t.amount);
    }
  }

  Future<Transaction?> getById(int id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Semua transaksi milik satu akun (untuk kalkulasi saldo).
  Future<List<Transaction>> getByAccount(int accountId) =>
      (select(transactions)..where((t) => t.accountId.equals(accountId))).get();

  /// Semua transfer MASUK ke satu akun (akun ini sebagai tujuan).
  Future<List<Transaction>> getIncomingTransfers(int accountId) => (select(
    transactions,
  )..where((t) => t.toAccountId.equals(accountId))).get();

  /// Jumlah transaksi yang memakai akun ini.
  Future<int> countByAccount(int accountId) =>
      (selectOnly(transactions)
            ..addColumns([countAll()])
            ..where(transactions.accountId.equals(accountId)))
          .map((r) => r.read(countAll())!)
          .getSingle();

  /// Jumlah transaksi yang memakai kategori ini.
  Future<int> countByCategory(int categoryId) =>
      (selectOnly(transactions)
            ..addColumns([countAll()])
            ..where(transactions.categoryId.equals(categoryId)))
          .map((r) => r.read(countAll())!)
          .getSingle();

  /// Pindahkan semua transaksi dari [fromCategoryId] ke [toCategoryId].
  Future<int> reassignCategory(int fromCategoryId, int toCategoryId) =>
      (update(transactions)..where((t) => t.categoryId.equals(fromCategoryId)))
          .write(TransactionsCompanion(categoryId: Value(toCategoryId)));

  Future<int> insert(TransactionsCompanion tx) => into(transactions).insert(tx);

  Future<bool> replace(Transaction tx) => update(transactions).replace(tx);

  Future<int> remove(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  /// Jumlah transaksi (untuk test + summary).
  Future<int> count() => (selectOnly(
    transactions,
  )..addColumns([countAll()])).map((r) => r.read(countAll())!).getSingle();

  // --- Agregasi untuk chart / ringkasan dashboard ---

  /// Total income pada rentang tanggal (dalam minor unit). Null = tidak ada.
  Future<int?> totalIncome({DateTime? from, DateTime? to}) {
    final amount = transactions.amount.sum();
    final q = selectOnly(transactions)
      ..addColumns([amount])
      ..where(transactions.type.equalsValue(TransactionType.income));
    if (from != null) q.where(transactions.date.isBiggerOrEqualValue(from));
    if (to != null) q.where(transactions.date.isSmallerOrEqualValue(to));
    return q.map((r) => r.read(amount)).getSingle();
  }

  /// Total expense pada rentang tanggal (dalam minor unit). Null = tidak ada.
  Future<int?> totalExpense({DateTime? from, DateTime? to}) {
    final amount = transactions.amount.sum();
    final q = selectOnly(transactions)
      ..addColumns([amount])
      ..where(transactions.type.equalsValue(TransactionType.expense));
    if (from != null) q.where(transactions.date.isBiggerOrEqualValue(from));
    if (to != null) q.where(transactions.date.isSmallerOrEqualValue(to));
    return q.map((r) => r.read(amount)).getSingle();
  }

  /// Expense per kategori (untuk pie chart). Return list (categoryId, total).
  Future<List<(int, int)>> expenseByCategory({DateTime? from, DateTime? to}) {
    final sum = transactions.amount.sum();
    final q = selectOnly(transactions)
      ..addColumns([transactions.categoryId, sum])
      ..where(transactions.type.equalsValue(TransactionType.expense))
      ..where(transactions.categoryId.isNotNull());
    if (from != null) q.where(transactions.date.isBiggerOrEqualValue(from));
    if (to != null) q.where(transactions.date.isSmallerOrEqualValue(to));
    q.groupBy([transactions.categoryId]);
    return q.map((r) => (r.read(transactions.categoryId)!, r.read(sum)!)).get();
  }
}
