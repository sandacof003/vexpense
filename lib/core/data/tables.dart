import 'package:drift/drift.dart';

import 'enums.dart';

/// Mata uang yang didukung aplikasi. `code` adalah primary key.
///
/// Drift generate data class `Currency` dari tabel ini.
class Currencies extends Table {
  TextColumn get code => text()();
  IntColumn get minorUnit => integer()();
  TextColumn get symbol => text()();

  @override
  Set<Column> get primaryKey => {code};
}

/// Akun (cash / bank / e-wallet). Tidak ada kolom `balance` — saldo selalu
/// dihitung dari ledger (`opening_balance` + transaksi).
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get currency => text().references(Currencies, #code)();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Kategori transaksi. `name` unik (case-insensitive).
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get type => textEnum<CategoryType>()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Transaksi = satu-satunya source of truth saldo.
///
/// Constraint penting (dari PRD §6):
/// - `amount > 0` (integer minor unit currency akun).
/// - transfer wajib `to_account_id`, tujuan != asal, `category_id` NULL.
/// - income/expense wajib `category_id` (tidak boleh NULL).
@TableIndex(name: 'idx_transactions_account_id', columns: {#accountId})
@TableIndex(name: 'idx_transactions_category_id', columns: {#categoryId})
@TableIndex(name: 'idx_transactions_date', columns: {#date})
@TableIndex(name: 'idx_transactions_to_account_id', columns: {#toAccountId})
@TableIndex(
  name: 'idx_transactions_date_category',
  columns: {#date, #categoryId},
)
@TableIndex(name: 'idx_transactions_date_account', columns: {#date, #accountId})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TransactionType>()();
  // ignore: recursive_getters
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('toAccountTransactions')
  IntColumn get toAccountId => integer().nullable().references(
    Accounts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get categoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get description => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => const [
    'CHECK (type IN (\'income\', \'expense\', \'transfer\'))',
    "CHECK (type != 'transfer' OR to_account_id IS NOT NULL)",
    "CHECK (type != 'transfer' OR to_account_id != account_id)",
    "CHECK (type != 'transfer' OR category_id IS NULL)",
    "CHECK (type = 'transfer' OR category_id IS NOT NULL)",
  ];
}

/// Kurs (display-only di MVP, untuk konversi dashboard ke IDR). `rate` adalah
/// REAL multiplier, bukan minor unit.
///
/// Primary key = pasangan (from, to) — natural key, sehingga `upsert` via
/// `insertOnConflictUpdate` menarget konflik pada pasangan mata uang (bukan id
/// autoincrement yang tidak ada).
class ExchangeRates extends Table {
  @ReferenceName('fromCurrencyRates')
  TextColumn get fromCurrency => text().references(Currencies, #code)();
  @ReferenceName('toCurrencyRates')
  TextColumn get toCurrency =>
      text().withDefault(const Constant('IDR')).references(Currencies, #code)();
  // ignore: recursive_getters
  RealColumn get rate => real().check(rate.isBiggerThanValue(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {fromCurrency, toCurrency};
}
