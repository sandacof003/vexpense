import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/daos/account_dao.dart';
import 'package:v_expense/core/data/daos/category_dao.dart';
import 'package:v_expense/core/data/daos/currency_dao.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/repositories/csv_import_repository.dart';
import 'package:v_expense/core/services/csv/csv_import_service.dart';

/// INT-07 gap: metrik PRD §9 "Import 1000 transaksi < 10 detik" belum punya
/// harness. Test ini yang menutupnya — 1000 baris CSV nyata masuk lewat jalur
/// produksi ([CsvImportRepositoryImpl.importBytes] = satu DB transaction),
/// lalu durasinya diukur.
///
/// Batas 10 detik di sini **longgar sengaja**: ini gate PRD di runner VPS
/// 2-core, bukan benchmark presisi. Kalau tembus 10 detik, metrik PRD gagal —
/// itu sinyal nyata, bukan flakiness.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  CsvImportRepositoryImpl repo() => CsvImportRepositoryImpl(
    db,
    const CsvImportService(),
    TransactionDao(db),
    AccountDao(db),
    CategoryDao(db),
    CurrencyDao(db),
  );

  /// 1000 baris unik: tanggal naik per baris, 3 kategori seed, 2 akun seed.
  /// Nominal & note dibedakan supaya hash dedupe tidak saling menabrak.
  String csv1000() {
    final buffer = StringBuffer('Date,Type,Category,Account,Amount,Currency,Note\n');
    for (var i = 0; i < 1000; i++) {
      final date = DateTime(2026, 1, 1).add(Duration(days: i));
      final y = date.year;
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      final type = i.isEven ? 'expense' : 'income';
      // Kategori harus cocok tipe-nya: seed expense (Makan & Minum/Transport)
      // vs seed income (Gaji). Salah pasang = baris invalid, bukan bug.
      final category = type == 'income'
          ? 'Gaji'
          : (i % 3 == 0 ? 'Transport' : 'Makan & Minum');
      final account = i % 2 == 0 ? 'Cash' : 'BCA';
      final amount = 1000 + i;
      buffer.writeln('$y-$m-$d,$type,$category,$account,$amount,IDR,baris-$i');
    }
    return buffer.toString();
  }

  test('import 1000 transaksi < 10 detik (PRD §9)', () async {
    final r = repo();
    final bytes = utf8.encode(csv1000());

    final stopwatch = Stopwatch()..start();
    final report = await r.importBytes(bytes: bytes, fileName: 'mutasi-1000.csv');
    stopwatch.stop();

    final elapsed = stopwatch.elapsed;
    // ignore: avoid_print
    print(
      'BENCHMARK import 1000 baris: ${elapsed.inMilliseconds} ms',
    );

    expect(report.insertedRows, 1000);
    expect(report.skippedRows, 0);
    expect(await db.transactionDao.count(), 1000);
    expect(report.duplicateRows, 0);
    expect(report.invalidRows, 0);
    expect(
      elapsed.inSeconds,
      lessThan(10),
      reason: 'PRD §9: import 1000 transaksi harus < 10 detik',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
