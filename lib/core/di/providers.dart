import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/daos/account_dao.dart';
import '../data/daos/category_dao.dart';
import '../data/daos/currency_dao.dart';
import '../data/daos/exchange_rate_dao.dart';
import '../data/daos/transaction_dao.dart';
import '../data/database.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/csv_import_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/repository_contracts.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/services/currency_converter.dart';
import '../services/csv/csv_import_service.dart';
import '../../features/reports/data/report_models.dart';
import '../../features/reports/data/reports_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final accountRepositoryProvider = Provider<AccountsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AccountRepository(db, AccountDao(db), TransactionDao(db));
});

final categoryRepositoryProvider = Provider<CategoriesRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CategoryRepository(db, CategoryDao(db), TransactionDao(db));
});

final transactionRepositoryProvider = Provider<TransactionsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TransactionRepository(db, TransactionDao(db), AccountDao(db));
});

final currencyRepositoryProvider = Provider<CurrenciesRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CurrencyRepository(CurrencyDao(db));
});

final dashboardRepositoryProvider = Provider<DashboardData>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final transactionRepository = ref.watch(transactionRepositoryProvider);
  final converter = CurrencyConverter(CurrencyDao(db), ExchangeRateDao(db));
  return DashboardRepository(
    AccountDao(db),
    TransactionDao(db),
    transactionRepository,
    converter,
  );
});

/// Query agregasi laporan (chart) — BE-05. Semua nominal dikonversi ke IDR.
final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final converter = CurrencyConverter(CurrencyDao(db), ExchangeRateDao(db));
  return ReportsRepository(
    TransactionDao(db),
    AccountDao(db),
    CategoryDao(db),
    converter,
  );
});

/// Parser/service CSV murni (tanpa DB) — dipakai repository import CSV.
final csvImportServiceProvider = Provider<CsvImportService>(
  (ref) => const CsvImportService(),
);

/// Entry point import CSV: parsing + dedupe DB + insert atomik.
final csvImportRepositoryProvider = Provider<CsvImportRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CsvImportRepositoryImpl(
    db,
    ref.watch(csvImportServiceProvider),
    TransactionDao(db),
    AccountDao(db),
    CategoryDao(db),
    CurrencyDao(db),
  );
});

final transactionsProvider = StreamProvider.autoDispose<List<Transaction>>((
  ref,
) {
  return ref
      .watch(transactionRepositoryProvider)
      .watchFiltered(const TransactionFilter());
});

/// Filter aktif daftar transaksi (FE-05). Search + filter hidup berdampingan
/// di satu [TransactionFilter] — mengubahnya tidak pernah menyentuh data.
final transactionListFilterProvider = StateProvider<TransactionFilter>(
  (ref) => const TransactionFilter(),
);

/// Stream transaksi sesuai filter aktif, terbaru dulu (FE-05).
final filteredTransactionsProvider =
    StreamProvider.autoDispose<List<Transaction>>((ref) {
      final filter = ref.watch(transactionListFilterProvider);
      return ref.watch(transactionRepositoryProvider).watchFiltered(filter);
    });

final accountsProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).watchAll();
});

final categoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAll();
});

/// Akun + saldo berjalan (opening_balance + Σ income − Σ expense ± transfer).
///
/// PRD: saldo = hasil hitung ledger, bukan kolom tersimpan — jadi layar Akun
/// wajib menampilkan angka ini, bukan `openingBalance` mentah.
final accountBalancesProvider =
    FutureProvider.autoDispose<List<(Account, int)>>((ref) async {
      ref.listen(transactionsProvider, (_, _) => ref.invalidateSelf());
      ref.listen(accountsProvider, (_, _) => ref.invalidateSelf());
      final accounts = await ref.watch(accountsProvider.future);
      final transactions = ref.watch(transactionRepositoryProvider);
      // ponytail: 1 query saldo per akun (N+1) — cukup untuk belasan akun
      // rumahan; ganti ke satu query GROUP BY kalau list akun jadi panjang.
      return [
        for (final account in accounts)
          (account, await transactions.balanceForAccount(account.id)),
      ];
    });

final dashboardBalanceProvider = FutureProvider.autoDispose<BalanceSummary>((
  ref,
) {
  // Refresh saat ledger ATAU akun berubah: total saldo bergantung ke
  // keduanya (transaksi, plus opening_balance & currency tiap akun).
  // Tanpa listener akun, edit saldo awal tidak mengubah tampilan.
  ref.listen(transactionsProvider, (_, _) => ref.invalidateSelf());
  ref.listen(accountsProvider, (_, _) => ref.invalidateSelf());
  return ref.watch(dashboardRepositoryProvider).totalBalance('IDR');
});

/// Income vs expense bulan berjalan (IDR) untuk dashboard FE-03.
/// Transfer dikecualikan; rate hilang → `isComplete=false` (BE-05).
final dashboardMonthlyProvider =
    FutureProvider.autoDispose<IncomeVsExpenseReport>((ref) {
      ref.listen(transactionsProvider, (_, _) => ref.invalidateSelf());
      final now = DateTime.now();
      return ref.watch(reportsRepositoryProvider).incomeVsExpense(
        from: DateTime(now.year, now.month),
        to: DateTime(
          now.year,
          now.month + 1,
        ).subtract(const Duration(microseconds: 1)),
      );
    });

/// Rentang tanggal laporan aktif (from, to inklusif) — default bulan ini.
/// Mengubah state ini memuat ulang kedua chart reports (FE-07).
final reportsRangeProvider = StateProvider<(DateTime, DateTime)>((ref) =>
    reportsPresets().values.first.toRange());

/// Satu preset rentang tanggal laporan (FE-07). `to` = akhir hari terakhir.
class ReportPreset {
  const ReportPreset(this.label, this.from, this.to);

  final String label;
  final DateTime from;
  final DateTime to;

  (DateTime, DateTime) toRange() => (from, to);
}

/// Preset Bulan ini / 30 hari terakhir / Tahun ini. Dihitung dari tanggal
/// saat ini; rentang inklusif sampai akhir hari.
Map<String, ReportPreset> reportsPresets() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return {
    'month': ReportPreset(
      'Bulan ini',
      DateTime(now.year, now.month),
      DateTime(now.year, now.month + 1)
          .subtract(const Duration(microseconds: 1)),
    ),
    'last30': ReportPreset(
      '30 hari terakhir',
      today.subtract(const Duration(days: 29)),
      today
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1)),
    ),
    'year': ReportPreset(
      'Tahun ini',
      DateTime(now.year),
      DateTime(now.year + 1).subtract(const Duration(microseconds: 1)),
    ),
  };
}

/// Expense by Category (pie) untuk rentang aktif — FE-07.
final expenseByCategoryProvider =
    FutureProvider.autoDispose<ExpenseByCategoryReport>((ref) {
      ref.listen(transactionsProvider, (_, _) => ref.invalidateSelf());
      final (from, to) = ref.watch(reportsRangeProvider);
      return ref
          .watch(reportsRepositoryProvider)
          .expenseByCategory(from: from, to: to);
    });

/// Income vs Expense (bar) untuk rentang aktif — FE-07.
final incomeVsExpenseRangeProvider =
    FutureProvider.autoDispose<IncomeVsExpenseReport>((ref) {
      ref.listen(transactionsProvider, (_, _) => ref.invalidateSelf());
      final (from, to) = ref.watch(reportsRangeProvider);
      return ref
          .watch(reportsRepositoryProvider)
          .incomeVsExpense(from: from, to: to);
    });
