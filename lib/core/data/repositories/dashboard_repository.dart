import '../daos/account_dao.dart';
import '../daos/transaction_dao.dart';
import '../database.dart';
import '../services/currency_converter.dart';
import 'repository_contracts.dart';

/// Ringkasan saldo gabungan semua akun dalam satu mata uang target.
class BalanceSummary {
  const BalanceSummary({
    required this.totalMinorUnit,
    required this.convertedCount,
    required this.missingRateCurrencies,
  });

  /// Total saldo (minor unit target) dari akun yang berhasil dikonversi.
  final int totalMinorUnit;

  /// Jumlah akun yang saldonya ikut dijumlah.
  final int convertedCount;

  /// Kode mata uang akun yang tidak bisa dikonversi karena rate hilang.
  final List<String> missingRateCurrencies;

  /// True bila seluruh saldo akun berhasil dikonversi (tidak ada rate hilang).
  bool get isComplete => missingRateCurrencies.isEmpty;
}

/// Query ringkasan dashboard (source-of-truth ledger).
///
/// Semua saldo dihitung dari transaksi (ledger), bukan kolom `balance` —
/// `accounts` tidak punya kolom saldo. Konversi mata uang terjadi di sini
/// (presentasi), bukan saat menyimpan transaksi.
class DashboardRepository implements DashboardData {
  DashboardRepository(
    this._accountDao,
    this._transactionDao,
    this._transactionRepository,
    this._converter,
  );

  final AccountDao _accountDao;
  final TransactionDao _transactionDao;
  final TransactionsRepository _transactionRepository;
  final CurrencyConverter _converter;

  /// Total saldo semua akun, dikonversi ke [targetCurrency].
  ///
  /// Akun yang rate-nya belum tersedia dilewati dan dicatat di
  /// [BalanceSummary.missingRateCurrencies] (bukan dikonversi pakai rate
  /// palsu).
  @override
  Future<BalanceSummary> totalBalance(String targetCurrency) async {
    final accounts = await _accountDao.getAll();
    var total = 0;
    var converted = 0;
    final missing = <String>[];

    for (final account in accounts) {
      final balance = await _transactionRepository.balanceForAccount(
        account.id,
      );
      final conversion = await _converter.convert(
        balance,
        from: account.currency,
        to: targetCurrency,
      );

      if (conversion.isSuccess) {
        total += conversion.amountMinorUnit;
        converted++;
      } else {
        missing.add(account.currency);
      }
    }

    return BalanceSummary(
      totalMinorUnit: total,
      convertedCount: converted,
      missingRateCurrencies: missing,
    );
  }

  /// [limit] transaksi terbaru (date DESC). Pakai index `idx_transactions_date`
  /// lewat ORDER BY date di [TransactionDao.getFiltered].
  @override
  Future<List<Transaction>> recentTransactions(int limit) async {
    final all = await _transactionDao.getFiltered(
      const TransactionFilter(),
      sort: TransactionSort.dateDesc,
    );
    return all.take(limit).toList();
  }
}
