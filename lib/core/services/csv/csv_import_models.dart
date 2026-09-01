/// Domain model untuk hasil import CSV.
///
/// Berdiri sendiri (tidak import flutter/widget/drift) supaya service di
/// `lib/core/services/` bebas di-unit-test tanpa dependency UI atau DB,
/// dan hasil/error bisa langsung dirender oleh lapisan UI.
library;

/// Kode error hasil import CSV.
///
/// Nama-nama ini bagian dari kontrak UI — jangan diganti tanpa sinkron ke
/// layar import. Nilai [name] dipakai juga sebagai kunci lokaliasi.
enum CsvImportErrorCode {
  /// File bukan CSV (ekstensi tidak `.csv`).
  notCsv,

  /// Encoding bukan UTF-8 / Windows-1252.
  badEncoding,

  /// File kosong (0 byte) atau tanpa satu baris pun yang valid.
  emptyFile,

  /// Header tidak cocok dengan kontrak Expense IQ
  /// (`Date, Type, Category, Account, Amount, Currency, Note`).
  missingHeaders,

  /// Kolom wajib tidak boleh kosong pada baris tertentu.
  requiredValueMissing,

  /// Nilai tanggal tidak bisa diparse dengan format yang didukung.
  invalidDate,

  /// Nilai nominal tidak bisa diparse (format angka tidak dikenal).
  invalidAmount,

  /// Nominal bernilai nol (harus > 0).
  zeroAmount,

  /// Tipe transaksi tidak dikenal (bukan income/expense/transfer).
  invalidType,

  /// Mata uang tidak dikenal di tabel currencies.
  unknownCurrency,

  /// Baris terdeteksi duplikat terhadap transaksi yang sudah ada.
  duplicate,
}

/// Satu kesalahan pada satu baris CSV, siap ditampilkan UI.
///
/// [rowNumber] adalah posisi baris 1-based di file sumber (1 = baris data
/// pertama setelah header), bukan index internal. [rowNumber] null hanya
/// untuk error tingkat-file (encoding/header/file kosong).
class CsvRowError {
  const CsvRowError({
    required this.code,
    this.rowNumber,
    this.column,
    this.message,
  });

  final CsvImportErrorCode code;

  /// 1-based, null untuk error tingkat-file.
  final int? rowNumber;

  /// Nama kolom terkait (mis. `Amount`), null bila tidak spesifik kolom.
  final String? column;

  /// Pesan siap-tampil. Bila null, UI wajib menyediakan teks dari [code].
  final String? message;

  @override
  String toString() {
    final loc = rowNumber == null ? 'file' : 'baris $rowNumber';
    final col = column == null ? '' : ' (kolom $column)';
    final msg = message ?? code.name;
    return '$loc$col: $msg';
  }
}

/// Hasil import CSV — dibentuk oleh [CsvImportService], dirender oleh UI.
///
/// Tidak ada coupling ke widget. UI memutuskan sendiri cara menampilkan
/// [rows] (valid), [errors] (invalid/gagal), dan [summary].
class CsvImportResult {
  const CsvImportResult({
    required this.rows,
    required this.errors,
    required this.summary,
  });

  /// Baris yang berhasil diparse (valid). Belum tentu committed.
  final List<CsvParsedRow> rows;

  /// Semua error yang ditemukan (parse + dedupe), urut sesuai baris sumber.
  final List<CsvRowError> errors;

  final CsvImportSummary summary;

  /// True bila tidak ada satu baris valid pun.
  bool get isEmpty => rows.isEmpty;

  /// True bila tidak ada error sama sekali.
  bool get isClean => errors.isEmpty;
}

/// Ringkasan angka untuk ditampilkan di akhir import.
class CsvImportSummary {
  const CsvImportSummary({
    required this.totalRows,
    required this.validRows,
    required this.duplicateRows,
    required this.invalidRows,
    required this.distinctAccounts,
    required this.distinctCategories,
  });

  /// Total baris data di file (di luar header).
  final int totalRows;

  /// Baris valid dan tidak duplikat (siap di-import).
  final int validRows;

  /// Baris valid tapi duplikat (di-skip).
  final int duplicateRows;

  /// Baris yang gagal parse (error).
  final int invalidRows;

  final int distinctAccounts;
  final int distinctCategories;

  /// Teks summary siap-tampil: "Berhasil import X transaksi, Y akun, Z
  /// kategori. Gagal/skip: N baris".
  String get message {
    final fail = duplicateRows + invalidRows;
    return 'Berhasil import $validRows transaksi, $distinctAccounts akun, '
        '$distinctCategories kategori. Gagal/skip: $fail baris';
  }
}

/// Satu baris CSV yang sudah diparse dan dinyatakan valid.
///
/// Semua nilai sudah dinormalisasi: amount dalam minor unit (integer),
/// tanggal sebagai [DateTime] (date-only). Pemetaan akun/kategori ke entitas
/// DB dilakukan service import, bukan parser — parser cukup mengembalikan
/// nama mentah [accountName]/[categoryName] untuk dipetakan.
class CsvParsedRow {
  const CsvParsedRow({
    required this.rowNumber,
    required this.date,
    required this.type,
    required this.categoryName,
    required this.accountName,
    required this.amountMinorUnit,
    required this.currencyCode,
    this.note,
  });

  final int rowNumber;
  final DateTime date;

  /// 'income' | 'expense' | 'transfer' (sudah dinormalisasi lowercase).
  final String type;

  final String categoryName;
  final String accountName;
  final int amountMinorUnit;
  final String currencyCode;
  final String? note;

  /// Hash dedupe sesuai PRD §7: date + amount + account + category + note.
  ///
  /// Dipakai service import untuk deteksi duplikat (import ulang tidak
  /// menggandakan). Hash dibangun dari representasi kanonik field, bukan
  /// string mentah, supaya `1.500.000` == `1500000` dianggap sama.
  String computeDedupeHash() {
    final dateKey = '${date.year}-${date.month}-${date.day}';
    final normalizedNote = (note ?? '').trim();
    return [
      dateKey,
      type,
      amountMinorUnit,
      currencyCode,
      accountName.trim(),
      categoryName.trim(),
      normalizedNote,
    ].join('|');
  }
}
