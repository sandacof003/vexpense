import '../formatters/app_locale.dart';
import '../formatters/currency_format.dart';
import '../formatters/money_formatter.dart';

/// Hasil validasi form: `null` = valid, selain itu pesan error untuk UI.
typedef ValidatorFn = String? Function();

/// Validasi form transaksi V Expense.
///
/// Pesan error berbahasa Indonesia (UI default). Semua nilai nominal adalah
/// integer minor unit — validator menolak nol dan negatif (PRD: amount > 0).
class TransactionFormValidators {
  const TransactionFormValidators({
    this.locale = AppLocale.id,
  });

  final AppLocale locale;

  MoneyFormatter get _money => MoneyFormatter(locale: locale);

  /// Validasi nominal: wajib diisi, angka valid, dan > 0.
  ///
  /// Mengembalikan minor unit yang sudah diparse, atau pesan error
  /// di sisi kiri record.
  ({int? minorUnit, String? error}) validateAmount(
    String input,
    CurrencyFormat currency,
  ) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return (minorUnit: null, error: 'Nominal wajib diisi');
    }
    final int minor;
    try {
      minor = _money.parseMinor(trimmed, currency);
    } on FormatException catch (e) {
      return (minorUnit: null, error: e.message);
    }
    if (minor <= 0) {
      return (minorUnit: null, error: 'Nominal harus lebih dari 0');
    }
    return (minorUnit: minor, error: null);
  }

  /// Income/expense wajib memilih kategori. `categoryId == null` → error.
  String? validateCategoryRequired(int? categoryId) =>
      categoryId == null ? 'Kategori wajib dipilih' : null;

  /// Transfer: akun asal dan tujuan wajib berbeda.
  String? validateTransferAccounts(int? fromAccountId, int? toAccountId) {
    if (fromAccountId == null) return 'Akun asal wajib dipilih';
    if (toAccountId == null) return 'Akun tujuan wajib dipilih';
    if (fromAccountId == toAccountId) {
      return 'Akun asal dan tujuan tidak boleh sama';
    }
    return null;
  }

  /// Nama wajib diisi (dipakai form akun/kategori).
  String? validateNameRequired(String? name, {String label = 'Nama'}) {
    if (name == null || name.trim().isEmpty) return '$label wajib diisi';
    return null;
  }
}
