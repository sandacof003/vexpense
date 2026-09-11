/// Model hasil agregasi laporan (chart) — BE-05.
///
/// Semua nominal di model ini dalam **minor unit mata uang target** (default
/// IDR), hasil konversi dari minor unit mata uang akun lewat
/// `CurrencyConverter`. Konversi bersifat **display-only**: nilai tersimpan di
/// `transactions.amount` TIDAK diubah (PRD §6 multi-currency MVP).
library;

/// Satu slice pie chart: total expense satu kategori (minor unit target).
class CategoryExpense {
  const CategoryExpense({
    required this.categoryId,
    required this.categoryName,
    required this.totalMinorUnit,
  });

  final int categoryId;
  final String categoryName;

  /// Total expense kategori ini, minor unit mata uang target (integer).
  final int totalMinorUnit;
}

/// Hasil query "Expense by Category" (pie chart).
class ExpenseByCategoryReport {
  const ExpenseByCategoryReport({
    required this.categories,
    required this.isComplete,
    required this.missingRateCurrencies,
  });

  /// Slice per kategori, terurut dari total terbesar (untuk pie/legend).
  final List<CategoryExpense> categories;

  /// True bila seluruh transaksi expense berhasil dikonversi ke target
  /// (tidak ada rate yang hilang). False = ada data yang tidak lengkap.
  final bool isComplete;

  /// Kode mata uang akun yang tidak bisa dikonversi karena rate-nya tidak ada
  /// di tabel `exchange_rates` lokal. Kosong = [isComplete] true.
  final List<String> missingRateCurrencies;
}

/// Hasil query "Income vs Expense" (bar chart) untuk satu rentang tanggal.
class IncomeVsExpenseReport {
  const IncomeVsExpenseReport({
    required this.incomeMinorUnit,
    required this.expenseMinorUnit,
    required this.isComplete,
    required this.missingRateCurrencies,
  });

  final int incomeMinorUnit;
  final int expenseMinorUnit;
  final bool isComplete;
  final List<String> missingRateCurrencies;
}
