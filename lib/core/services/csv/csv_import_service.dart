/// Layanan import CSV end-to-end (tanpa DB, tanpa widget).
///
/// Alur (PRD §7):
/// 1. validasi file (ekstensi/encoding/header) -> error tingkat-file;
/// 2. parse & preview (baris invalid di-highlight lewat [CsvRowError]);
/// 3. dedupe (hash per baris) -> baris duplikat di-skip dengan alasan;
/// 4. summary siap-tampil.
///
/// Service TIDAK menyentuh DB. Langkah "atomic import" (satu DB transaction)
/// dan "mapping kategori/akun" ada di lapisan data/repository, yang akan
/// memanggil service ini lalu mengambil [CsvImportResult.rows] untuk commit.
library;

import 'dart:convert';

import 'csv_encoding.dart';
import 'csv_import_models.dart';
import 'csv_parser.dart';

/// Konfigurasi satu kali import.
class CsvImportOptions {
  const CsvImportOptions({
    this.supportedCurrencyCodes = kDefaultCurrencyCodes,
    this.existingHashes = const <String>{},
  });

  /// Kode mata uang valid (dari tabel currencies saat runtime).
  final Set<String> supportedCurrencyCodes;

  /// Hash transaksi yang sudah ada di DB (untuk deteksi duplikat). Service
  /// import menghitung hash yang sama via [CsvParsedRow.computeDedupeHash].
  final Set<String> existingHashes;
}

/// Layanan import CSV.
class CsvImportService {
  const CsvImportService({
    this.parser = const CsvImportParser(),
    this.encodingDetector = const CsvEncodingDetector(),
  });

  final CsvImportParser parser;
  final CsvEncodingDetector encodingDetector;

  /// Import dari bytes (hasil baca file picker).
  ///
  /// [fileName] hanya dipakai untuk validasi ekstensi; boleh null bila
  /// sumber tidak punya nama (mis. dari clipboard/unit test).
  CsvImportResult importBytes({
    required List<int> bytes,
    String? fileName,
    CsvImportOptions options = const CsvImportOptions(),
  }) {
    final fileErrors = <CsvRowError>[];

    // 1. Validasi ekstensi.
    if (fileName != null && !_isCsv(fileName)) {
      fileErrors.add(
        CsvRowError(
          code: CsvImportErrorCode.notCsv,
          message: 'File bukan .csv (diterima: $fileName)',
        ),
      );
      return _emptyResult(fileErrors);
    }

    // 2. Validasi tidak kosong.
    if (bytes.isEmpty) {
      fileErrors.add(const CsvRowError(code: CsvImportErrorCode.emptyFile));
      return _emptyResult(fileErrors);
    }

    // 3. Deteksi encoding + decode.
    final encoding = encodingDetector.detect(bytes);
    final decoded = encoding.decoded;
    if (decoded.trim().isEmpty) {
      fileErrors.add(const CsvRowError(code: CsvImportErrorCode.emptyFile));
      return _emptyResult(fileErrors);
    }

    // 4. Parse dengan currency codes dari opsi.
    final effectiveParser =
        options.supportedCurrencyCodes == kDefaultCurrencyCodes
        ? parser
        : CsvImportParser(
            supportedCurrencyCodes: options.supportedCurrencyCodes,
          );
    final parsed = effectiveParser.parse(decoded);

    // Error tingkat-file (header/empty) langsung keluar.
    if (parsed.errors.any((e) => e.rowNumber == null)) {
      return _emptyResult(parsed.errors);
    }

    // 5. Dedupe.
    final valid = <CsvParsedRow>[];
    final allErrors = <CsvRowError>[...parsed.errors];
    final seen = <String>{};
    var duplicateCount = 0;

    final accounts = <String>{};
    final categories = <String>{};

    for (final row in parsed.rows) {
      final hash = row.computeDedupeHash();

      // Duplikat dalam file itu sendiri.
      if (seen.contains(hash)) {
        allErrors.add(
          CsvRowError(
            code: CsvImportErrorCode.duplicate,
            rowNumber: row.rowNumber,
            message: 'Duplikat baris ${row.rowNumber} di file ini',
          ),
        );
        duplicateCount++;
        continue;
      }
      // Duplikat terhadap transaksi existing.
      if (options.existingHashes.contains(hash)) {
        allErrors.add(
          CsvRowError(
            code: CsvImportErrorCode.duplicate,
            rowNumber: row.rowNumber,
            message: 'Sudah ada di database',
          ),
        );
        duplicateCount++;
        continue;
      }

      seen.add(hash);
      valid.add(row);
      accounts.add(row.accountName.trim());
      if (row.categoryName.isNotEmpty) {
        categories.add(row.categoryName.trim());
      }
    }

    final totalRows = valid.length + duplicateCount + parsed.errors.length;

    final summary = CsvImportSummary(
      totalRows: totalRows,
      validRows: valid.length,
      duplicateRows: duplicateCount,
      invalidRows: parsed.errors.length,
      distinctAccounts: accounts.length,
      distinctCategories: categories.length,
    );

    return CsvImportResult(rows: valid, errors: allErrors, summary: summary);
  }

  bool _isCsv(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.csv');
  }

  CsvImportResult _emptyResult(List<CsvRowError> fileErrors) {
    return CsvImportResult(
      rows: const [],
      errors: fileErrors,
      summary: const CsvImportSummary(
        totalRows: 0,
        validRows: 0,
        duplicateRows: 0,
        invalidRows: 0,
        distinctAccounts: 0,
        distinctCategories: 0,
      ),
    );
  }
}

/// Helper: baca bytes lalu import lewat service (convenience untuk UI).
///
/// UI cukup panggil [CsvImportService.importBytes]; helper ini hanya
/// menyediakan jalur alternatif bila konten sudah berupa String.
extension CsvImportServiceText on CsvImportService {
  CsvImportResult importText(
    String content, {
    CsvImportOptions options = const CsvImportOptions(),
  }) {
    return importBytes(bytes: utf8.encode(content), options: options);
  }
}
