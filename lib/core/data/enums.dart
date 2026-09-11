/// Enum domain untuk seluruh entitas V Expense.
///
/// Nilai enum disimpan ke database sebagai TEXT sesuai nama entry (lihat
/// [textEnum] di `tables.dart`). Nama entry JANGAN di-rename tanpa migrasi —
/// itu bagian dari schema.
library;

/// Tipe transaksi. `transfer` punya aturan khusus (lihat constraint di
/// `Transactions`): wajib `toAccountId`, tujuan != asal, `categoryId` NULL.
enum TransactionType { income, expense, transfer }

/// Tipe kategori. Kategori hanya bisa income ATAU expense.
enum CategoryType { income, expense }

/// Tipe akun.
enum AccountType { cash, bank, ewallet }
