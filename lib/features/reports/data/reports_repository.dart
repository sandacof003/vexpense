import '../../../core/data/daos/account_dao.dart';
import '../../../core/data/daos/category_dao.dart';
import '../../../core/data/daos/transaction_dao.dart';
import '../../../core/data/database.dart';
import '../../../core/data/enums.dart';
import '../../../core/data/services/currency_converter.dart';
import 'report_models.dart';

/// Query agregasi laporan (chart) — BE-05.
///
/// Semua agregasi memakai **minor unit** dari `transactions.amount` (integer),
/// kemudian dikonversi ke mata uang target (default IDR) lewat
/// [CurrencyConverter]. Konversi terjadi di sini (presentasi), TIDAK mengubah
/// nilai tersimpan.
///
/// Aturan:
/// - Transfer TIDAK masuk chart (bukan income/expense; pergerakan internal).
/// - Rate hanya dari tabel `exchange_rates` lokal — tidak ada API real-time.
/// - Rate hilang → transaksi akun bersangkutan dilewati dan dicatat di
///   `missingRateCurrencies`; `isComplete` jadi false (data tidak lengkap),
///   BUKAN diisi rate palsu.
class ReportsRepository {
  ReportsRepository(
    this._transactionDao,
    this._accountDao,
    this._categoryDao,
    this._converter,
  );

  final TransactionDao _transactionDao;
  final AccountDao _accountDao;
  final CategoryDao _categoryDao;
  final CurrencyConverter _converter;

  /// Expense per kategori (pie chart) dalam rentang [from]..[to] (inklusif),
  /// dikonversi ke [targetCurrency]. Transfer dikecualikan.
  Future<ExpenseByCategoryReport> expenseByCategory({
    DateTime? from,
    DateTime? to,
    String targetCurrency = 'IDR',
  }) async {
    final transactions = await _transactionDao.getFiltered(
      TransactionFilter(
        type: TransactionType.expense,
        fromDate: from,
        toDate: to,
      ),
      sort: TransactionSort.dateAsc,
    );

    // Kumpulkan currency semua akun yang muncul, sekali query (bukan N+1).
    final accountIds = {for (final t in transactions) t.accountId};
    final accountsById = <int, Account>{};
    for (final account in await _accountDao.getAll()) {
      if (accountIds.contains(account.id)) {
        accountsById[account.id] = account;
      }
    }

    final categoryIds = {for (final t in transactions) t.categoryId};
    final categoriesById = <int, Category>{};
    for (final category in await _categoryDao.getAll()) {
      if (categoryIds.contains(category.id)) {
        categoriesById[category.id] = category;
      }
    }

    final totals = <int, int>{}; // categoryId -> total minor unit target
    final missing = <String>{};

    for (final t in transactions) {
      final account = accountsById[t.accountId];
      if (account == null) continue; // akun terhapus; expense ikut RESTRICT

      final conversion = await _converter.convert(
        t.amount,
        from: account.currency,
        to: targetCurrency,
      );
      if (conversion.isSuccess) {
        final catId = t.categoryId;
        if (catId != null) {
          totals[catId] = (totals[catId] ?? 0) + conversion.amountMinorUnit;
        }
      } else {
        missing.add(account.currency);
      }
    }

    final categories = [
      for (final entry in totals.entries)
        CategoryExpense(
          categoryId: entry.key,
          categoryName: categoriesById[entry.key]?.name ?? 'Tanpa kategori',
          totalMinorUnit: entry.value,
        ),
    ]..sort((a, b) => b.totalMinorUnit.compareTo(a.totalMinorUnit));

    return ExpenseByCategoryReport(
      categories: categories,
      isComplete: missing.isEmpty,
      missingRateCurrencies: (missing.toList()..sort()),
    );
  }

  /// Income vs expense (bar chart) dalam rentang [from]..[to] (inklusif),
  /// dikonversi ke [targetCurrency]. Transfer dikecualikan.
  Future<IncomeVsExpenseReport> incomeVsExpense({
    DateTime? from,
    DateTime? to,
    String targetCurrency = 'IDR',
  }) async {
    final transactions = await _transactionDao.getFiltered(
      TransactionFilter(fromDate: from, toDate: to),
      sort: TransactionSort.dateAsc,
    );

    final accountIds = {for (final t in transactions) t.accountId};
    final accountsById = <int, Account>{};
    for (final account in await _accountDao.getAll()) {
      if (accountIds.contains(account.id)) {
        accountsById[account.id] = account;
      }
    }

    var income = 0;
    var expense = 0;
    final missing = <String>{};

    for (final t in transactions) {
      final account = accountsById[t.accountId];
      if (account == null) continue;

      final conversion = await _converter.convert(
        t.amount,
        from: account.currency,
        to: targetCurrency,
      );
      if (!conversion.isSuccess) {
        missing.add(account.currency);
        continue;
      }

      switch (t.type) {
        case TransactionType.income:
          income += conversion.amountMinorUnit;
        case TransactionType.expense:
          expense += conversion.amountMinorUnit;
        case TransactionType.transfer:
          // Transfer dikecualikan dari chart.
          break;
      }
    }

    return IncomeVsExpenseReport(
      incomeMinorUnit: income,
      expenseMinorUnit: expense,
      isComplete: missing.isEmpty,
      missingRateCurrencies: (missing.toList()..sort()),
    );
  }
}
