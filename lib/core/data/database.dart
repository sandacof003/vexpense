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

/// Nomor versi schema. Naikkan + tambahkan step di [AppDatabase.migration]
/// setiap ada perubahan struktur tabel.
///
/// Riwayat: v1 = schema awal, v2 = index unik `lower(name)` untuk
/// accounts & categories.
const int _schemaVersion = 2;

/// Index unik case-insensitive `lower(name)`.
///
/// Validasi duplikat nama di repository cuma lapisan UX — invariant-nya dijaga
/// di sini supaya mapping import by-name (`lower(name)`) tidak pernah ambigu
/// walau ada jalur tulis yang melewati repository.
///
/// DDL ekspresi indeks tidak bisa dideklarasikan di `tables.dart`, jadi dibuat
/// manual (idempoten) di onCreate dan di step upgrade v1 → v2.
const List<String> _uniqueNameIndexes = [
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_name_lower '
      'ON accounts (lower(name))',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_name_lower '
      'ON categories (lower(name))',
];

/// Seed kategori bawaan (idempotent — nama dicek dulu sebelum insert,
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
      await _ensureUniqueNameIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2: index unik `lower(name)`. Rapikan duplikat lama dulu supaya
        // pembuatan index tidak gagal di DB yang sudah terisi.
        await _mergeCaseInsensitiveNameDuplicates();
        await _ensureUniqueNameIndexes();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _ensureUniqueNameIndexes() async {
    for (final sql in _uniqueNameIndexes) {
      await customStatement(sql);
    }
  }

  /// Rapikan nama yang cuma beda kapitalisasi (validasi v1 hanya di aplikasi):
  /// semua referensi dipindah ke baris "keeper" (id terkecil per grup
  /// `lower(name)`), lalu baris sisanya dihapus.
  Future<void> _mergeCaseInsensitiveNameDuplicates() async {
    // HARUS sebelum repoint — lihat [_deleteTransfersBetweenSameNameAccounts].
    await _deleteTransfersBetweenSameNameAccounts();
    await _repointToKeeper('transactions', 'account_id', 'accounts');
    await _repointToKeeper('transactions', 'to_account_id', 'accounts');
    await _deleteDuplicateNames('accounts');
    await _repointToKeeper('transactions', 'category_id', 'categories');
    await _deleteDuplicateNames('categories');
  }

  /// Pindahkan `table.column` ke keeper grup nama (case-insensitive).
  /// No-op pada baris yang sudah menunjuk keeper / bernilai NULL.
  Future<void> _repointToKeeper(
    String table,
    String column,
    String nameTable,
  ) => customUpdate(
    'UPDATE $table SET $column = ('
    'SELECT MIN(k.id) FROM $nameTable k WHERE lower(k.name) = ('
    'SELECT lower(s.name) FROM $nameTable s WHERE s.id = $table.$column)) '
    'WHERE $column IS NOT NULL',
  );

  /// Buang transfer antar dua akun yang namanya sama (case-insensitive).
  ///
  /// Di v1 akun `Tunai` (id=1) dan `tunai` (id=2) itu dua baris berbeda, jadi
  /// transfer 1 → 2 legal. Setelah repoint ke keeper, kedua kolom jatuh ke id
  /// yang sama → jadi transfer ke diri sendiri, dan CHECK di `tables.dart`
  /// (`type != 'transfer' OR to_account_id != account_id`) menolak UPDATE-nya
  /// langsung, bukan cuma barisnya. Karena drift menulis `user_version` sesudah
  /// `onUpgrade` kelar, throw di sini bikin DB terkunci di v1 dan gagal dibuka
  /// selamanya. Baris begini cuma bisa muncul dari collapse (CHECK sudah
  /// melarangnya di v1) dan perpindahan saldonya nol, jadi dibuang lebih dulu.
  Future<void> _deleteTransfersBetweenSameNameAccounts() => customUpdate(
    "DELETE FROM transactions WHERE type = 'transfer' "
    'AND account_id IS NOT NULL AND to_account_id IS NOT NULL '
    'AND (SELECT lower(na.name) FROM accounts na '
    'WHERE na.id = transactions.account_id) '
    '= (SELECT lower(nb.name) FROM accounts nb '
    'WHERE nb.id = transactions.to_account_id)',
  );

  /// Hapus nama duplikat (case-insensitive), sisakan id terkecil.
  Future<void> _deleteDuplicateNames(String table) => customUpdate(
    'DELETE FROM $table WHERE id NOT IN '
    '(SELECT MIN(id) FROM $table GROUP BY lower(name))',
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
