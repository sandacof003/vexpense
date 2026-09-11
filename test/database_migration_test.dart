import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/database.dart';

/// Test schema & migrasi BE-01 secara end-to-end memakai database FILE asli
/// (bukan in-memory), supaya migrasi + seed beneran dijalankan ulang saat
/// database dibuka kembali. Ini menutup acceptance:
/// - Migration dapat dijalankan ulang tanpa menggandakan seed.
/// - Currency mencakup IDR, USD, JPY, SGD, USDT, MYR, THB dengan minor_unit &
///   symbol yang benar.
/// - Semua index PRD tersedia.
void main() {
  late Directory tmp;
  late String path;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vexpense_migration_test');
    path = '${tmp.path}/test.sqlite';
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  AppDatabase openFile() => AppDatabase.forTesting(NativeDatabase(File(path)));

  test('currency seed lengkap: 7 kode + minor_unit + symbol benar', () async {
    final db = openFile();
    addTearDown(db.close);

    final currencies = await db.currencyDao.getAll();
    final byCode = {for (final c in currencies) c.code: c};

    expect(
      byCode.keys,
      containsAll(['IDR', 'USD', 'JPY', 'SGD', 'USDT', 'MYR', 'THB']),
    );
    expect(byCode.length, 7);

    // minor_unit sesuai PRD §6: IDR/JPY=0, USD/SGD/MYR/THB=2, USDT=6.
    expect(byCode['IDR']!.minorUnit, 0);
    expect(byCode['JPY']!.minorUnit, 0);
    expect(byCode['USD']!.minorUnit, 2);
    expect(byCode['SGD']!.minorUnit, 2);
    expect(byCode['MYR']!.minorUnit, 2);
    expect(byCode['THB']!.minorUnit, 2);
    expect(byCode['USDT']!.minorUnit, 6);

    // symbol benar.
    expect(byCode['IDR']!.symbol, 'Rp');
    expect(byCode['USD']!.symbol, r'$');
    expect(byCode['JPY']!.symbol, '¥');
    expect(byCode['SGD']!.symbol, r'S$');
    expect(byCode['MYR']!.symbol, 'RM');
    expect(byCode['THB']!.symbol, '฿');
    expect(byCode['USDT']!.symbol, '₮');
  });

  test(
    'migration dijalankan ulang (reopen file) tidak menggandakan seed',
    () async {
      // Buka pertama kali → onCreate + seed.
      final db1 = openFile();
      final currencies1 = await db1.currencyDao.getAll();
      final categories1 = await db1.categoryDao.getAll();
      expect(currencies1.length, 7);
      expect(categories1.length, 11);
      await db1.close();

      // Buka ulang file yang sama → migrasi tidak boleh seed lagi.
      final db2 = openFile();
      addTearDown(db2.close);
      final currencies2 = await db2.currencyDao.getAll();
      final categories2 = await db2.categoryDao.getAll();

      expect(currencies2.length, 7);
      expect(categories2.length, 11);

      // Pastikan tidak ada duplikat nama kategori.
      final names = categories2.map((c) => c.name).toList();
      expect(names.toSet().length, names.length);
    },
  );

  test('PRAGMA foreign_keys ON aktif di koneksi file', () async {
    final db = openFile();
    addTearDown(db.close);
    final on = await db
        .customSelect('PRAGMA foreign_keys')
        .map((r) => r.read<int>('foreign_keys'))
        .getSingle();
    expect(on, 1);
  });

  test('semua index PRD tersedia di schema SQLite', () async {
    final db = openFile();
    addTearDown(db.close);

    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'transactions' AND name LIKE 'idx_%'",
        )
        .map((r) => r.read<String>('name'))
        .get();

    expect(
      rows.toSet(),
      containsAll([
        'idx_transactions_account_id',
        'idx_transactions_category_id',
        'idx_transactions_date',
        'idx_transactions_to_account_id',
        'idx_transactions_date_category',
        'idx_transactions_date_account',
      ]),
    );
  });

  test('schema tidak punya kolom balance di accounts', () async {
    final db = openFile();
    addTearDown(db.close);

    final cols = await db
        .customSelect("PRAGMA table_info('accounts')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(cols, isNot(contains('balance')));
  });
}
