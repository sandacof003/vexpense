/// Parser CSV Expense IQ -> baris valid + error per baris.
///
/// Tanggung jawab: ambil String yang sudah di-decode, deteksi delimiter,
/// validasi header, lalu parse tiap baris data menjadi [CsvParsedRow] atau
/// [CsvRowError]. Tidak melakukan dedupe (itu di service) dan tidak menyentuh
/// DB/Flutter.
library;

import 'package:csv/csv.dart';

import 'csv_formats.dart';
import 'csv_import_models.dart';

/// Kolom wajib kontrak CSV Expense IQ (PRD §7).
///
/// `Date, Type, Category, Account, Amount, Currency, Note`.
/// Pencocokan header case-insensitive + trim. Urutan kolom bebas — parser
/// memetakan lewat nama header, bukan posisi.
const List<String> kRequiredHeaders = <String>[
  'Date',
  'Type',
  'Category',
  'Account',
  'Amount',
  'Currency',
  'Note',
];

/// Nilai type transaksi yang diterima (dinormalisasi lowercase).
const Set<String> kSupportedTypes = <String>{'income', 'expense', 'transfer'};

/// Hasil parse mentah (sebelum dedupe).
class CsvParseResult {
  const CsvParseResult({
    required this.rows,
    required this.errors,
    required this.delimiter,
  });

  final List<CsvParsedRow> rows;
  final List<CsvRowError> errors;
  final String delimiter;
}

/// Parser baris CSV -> [CsvParsedRow].
class CsvImportParser {
  const CsvImportParser({this.supportedCurrencyCodes = kDefaultCurrencyCodes});

  /// Kode mata uang yang dikenal (disuntik supaya parser tidak coupling ke DB).
  final Set<String> supportedCurrencyCodes;

  CsvParseResult parse(String decoded) {
    // Normalisasi line ending: \r\n dan \r -> \n (eol converter dipatok '\n').
    final normalized = decoded.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final delimiter = _detectDelimiter(normalized);
    final converter = CsvToListConverter(
      shouldParseNumbers: false,
      fieldDelimiter: delimiter,
      eol: '\n',
    );
    final rows = converter.convert(normalized);

    if (rows.isEmpty) {
      return CsvParseResult(
        rows: const [],
        errors: const [CsvRowError(code: CsvImportErrorCode.emptyFile)],
        delimiter: delimiter,
      );
    }

    // Header = baris pertama non-kosong.
    var headerIndex = 0;
    while (headerIndex < rows.length && _isBlankRow(rows[headerIndex])) {
      headerIndex++;
    }
    if (headerIndex >= rows.length) {
      return CsvParseResult(
        rows: const [],
        errors: const [CsvRowError(code: CsvImportErrorCode.emptyFile)],
        delimiter: delimiter,
      );
    }

    final header = _normalizeHeader(rows[headerIndex]);
    final missing = _missingHeaders(header);
    if (missing.isNotEmpty) {
      return CsvParseResult(
        rows: const [],
        errors: [
          CsvRowError(
            code: CsvImportErrorCode.missingHeaders,
            message:
                'Kolom header wajib hilang: ${missing.join(', ')}. '
                'Format diharapkan: ${kRequiredHeaders.join(', ')}.',
          ),
        ],
        delimiter: delimiter,
      );
    }

    // Map nama kolom -> index.
    final index = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final name = _canonicalHeader(header[i]);
      if (name.isNotEmpty) index[name] = i;
    }

    final parsedRows = <CsvParsedRow>[];
    final errors = <CsvRowError>[];

    for (var r = headerIndex + 1; r < rows.length; r++) {
      final raw = rows[r];
      if (_isBlankRow(raw)) continue; // baris kosong dilewati eksplisit (PRD)

      final rowNumber = r - headerIndex; // 1-based baris data

      String cell(String name) {
        final i = index[name.toLowerCase()];
        if (i == null || i >= raw.length) return '';
        final v = raw[i];
        return v == null ? '' : v.toString().trim();
      }

      final dateRaw = cell('Date');
      final typeRaw = cell('Type');
      final categoryRaw = cell('Category');
      final accountRaw = cell('Account');
      final amountRaw = cell('Amount');
      final currencyRaw = cell('Currency');
      final noteRaw = cell('Note');

      // Kolom wajib tidak boleh kosong (kecuali Category untuk transfer).
      final type = typeRaw.toLowerCase();
      if (dateRaw.isEmpty) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.requiredValueMissing,
            rowNumber: rowNumber,
            column: 'Date',
          ),
        );
        continue;
      }
      if (typeRaw.isEmpty) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.requiredValueMissing,
            rowNumber: rowNumber,
            column: 'Type',
          ),
        );
        continue;
      }
      if (type != 'transfer' && categoryRaw.isEmpty) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.requiredValueMissing,
            rowNumber: rowNumber,
            column: 'Category',
          ),
        );
        continue;
      }
      if (accountRaw.isEmpty) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.requiredValueMissing,
            rowNumber: rowNumber,
            column: 'Account',
          ),
        );
        continue;
      }
      if (amountRaw.isEmpty) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.requiredValueMissing,
            rowNumber: rowNumber,
            column: 'Amount',
          ),
        );
        continue;
      }
      if (currencyRaw.isEmpty) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.requiredValueMissing,
            rowNumber: rowNumber,
            column: 'Currency',
          ),
        );
        continue;
      }

      if (!kSupportedTypes.contains(type)) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.invalidType,
            rowNumber: rowNumber,
            column: 'Type',
            message:
                'Tipe "$typeRaw" tidak dikenal '
                '(harus income/expense/transfer)',
          ),
        );
        continue;
      }

      final DateTime date;
      try {
        date = CsvDateParser.parse(dateRaw);
      } on FormatException catch (e) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.invalidDate,
            rowNumber: rowNumber,
            column: 'Date',
            message: e.message,
          ),
        );
        continue;
      }

      // Currency dibutuhkan lebih awal: skala minor unit ditentukan per currency.
      final currency = currencyRaw.toUpperCase();

      final int minorUnits;
      final bool isNegative;
      try {
        final parsedAmount = const CsvNumberParser()
            .parse(amountRaw, currency: currency);
        minorUnits = parsedAmount.minorUnits;
        isNegative = parsedAmount.isNegative;
      } on FormatException catch (e) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.invalidAmount,
            rowNumber: rowNumber,
            column: 'Amount',
            message: e.message,
          ),
        );
        continue;
      }
      if (minorUnits <= 0) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.zeroAmount,
            rowNumber: rowNumber,
            column: 'Amount',
            message: 'Nominal harus lebih dari nol',
          ),
        );
        continue;
      }

      // Sign harus sesuai kontrak tipe: arah transaksi ditentukan kolom Type,
      // nominal disimpan sebagai magnitudo positif (schema: CHECK amount > 0).
      // Jadi `-50000` / `(50000)` pada income/expense/transfer = salah tulis,
      // bukan expense implisit — tanpa guard ini `minorUnits` yang selalu
      // positif membuat nominal negatif lolos sebagai transaksi positif.
      if (isNegative) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.invalidSign,
            rowNumber: rowNumber,
            column: 'Amount',
            message:
                'Nominal negatif tidak valid untuk tipe "$type" — '
                'tulis nominal positif, arah ditentukan kolom Type',
          ),
        );
        continue;
      }

      if (!supportedCurrencyCodes.contains(currency)) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.unknownCurrency,
            rowNumber: rowNumber,
            column: 'Currency',
            message: 'Mata uang "$currencyRaw" tidak dikenal',
          ),
        );
        continue;
      }

      parsedRows.add(
        CsvParsedRow(
          rowNumber: rowNumber,
          date: date,
          type: type,
          categoryName: type == 'transfer' ? '' : categoryRaw,
          accountName: accountRaw,
          amountMinorUnit: minorUnits,
          currencyCode: currency,
          note: noteRaw.isEmpty ? null : noteRaw,
        ),
      );
    }

    return CsvParseResult(
      rows: parsedRows,
      errors: errors,
      delimiter: delimiter,
    );
  }

  // --- helpers ---

  static String _detectDelimiter(String decoded) {
    final firstLine = decoded.split('\n').first;
    final commas = ','.allMatches(firstLine).length;
    final semis = ';'.allMatches(firstLine).length;
    final tabs = '\t'.allMatches(firstLine).length;
    final best = [commas, semis, tabs].reduce((a, b) => a > b ? a : b);
    if (best == 0) return ',';
    if (best == semis) return ';';
    if (best == tabs) return '\t';
    return ',';
  }

  static bool _isBlankRow(List<dynamic> row) {
    return row.every((c) => c == null || c.toString().trim().isEmpty);
  }

  static List<String> _normalizeHeader(List<dynamic> row) {
    return row.map((c) => c == null ? '' : c.toString().trim()).toList();
  }

  static String _canonicalHeader(String name) => name.toLowerCase();

  static List<String> _missingHeaders(List<String> header) {
    final present = header
        .map(_canonicalHeader)
        .where((h) => h.isNotEmpty)
        .toSet();
    return kRequiredHeaders
        .where((h) => !present.contains(h.toLowerCase()))
        .toList();
  }
}

/// Seed kode mata uang region (PRD §6) — default bila caller tidak suntik.
const Set<String> kDefaultCurrencyCodes = <String>{
  'IDR',
  'USD',
  'JPY',
  'USDT',
  'SGD',
  'MYR',
  'THB',
};
