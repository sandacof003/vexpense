import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/services/csv/csv_encoding.dart';
import 'package:v_expense/core/services/csv/csv_formats.dart';
import 'package:v_expense/core/services/csv/csv_import_models.dart';
import 'package:v_expense/core/services/csv/csv_import_service.dart';
import 'package:v_expense/core/services/csv/csv_parser.dart';

void main() {
  group('CsvNumberParser — skala per minor unit currency', () {
    const parser = CsvNumberParser();

    test('IDR (minor unit 0): 25000 -> 25000, bukan 2500000', () {
      final r = parser.parse('25000', currency: 'IDR');
      expect(r.minorUnits, 25000);
      expect(r.isNegative, false);
    });

    test('IDR: format Indonesia dengan titik ribuan tidak diskalakan', () {
      expect(parser.parse('1.500.000', currency: 'IDR').minorUnits, 1500000);
      expect(parser.parse('Rp 1.500.000', currency: 'IDR').minorUnits, 1500000);
    });

    test('JPY (minor unit 0)', () {
      expect(parser.parse('¥1000', currency: 'JPY').minorUnits, 1000);
      expect(parser.parse('1000.4', currency: 'JPY').minorUnits, 1000);
    });

    test('USD (minor unit 2)', () {
      expect(parser.parse(r'$25.00', currency: 'USD').minorUnits, 2500);
      expect(parser.parse('1500000.50', currency: 'USD').minorUnits, 150000050);
      expect(parser.parse('1500000,50', currency: 'USD').minorUnits, 150000050);
    });

    test('USDT (minor unit 6)', () {
      expect(parser.parse('1.5', currency: 'USDT').minorUnits, 1500000);
      expect(parser.parse('0.000001', currency: 'USDT').minorUnits, 1);
    });

    test('desimal melebihi minor unit dibulatkan half-up', () {
      expect(parser.parse('25000.5', currency: 'IDR').minorUnits, 25001);
      expect(parser.parse('25000.4', currency: 'IDR').minorUnits, 25000);
      expect(parser.parse('1.0050', currency: 'USD').minorUnits, 101);
      expect(parser.parse('2.4999', currency: 'USD').minorUnits, 250);
    });

    test('parsing eksak tanpa double', () {
      expect(parser.parse('0.1', currency: 'USD').minorUnits, 10);
      expect(parser.parse('0.29', currency: 'USD').minorUnits, 29);
      expect(
        parser.parse('1234567890.12', currency: 'USD').minorUnits,
        123456789012,
      );
      expect(parser.parse('.50', currency: 'USD').minorUnits, 50);
    });

    test('titik ribuan ambigu -> angka 3 digit dianggap ribuan', () {
      expect(parser.parse('1.500', currency: 'IDR').minorUnits, 1500);
    });

    test('currency tak dikenal -> fallback ISO 4217 (2 desimal)', () {
      expect(parser.parse('25.00', currency: 'EUR').minorUnits, 2500);
      expect(parser.minorUnitFor('idr'), 0);
      expect(parser.minorUnitFor('usdt'), 6);
    });

    test('tanda negatif (expense)', () {
      final r = parser.parse('-1500', currency: 'IDR');
      expect(r.minorUnits, 1500);
      expect(r.isNegative, true);
    });

    test('tanda negatif dalam kurung', () {
      final r = parser.parse('(1500)', currency: 'IDR');
      expect(r.minorUnits, 1500);
      expect(r.isNegative, true);
    });

    test('nominal kosong throws', () {
      expect(() => parser.parse('', currency: 'IDR'), throwsFormatException);
    });

    test('nominal tanpa angka throws', () {
      expect(() => parser.parse('abc', currency: 'IDR'), throwsFormatException);
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
      expect(result.rows.first.amountMinorUnit, 25000);
      expect(result.rows.first.categoryName, 'Makan');
      expect(result.rows.first.note, 'lunch');
      expect(result.rows[1].note, isNull);
    });

    test('nominal diskalakan sesuai minor unit currency baris', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,\n'
          '2024-01-15,expense,Makan,JPY Wallet,1000,JPY,\n'
          '2024-01-15,expense,Makan,USD Wallet,25.00,USD,';
      final result = parser.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.rows[0].amountMinorUnit, 25000); // IDR: 0 desimal
      expect(result.rows[1].amountMinorUnit, 1000); // JPY: 0 desimal
      expect(result.rows[2].amountMinorUnit, 2500); // USD: 2 desimal
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

    test('income negatif -> row error invalidSign, tidak tersimpan', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,income,Gaji,BCA,-5000000,IDR,';
      final result = parser.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.code, CsvImportErrorCode.invalidSign);
      expect(result.errors.single.rowNumber, 1);
      expect(result.errors.single.column, 'Amount');
      expect(result.errors.single.message, contains('income'));
    });

    test('expense negatif -> row error invalidSign, tidak tersimpan', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,-25000,IDR,lunch';
      final result = parser.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors.single.code, CsvImportErrorCode.invalidSign);
      expect(result.errors.single.message, contains('expense'));
    });

    test('transfer negatif -> row error invalidSign', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,transfer,,BCA,-25000,IDR,';
      final result = parser.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors.single.code, CsvImportErrorCode.invalidSign);
    });

    test('tanda negatif dalam kurung juga ditolak', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,"(25000)",IDR,';
      final result = parser.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors.single.code, CsvImportErrorCode.invalidSign);
    });

    test('nominal nol -> zeroAmount (guard kini benar-benar kena)', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,0,IDR,';
      final result = parser.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors.single.code, CsvImportErrorCode.zeroAmount);
    });

    test('baris valid lain tidak ikut tertolak saat ada baris negatif', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,income,Gaji,BCA,-5000000,IDR,\n'
          '2024-01-16,expense,Makan,Cash,25000,IDR,ok';
      final result = parser.parse(csv);
      expect(result.rows, hasLength(1));
      expect(result.rows.single.amountMinorUnit, 25000);
      expect(result.rows.single.type, 'expense');
      expect(result.errors.single.rowNumber, 1);
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
      const existing = {'2024-1-15|expense|25000|IDR|Cash|Makan|lunch'};
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

    test('baris sign salah -> invalid, tidak tersimpan', () {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,income,Gaji,BCA,-5000000,IDR,\n'
          '2024-01-15,expense,Makan,Cash,-25000,IDR,\n'
          '2024-01-16,expense,Makan,Cash,25000,IDR,ok';
      final result = service.importBytes(
        bytes: utf8.encode(csv),
        fileName: 'sign.csv',
      );
      expect(result.rows, hasLength(1));
      expect(result.rows.single.amountMinorUnit, 25000);
      expect(result.summary.validRows, 1);
      expect(result.summary.invalidRows, 2);
      expect(result.summary.totalRows, 3);
      expect(
        result.errors
            .where((e) => e.code == CsvImportErrorCode.invalidSign)
            .map((e) => e.rowNumber),
        [1, 2],
      );
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
