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

  /// Tanda nominal tidak sesuai tipe transaksi (mis. `income` negatif).
  /// Arah transaksi ditentukan kolom `Type`; nominal selalu magnitudo positif.
  invalidSign,

  /// Tipe transaksi tidak dikenal (bukan income/expense/transfer).
  invalidType,

  /// Mata uang tidak dikenal di tabel currencies.
  unknownCurrency,

  /// Baris terdeteksi duplikat terhadap transaksi yang sudah ada.
  duplicate,

  /// Transfer belum bisa dipetakan: kontrak CSV MVP hanya punya satu kolom
  /// `Account`, sedangkan transfer butuh akun tujuan.
  unsupportedTransfer,

  /// Akun dengan nama itu sudah ada di DB dengan currency berbeda — nominal
  /// baris tidak bisa dihormati (transaksi mewarisi currency akun).
  accountCurrencyMismatch,

  /// Kategori dengan nama itu sudah ada dengan tipe berbeda (income vs expense)
  /// dan `categories.name` unik — butuh mapping manual.
  categoryTypeMismatch,
}

/// Hash dedupe PRD §7 (date + amount + account + category + note).
///
/// **Satu-satunya** implementasi hash. Dipakai dua arah supaya tidak bisa
/// menyimpang: jalur CSV ([CsvParsedRow.computeDedupeHash]) dan jalur baca
/// transaksi existing dari DB (repository import). Dibangun dari representasi
/// kanonik field, bukan string mentah, supaya `1.500.000` == `1500000`.
///
/// Catatan tanggal: komponen `y-m-d` dipakai apa adanya. Baris CSV disimpan
/// sebagai date-only UTC ([CsvDateParser]), jadi jalur DB wajib mengirim
/// `DateTime` hasil `.toUtc()` supaya hash dua arah tetap sama di semua timezone.
/// Catatan nama: `accountName`/`categoryName` dinormalisasi `toLowerCase()`
/// (setelah trim) di dalam fungsi ini. Mapping akun/kategori di repository
/// memakai kunci lowercase, jadi hash dua arah harus ikut case-insensitive —
/// tanpa ini DB berisi akun `Cash` sementara CSV menulis `cash`, hash-nya beda,
/// dan file yang sama bisa masuk dua kali.
String csvDedupeHash({
  required DateTime date,
  required String type,
  required int amountMinorUnit,
  required String currencyCode,
  required String accountName,
  required String categoryName,
  String? note,
}) {
  final dateKey = '${date.year}-${date.month}-${date.day}';
  final normalizedNote = (note ?? '').trim();
  return [
    dateKey,
    type,
    amountMinorUnit,
    currencyCode,
    accountName.trim().toLowerCase(),
    categoryName.trim().toLowerCase(),
    normalizedNote,
  ].join('|');
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
  /// Delegasi ke [csvDedupeHash] — implementasi tunggal, sama dengan yang
  /// dipakai repository import saat menghitung hash transaksi existing dari DB.
  String computeDedupeHash() => csvDedupeHash(
    date: date,
    type: type,
    amountMinorUnit: amountMinorUnit,
    currencyCode: currencyCode,
    accountName: accountName,
    categoryName: categoryName,
    note: note,
  );
}

/// Hasil preview import: parser + validasi + dedupe DB + rencana mapping akun
/// dan kategori (PRD §7 langkah 1-4). Belum ada tulisan ke DB.
class CsvImportPreview {
  const CsvImportPreview({
    required this.result,
    required this.accountsToCreate,
    required this.categoriesToCreate,
  });

  /// Baris valid siap-import, error per baris, dan summary dari service.
  final CsvImportResult result;

  /// Nama akun di CSV yang belum ada di DB — akan dibuat saat import.
  final List<String> accountsToCreate;

  /// Nama kategori di CSV yang belum ada di DB — akan dibuat saat import.
  final List<String> categoriesToCreate;

  List<CsvParsedRow> get rows => result.rows;
  List<CsvRowError> get errors => result.errors;
  CsvImportSummary get summary => result.summary;

  /// Tidak ada baris yang bisa di-import.
  bool get isEmpty => rows.isEmpty;

  /// Tidak ada satu pun error (file maupun baris).
  bool get isClean => errors.isEmpty;

  /// Error level file (mis. header hilang) — kalau ada, tidak ada baris masuk.
  List<CsvRowError> get fileErrors =>
      errors.where((e) => e.rowNumber == null).toList();
}

/// Hasil commit import ke database (PRD §7 langkah 5).
///
/// Seluruh batch ditulis dalam satu transaksi: `insertedRows` adalah jumlah yang
/// benar-benar masuk, atau semuanya 0 kalau transaksinya rollback (import
/// melempar exception, tidak ada transaksi separuh masuk).
class CsvImportReport {
  const CsvImportReport({
    required this.insertedRows,
    required this.createdAccounts,
    required this.createdCategories,
    required this.errors,
  });

  /// Jumlah transaksi yang benar-benar di-insert.
  final int insertedRows;

  /// Akun baru yang dibuat otomatis dari nama di CSV.
  final int createdAccounts;

  /// Kategori baru yang dibuat otomatis dari nama di CSV.
  final int createdCategories;

  /// Semua alasan baris tidak masuk (duplikat / invalid / tidak bisa dipetakan).
  final List<CsvRowError> errors;

  /// Baris di-skip karena duplikat (sudah ada di DB atau di batch ini).
  int get duplicateRows =>
      errors.where((e) => e.code == CsvImportErrorCode.duplicate).length;

  /// Baris di-skip karena tidak valid / tidak bisa dipetakan ke akun-kategori.
  int get invalidRows => errors
      .where(
        (e) =>
            e.rowNumber != null && e.code != CsvImportErrorCode.duplicate,
      )
      .length;

  int get skippedRows => duplicateRows + invalidRows;

  /// Error level file — kalau ada, seluruh import menghasilkan 0 baris.
  List<CsvRowError> get fileErrors =>
      errors.where((e) => e.rowNumber == null).toList();

  /// Teks summary siap-tampil. Format mengikuti [CsvImportSummary.message],
  /// tapi angkanya angka hasil commit: baris yang benar-benar masuk dan
  /// akun/kategori yang benar-benar dibuat (bukan hitungan baris valid).
  String get message =>
      'Berhasil import $insertedRows transaksi, $createdAccounts akun, '
      '$createdCategories kategori. Gagal/skip: $skippedRows baris';
}
