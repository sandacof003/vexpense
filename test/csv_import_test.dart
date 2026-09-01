import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/services/csv/csv_encoding.dart';
import 'package:v_expense/core/services/csv/csv_formats.dart';
import 'package:v_expense/core/services/csv/csv_import_models.dart';
import 'package:v_expense/core/services/csv/csv_import_service.dart';
import 'package:v_expense/core/services/csv/csv_parser.dart';

void main() {
  group('CsvNumberParser', () {
    const parser = CsvNumberParser();

    test('integer polos', () {
      expect(parser.parse('1500').minorUnits, 150000);
      expect(parser.parse('1500').isNegative, false);
    });

    test('format Indonesia dengan titik ribuan', () {
      expect(parser.parse('1.500.000').minorUnits, 150000000);
    });

    test('format dengan desimal titik', () {
      expect(parser.parse('1500000.50').minorUnits, 150000050);
    });

    test('format dengan desimal koma', () {
      expect(parser.parse('1500000,50').minorUnits, 150000050);
    });

    test('titik ribuan ambigu -> angka 3 digit dianggap ribuan', () {
      // "1.500" = 1500 (bukan 1.5)
      expect(parser.parse('1.500').minorUnits, 150000);
    });

    test('strip simbol mata uang', () {
      expect(parser.parse('Rp 1.500.000').minorUnits, 150000000);
      expect(parser.parse(r'$25.00').minorUnits, 2500);
      expect(parser.parse('¥1000').minorUnits, 100000);
    });

    test('tanda negatif (expense)', () {
      final r = parser.parse('-1500');
      expect(r.minorUnits, 150000);
      expect(r.isNegative, true);
    });

    test('tanda negatif dalam kurung', () {
      final r = parser.parse('(1500)');
      expect(r.minorUnits, 150000);
      expect(r.isNegative, true);
    });

    test('nominal kosong throws', () {
      expect(() => parser.parse(''), throwsFormatException);
    });

    test('nominal tanpa angka throws', () {
      expect(() => parser.parse('abc'), throwsFormatException);
    });
  });

  group('CsvDateParser', () {
    test('ISO yyyy-MM-dd', () {
      expect(CsvDateParser.parse('2024-01-15'), DateTime.utc(2024, 1, 15));
    });

    test('dd/MM/yyyy', () {
      expect(CsvDateParser.parse('15/01/2024'), DateTime.utc(2024, 1, 15));
    });

    test('dd-MM-yyyy', () {
      expect(CsvDateParser.parse('15-01-2024'), DateTime.utc(2024, 1, 15));
    });

    test('tanggal tidak valid throws', () {
      expect(() => CsvDateParser.parse('31/02/2024'), throwsFormatException);
      expect(() => CsvDateParser.parse('not-a-date'), throwsFormatException);
    });
  });

  group('CsvEncodingDetector', () {
    const detector = CsvEncodingDetector();

    test('UTF-8 valid', () {
      final r = detector.detect(utf8.encode('Date,Type\n2024-01-01,expense'));
      expect(r.encoding, CsvEncoding.utf8);
      expect(r.decoded, contains('Date'));
    });

    test('BOM UTF-8 di-strip', () {
      final bom = [0xEF, 0xBB, 0xBF, ...utf8.encode('Date')];
      final r = detector.detect(bom);
      expect(r.encoding, CsvEncoding.utf8);
      expect(r.decoded, 'Date');
    });

    test('byte invalid UTF-8 -> windows1252', () {
      // 0xE9 (é di latin-1) tidak valid sendirian di UTF-8.
      final r = detector.detect([0xE9, 0x20, 0x41]);
      expect(r.encoding, CsvEncoding.windows1252);
      expect(r.decoded, contains('é'));
    });
  });

  group('CsvImportParser', () {
    const parser = CsvImportParser();

    test('parse header + baris valid', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,lunch\n'
          '2024-01-16,income,Gaji,BCA,5000000,IDR,';
      final result = parser.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(2));
      expect(result.rows.first.amountMinorUnit, 2500000);
      expect(result.rows.first.categoryName, 'Makan');
      expect(result.rows.first.note, 'lunch');
      expect(result.rows[1].note, isNull);
    });

    test('kolom wajib hilang -> error missingHeaders', () {
      const csv = 'Date,Amount,Currency\n2024-01-15,25000,IDR';
      final result = parser.parse(csv);
      expect(result.errors, hasLength(1));
      expect(result.errors.first.code, CsvImportErrorCode.missingHeaders);
      expect(result.rows, isEmpty);
    });

    test('baris kosong dilewati', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,\n'
          '   \n';
      final result = parser.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(1));
    });

    test('file kosong -> emptyFile', () {
      final result = parser.parse('');
      expect(result.errors.first.code, CsvImportErrorCode.emptyFile);
      expect(result.rows, isEmpty);
    });

    test('baris invalid: tanggal salah', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '31/02/2024,expense,Makan,Cash,25000,IDR,';
      final result = parser.parse(csv);
      expect(result.errors.first.code, CsvImportErrorCode.invalidDate);
      expect(result.rows, isEmpty);
    });

    test('baris invalid: nominal salah', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,abc,IDR,';
      final result = parser.parse(csv);
      expect(result.errors.first.code, CsvImportErrorCode.invalidAmount);
    });

    test('baris invalid: tipe tidak dikenal', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,refund,Makan,Cash,25000,IDR,';
      final result = parser.parse(csv);
      expect(result.errors.first.code, CsvImportErrorCode.invalidType);
    });

    test('baris invalid: kategori kosong pada expense', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,,Cash,25000,IDR,';
      final result = parser.parse(csv);
      expect(result.errors.first.code, CsvImportErrorCode.requiredValueMissing);
    });

    test('transfer boleh kategori kosong', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,transfer,,BCA,25000,IDR,';
      final result = parser.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.single.type, 'transfer');
      expect(result.rows.single.categoryName, '');
    });

    test('mata uang tidak dikenal', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,25000,EUR,';
      final result = parser.parse(csv);
      expect(result.errors.first.code, CsvImportErrorCode.unknownCurrency);
    });

    test('karakter khusus & koma di dalam note (quoted)', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,"Makan,Minum",Cash,25000,IDR,"nasi, goreng"';
      final result = parser.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.single.categoryName, 'Makan,Minum');
      expect(result.rows.single.note, 'nasi, goreng');
    });

    test('delimiter semicolon terdeteksi', () {
      const csv =
          'Date;Type;Category;Account;Amount;Currency;Note\n'
          '2024-01-15;expense;Makan;Cash;25000;IDR;';
      final result = parser.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(1));
    });

    test('header case-insensitive + urutan bebas', () {
      const csv =
          'note,AMOUNT,currency,account,CATEGORY,type,DATE\n'
          'x,25000,IDR,Cash,Makan,expense,2024-01-15';
      final result = parser.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.single.categoryName, 'Makan');
      expect(result.rows.single.note, 'x');
    });
  });

  group('CsvImportService', () {
    const service = CsvImportService();

    const validCsv =
        'Date,Type,Category,Account,Amount,Currency,Note\n'
        '2024-01-15,expense,Makan,Cash,25000,IDR,lunch\n'
        '2024-01-16,income,Gaji,BCA,5000000,IDR,\n';

    test('import valid -> summary benar', () {
      final result = service.importBytes(
        bytes: utf8.encode(validCsv),
        fileName: 'data.csv',
      );
      expect(result.isClean, true);
      expect(result.summary.validRows, 2);
      expect(result.summary.distinctAccounts, 2);
      expect(result.summary.distinctCategories, 2);
      expect(result.summary.message, contains('Berhasil import 2 transaksi'));
    });

    test('ekstensi bukan csv -> notCsv', () {
      final result = service.importBytes(
        bytes: utf8.encode(validCsv),
        fileName: 'data.txt',
      );
      expect(result.errors.first.code, CsvImportErrorCode.notCsv);
    });

    test('file kosong -> emptyFile', () {
      final result = service.importBytes(bytes: const [], fileName: 'data.csv');
      expect(result.errors.first.code, CsvImportErrorCode.emptyFile);
    });

    test('duplikat dalam file di-skip', () {
      const dup =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,lunch\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,lunch\n';
      final result = service.importBytes(
        bytes: utf8.encode(dup),
        fileName: 'data.csv',
      );
      expect(result.summary.validRows, 1);
      expect(result.summary.duplicateRows, 1);
      expect(
        result.errors,
        anyElement(
          predicate(
            (e) => e is CsvRowError && e.code == CsvImportErrorCode.duplicate,
          ),
        ),
      );
    });

    test('duplikat terhadap existing di-skip', () {
      const dup =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,lunch\n';
      const existing = {'2024-1-15|expense|2500000|IDR|Cash|Makan|lunch'};
      final result = service.importBytes(
        bytes: utf8.encode(dup),
        fileName: 'data.csv',
        options: CsvImportOptions(existingHashes: existing),
      );
      expect(result.summary.validRows, 0);
      expect(result.summary.duplicateRows, 1);
    });

    test('campuran valid + invalid -> summary hitung benar', () {
      const mix =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,ok\n'
          'bad-date,expense,Makan,Cash,25000,IDR,invalid\n';
      final result = service.importBytes(
        bytes: utf8.encode(mix),
        fileName: 'data.csv',
      );
      expect(result.summary.validRows, 1);
      expect(result.summary.invalidRows, 1);
      expect(result.rows, hasLength(1));
      expect(result.errors, hasLength(1));
    });

    test('hash dedupe konsisten antar format angka', () {
      const a =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,1.500.000,IDR,x\n';
      const b =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,1500000,IDR,x\n';
      final ra = service.importBytes(bytes: utf8.encode(a), fileName: 'a.csv');
      final rb = service.importBytes(bytes: utf8.encode(b), fileName: 'b.csv');
      expect(
        ra.rows.single.computeDedupeHash(),
        rb.rows.single.computeDedupeHash(),
      );
    });
  });
}
