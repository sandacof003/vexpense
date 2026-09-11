import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/account_dao.dart';
import 'daos/category_dao.dart';
import 'daos/currency_dao.dart';
import 'daos/exchange_rate_dao.dart';
import 'daos/transaction_dao.dart';
import 'enums.dart';
import 'tables.dart';

part 'database.g.dart';

/// Nomor versi schema. Naikkan + tambahkan step di [_migration] setiap ada
/// perubahan struktur tabel.
const int _schemaVersion = 1;

/// Seed kategori bawaan (idempotent — dicek `WHERE NOT EXISTS` saat migration,
/// jadi tidak duplikat walau database dibuka ulang).
const List<(String, CategoryType)> _seedCategories = [
  ('Gaji', CategoryType.income),
  ('Bonus', CategoryType.income),
  ('Bisnis / Lainnya', CategoryType.income),
  ('Makan & Minum', CategoryType.expense),
  ('Transport', CategoryType.expense),
  ('Belanja', CategoryType.expense),
  ('Tagihan & Utilitas', CategoryType.expense),
  ('Hiburan', CategoryType.expense),
  ('Kesehatan', CategoryType.expense),
  ('Pendidikan', CategoryType.expense),
  ('Lainnya', CategoryType.expense),
];

/// Seed mata uang (idempotent).
const List<(String, int, String)> _seedCurrencies = [
  ('IDR', 0, 'Rp'),
  ('USD', 2, r'$'),
  ('JPY', 0, '¥'),
  ('USDT', 6, '₮'),
  ('SGD', 2, r'S$'),
  ('MYR', 2, 'RM'),
  ('THB', 2, '฿'),
];

/// Database utama V Expense.
///
/// `PRAGMA foreign_keys = ON` diaktifkan di [MigrationStrategy.beforeOpen]
/// untuk seluruh sesi.
@DriftDatabase(
  tables: [Currencies, Accounts, Categories, Transactions, ExchangeRates],
  daos: [CurrencyDao, AccountDao, CategoryDao, TransactionDao, ExchangeRateDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Untuk unit test: buka database di file tertentu (biasanya `inMemory`).
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => _schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seed(m);
    },
    onUpgrade: (m, from, to) async {
      // Versi baru di masa depan ditambah di sini. v1 → belum ada upgrade.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seed(Migrator m) async {
    // Mata uang (PK = code, jadi INSERT OR IGNORE aman & idempotent).
    await batch((b) {
      b.insertAll(
        currencies,
        _seedCurrencies
            .map(
              (c) => CurrenciesCompanion.insert(
                code: c.$1,
                minorUnit: c.$2,
                symbol: c.$3,
              ),
            )
            .toList(),
        mode: InsertMode.insertOrIgnore,
      );
    });

    // Kategori: hanya insert kalau namanya belum ada.
    for (final (name, type) in _seedCategories) {
      final exists = await (select(
        categories,
      )..where((c) => c.name.equals(name))).getSingleOrNull();
      if (exists == null) {
        await into(
          categories,
        ).insert(CategoriesCompanion.insert(name: name, type: type));
      }
    }
  }
}

/// Buka koneksi native SQLite. Di Android/desktop pakai file database
/// `v_expense.sqlite`; di unit test pakai in-memory (lihat [AppDatabase.forTesting]).
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'v_expense.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
