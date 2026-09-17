# ARCHITECTURE.md — V Expense

Dokumen ini mendeskripsikan **arsitektur yang BENAR-BENAR ADA** di codebase ini per
2026-09-17 (commit `29ff871`). Tujuannya dokumentasi, bukan redesign. Tidak ada
kode yang diubah, tidak ada dependency yang ditambah, tidak ada behavior yang
diubah saat dokumen ini dibuat.

Referensi proyek lain (di luar folder ini):
- `../PRD.md` (v0.4.1) — source of truth produk.
- `../AGENTS.md` — guardrail multi-agent proyek.
- `../wireframes/wireframe.html` — wireframe UI.

> Catatan pembacaan: setiap klaim di bawah ini diverifikasi dengan perintah nyata
> (lihat §17 Evidence). Klaim yang tidak bisa diverifikasi ditandai **UNKNOWN**,
> bukan ditebak.

---

## 1. Identitas proyek

| Item | Nilai | Sumber |
|---|---|---|
| Nama paket (pubspec) | `v_expense` | `pubspec.yaml` |
| Versi | `0.1.0-alpha.2+2` | `pubspec.yaml` |
| Dart SDK | `^3.8.0` | `pubspec.yaml` |
| Flutter (terpasang di VPS) | 3.32.0 stable | `flutter --version` |
| `applicationId` | `com.sandacof003.vexpense` | `android/app/build.gradle.kts` |
| `namespace` (Android) | `com.sandacof003.v_expense` | `android/app/build.gradle.kts` |
| `minSdk` | 26 | `android/app/build.gradle.kts` |
| Target platform | Android saja | `android/` ada; tidak ada `ios/`, `web/`, `linux/`, `macos/`, `windows/` |
| Remote git | `https://github.com/sandacof003/vexpense` (branch `main`, URL remote memuat token akses) | `git remote -v` |
| Status working tree | bersih di `main` | `git status --short` |
| CI | **tidak ada** (`.github/` tidak ada) | `ls .github` |
| `pubspec.lock` | di-track | `git ls-files` |

Total ukuran kode:

| Kategori | File | Baris |
|---|---|---|
| `lib/` hand-written (non-`.g.dart`) | 53 | 5.558 |
| `lib/` generated (`*.g.dart`) | 6 | 4.500 |
| `test/` | 14 | 4.561 |
| Total | 73 | 14.619 |

`flutter analyze` → **No issues found**. `flutter test` → **218 test pass**.
`dart format` → **20 file belum terformat** (repo belum format-clean; lihat §15-06).

### Riwayat commit di `main` (terbaru dulu)

```
29ff871 chore(release): bump versi 0.1.0-alpha.2 (FE-04 form transaksi)
a13ab7f fix(test): FE-04 updatedAt assertion anti-flaky (presisi ms) (t_c2c86d80)
4e84cd9 feat(fe): FE-04 form tambah & edit transaksi income/expense (#6)
b091da2 feat(fe): FE-06 manajemen akun & kategori (CRUD UI + picker warna/ikon) (#5)
b3d23b3 chore(release): section Download APK di README + versi 0.1.0-alpha.1
bde241b feat(be): BE-05 query agregasi laporan + exchange rate (#4)
6768d08 feat(fe): FE-02 formatter minor-unit, validasi form, AmountField (#3)
63fcfb2 feat(be): CSV import atomic + ledger foundation (#1)
f42ec80 feat: FE-01 app shell, onboarding, dark theme default (#2)
763a3a1 chore: hapus widget_test template (referensi MyApp lama)
70c7239 chore: scaffold Flutter v_expense (applicationId com.sandacof003.vexpense, minSdk 26)
```

### Branch lokal (banyak yang belum di-merge)

Merged ke `main`: `fe/fe-07-reports`, `feat/ui-mvp`.
Belum merged: `be/be-05-reports`, `be/csv-import`, `be/csv-import-rebased`,
`fe/fe-01-app-shell`, `fe/fe-02-formatters`, `fe/fe-04-transaction-form`,
`fe/fe-06-accounts-categories`, `fe/fe-08-import-csv`.

Branch yang ada di `origin`: `main`, `be/be-05-reports`, `be/csv-import`,
`fe/fe-01-app-shell`, `fe/fe-02-formatters`, `fe/fe-04-transaction-form`,
`fe/fe-06-accounts-categories` — jadi `fe/fe-08-import-csv`,
`be/csv-import-rebased`, `fe/fe-07-reports`, `feat/ui-mvp` **tidak ada di remote**
(walaupun `fe/fe-07-reports` & `feat/ui-mvp` sudah merged secara lokal).

---

## 2. Struktur direktori (aktual)

```
v_expense/
├── ARCHITECTURE.md              ← dokumen ini
├── AGENTS.md                    guardrail agent level subfolder
├── README.md                    ringkasan + link APK release
├── analysis_options.yaml        flutter_lints (default, tidak ada rule custom aktif)
├── pubspec.yaml / pubspec.lock
├── .gitignore / .metadata
├── android/                     namespace com.sandacof003.v_expense
│   ├── gradle.properties        daemon OFF, JVM heap 2 GB (dikunci; jangan diubah)
│   └── app/build.gradle.kts     applicationId com.sandacof003.vexpense, minSdk 26
├── build/                       artifact (gitignored)
├── lib/
│   ├── main.dart                entry point: SharedPreferences → ProviderScope → VExpenseApp
│   ├── app/
│   │   └── v_expense_app.dart   MaterialApp.router + AppTheme.dark (permanen)
│   ├── core/
│   │   ├── data/
│   │   │   ├── database.dart    AppDatabase (Drift), schemaVersion 2, migrasi, seed
│   │   │   ├── database.g.dart  GENERATED
│   │   │   ├── tables.dart      5 tabel + index + custom CHECK constraint
│   │   │   ├── enums.dart       TransactionType, CategoryType, AccountType
│   │   │   ├── daos/            5 DAO + 5 file *.g.dart (GENERATED)
│   │   │   │   ├── account_dao.dart
│   │   │   │   ├── category_dao.dart
│   │   │   │   ├── currency_dao.dart
│   │   │   │   ├── exchange_rate_dao.dart
│   │   │   │   └── transaction_dao.dart      + TransactionFilter, TransactionSort
│   │   │   ├── repositories/
│   │   │   │   ├── repository_contracts.dart  interface: Accounts/Categories/Transactions/DashboardData/CsvImport
│   │   │   │   ├── account_repository.dart    impl + DataException/DuplicateNameException/AccountInUseException
│   │   │   │   ├── category_repository.dart   impl + kebijakan fallback "Lainnya"
│   │   │   │   ├── transaction_repository.dart impl + ledger + agregasi
│   │   │   │   ├── currency_repository.dart   interface + impl (di file sendiri)
│   │   │   │   ├── dashboard_repository.dart  impl + class BalanceSummary
│   │   │   │   └── csv_import_repository.dart impl import CSV atomik
│   │   │   └── services/
│   │   │       └── currency_converter.dart    CurrencyConverter + convertMinorUnit()
│   │   ├── di/
│   │   │   └── providers.dart   SELURUH graph DI (DB, DAO→repo, stream provider)
│   │   ├── errors/
│   │   │   └── app_error.dart   AppError dkk + mapAppError() — TIDAK TERPAKAI (lihat §13-01)
│   │   ├── formatters/
│   │   │   ├── app_locale.dart      enum AppLocale (id/en)
│   │   │   ├── currency_format.dart CurrencyFormat + kDefaultCurrencyFormats
│   │   │   ├── money_formatter.dart formatMinor/format/parseMinor (integer, bukan double)
│   │   │   └── date_formatter.dart  DateStyle + DateFormatter (tanpa package intl)
│   │   ├── router/
│   │   │   └── app_router.dart  routerProvider (GoRouter) + redirect onboarding
│   │   ├── services/csv/        parser CSV murni Dart (tanpa Flutter/Drift)
│   │   │   ├── csv_encoding.dart      deteksi UTF-8 vs Windows-1252 + strip BOM
│   │   │   ├── csv_formats.dart       CsvNumberParser, CsvDateParser, kCurrencyMinorUnits
│   │   │   ├── csv_import_models.dart CsvImportErrorCode, CsvRowError, CsvImportResult/Summary/Report/Preview, csvDedupeHash()
│   │   │   ├── csv_import_service.dart CsvImportService + CsvImportOptions
│   │   │   └── csv_parser.dart        CsvImportParser (header wajib, validasi per baris)
│   │   ├── settings/
│   │   │   ├── currency.dart          enum AppCurrency
│   │   │   ├── settings_providers.dart onboardingCompletedProvider, defaultCurrencyProvider, sharedPreferencesProvider
│   │   │   └── settings_storage.dart   SettingsStorage (SharedPreferences)
│   │   ├── theme/
│   │   │   └── app_theme.dart   AppTheme.dark (satu-satunya tema)
│   │   ├── validators/
│   │   │   └── transaction_form_validators.dart
│   │   └── widgets/
│   │       ├── amount_field.dart           AmountField (prefix simbol currency)
│   │       └── amount_input_formatter.dart AmountInputFormatter (digit → grouping)
│   └── features/
│       ├── accounts/
│       │   ├── accounts_screen.dart       list akun (live stream) — route /accounts
│       │   ├── account_form_screen.dart   tambah/edit/hapus akun
│       │   └── domain/account_contract.dart  AccountDraft
│       ├── categories/
│       │   ├── categories_screen.dart       list per tipe — route /categories
│       │   ├── category_form_screen.dart    form + picker warna/ikon
│       │   ├── category_appearance.dart     palet warna + map ikon Material
│       │   └── domain/category_contract.dart CategoryDraft
│       ├── dashboard/
│       │   └── dashboard_screen.dart  PLACEHOLDER (currency + tombol nav + FAB quick add)
│       ├── onboarding/
│       │   └── onboarding_screen.dart pilih currency + simpan status — route /onboarding
│       ├── reports/
│       │   └── data/
│       │       ├── report_models.dart      CategoryExpense, ExpenseByCategoryReport, IncomeVsExpenseReport
│       │       └── reports_repository.dart agregasi chart (TIDAK ada screen-nya)
│       ├── settings/                       ⚠️ DIREKTORI KOSONG (0 file tracked)
│       ├── transactions/
│       │   ├── presentation/transaction_form_screen.dart  form income/expense
│       │   ├── providers/transaction_providers.dart       categoriesByTypeProvider + 2 provider use case
│       │   └── domain/
│       │       ├── transaction_use_cases.dart  Create/Edit/DeleteTransactionUseCase
│       │       └── money.dart                  class Money — TIDAK TERPAKAI (§13-02)
│       └── transfers/
│           └── transfer_use_cases.dart  Create/DeleteTransferUseCase (tanpa UI)
└── test/                        14 file, 218 test (lihat §14)
```

Tidak ada folder `assets/`, `l10n/`, `i18n/`, `docs/`, `.github/`, `integration_test/`.

---

## 3. Dependencies

### Runtime (`pubspec.yaml`)

| Paket | Versi | Dipakai di |
|---|---|---|
| `flutter` | SDK | seluruh UI |
| `cupertino_icons` | ^1.0.8 | tidak direferensikan di `lib/` |
| `csv` | ^6.0.0 | `core/services/csv/csv_parser.dart` |
| `drift` | ^2.31.0 | `core/data/**` |
| `flutter_riverpod` | ^2.6.1 | DI + UI (`ConsumerWidget`/`ConsumerStatefulWidget`) |
| `go_router` | ^14.2.0 | `core/router/app_router.dart` |
| `shared_preferences` | ^2.3.2 | `core/settings/settings_storage.dart` |
| `sqlite3_flutter_libs` | ^0.5.42 | runtime native SQLite (dipakai via drift) |
| `path` | ^1.9.1 | `core/data/database.dart` (join path file DB) |
| `path_provider` | ^2.1.5 | `core/data/database.dart` (`getApplicationDocumentsDirectory`) |

### Dev

| Paket | Versi | Catatan |
|---|---|---|
| `flutter_test` | SDK | semua test |
| `flutter_lints` | ^5.0.0 | diaktifkan lewat `analysis_options.yaml` (`include: package:flutter_lints/flutter.yaml`, tanpa rule custom) |
| `drift_dev` | ^2.31.0 | codegen `*.g.dart` |
| `build_runner` | ^2.15.1 | menjalankan codegen |

**Tidak ada** `fl_chart`, `file_picker`, `intl`, `riverpod_generator`,
`flutter_hooks`, `mockito`, `mocktail`, `freezed`, `json_serializable`, `get_it`,
`provider`. Artinya: chart belum punya library, import file belum punya picker,
lokalisasi ditulis tangan, dan tidak ada framework mocking.

> ⚠️ `README.md` baris 23, `AGENTS.md` baris 9 & 25, dan `../AGENTS.md` baris 14
> **menyebut `fl_chart` dan `file_picker`** — keduanya tidak ada di
> `pubspec.yaml` proyek ini. Lihat §13-03.

---

## 4. Layering & dependency flow

Lapisan yang benar-benar ada:

```
UI (lib/features/**/**_screen.dart, lib/app)
 │  watch/read
 ▼
Riverpod providers (lib/core/di/providers.dart, lib/core/settings/settings_providers.dart,
                   lib/features/transactions/providers/transaction_providers.dart)
 │
 ├──────────────► Repository (lib/core/data/repositories/**, lib/features/reports/data/)
 │                  │
 │                  ▼
 │                DAO (lib/core/data/daos/)  ──► Drift Query Builder
 │                  │
 │                  ▼
 │                AppDatabase (lib/core/data/database.dart) + tables.dart
 │                  │
 │                  ▼
 │                SQLite native (file `v_expense.sqlite`)
 │
 └──────────────► Use case (lib/features/transactions/domain, lib/features/transfers)
                    │  ⚠️ memakai AppDatabase LANGSUNG (lewati repository)
                    ▼
                  AppDatabase.transactionDao / accountDao
```

Aturan dependensi yang berlaku hari ini:

- `core/data/**` tidak pernah mengimpor `features/**` — **kecuali** manifest
  `core/di/providers.dart` yang mengimpor `features/reports/data/reports_repository.dart`
  dan `core/errors/app_error.dart` yang mengimpor
  `core/data/repositories/account_repository.dart` (§13-04).
- `core/services/csv/**` bebas dari Flutter & Drift (pure Dart) — satu-satunya
  bagian yang sengaja tidak coupled.
- UI mengakses DB **hanya** lewat provider → repository. Widget tidak pernah
  membuat DAO/`AppDatabase` sendiri. (Satu penyimpangan: form transaksi memakai
  use case, bukan `TransactionsRepository`.)
- Tidak ada lapisan "data source"/"remote API". Aplikasi 100% offline.

### Alur data utama (baca)

```
SQLite ──Drift stream──► TransactionDao.watchFiltered()
   ──► TransactionRepository.watchFiltered()
   ──► transactionsProvider (StreamProvider.autoDispose)
   ──► widget (ref.watch)
```
⚠️ `transactionsProvider` saat ini **tidak dipakai widget mana pun** (§13-05).

### Alur data utama (tulis transaksi income/expense)

```
TransactionFormScreen._save()
 ├── validasi: MoneyFormatter.parseMinor → TransactionFormValidators.validateAmount
 └── read(createTransactionProvider) → CreateTransactionUseCase.call()
        └── AppDatabase.transaction { transactionDao.insert(...) }   ← 1 DB transaction
 (mode edit) read(editTransactionProvider) → EditTransactionUseCase.call()
        └── AppDatabase.transaction { getById → validate → transactionDao.replace() }
```

### Alur data tulis akun/kategori

```
AccountFormScreen  → read(accountRepositoryProvider)  → AccountRepository
   → _accountDao.getByName() (cek duplikat) → _accountDao.insert/replace/remove
   → delete: _db.transaction { getByAccount() → remove() }  (RESTRICT)

CategoryFormScreen → read(categoryRepositoryProvider) → CategoryRepository
   → delete: cari fallback "Lainnya" → _db.transaction { reassignCategory() → remove() }
```

### Alur data import CSV (end-to-end)

```
bytes (dari file picker) ─ UNKNOWN: pemanggilnya belum ada (§13-06)
 └──► CsvImportRepository.preview()/importBytes()
        ├── CurrencyDao.getAll()  → inject supportedCurrencyCodes + minorUnitsByCurrency
        ├── CsvImportService.importBytes()
        │     ├── CsvEncodingDetector.detect()      UTF-8 strict → fallback Windows-1252, strip BOM
        │     ├── CsvImportParser.parse()            deteksi delimiter, cek header, validasi per baris
        │     │     ├── CsvDateParser.parse()        5 format tanggal didukung
        │     │     └── CsvNumberParser.parse()      skala per minor unit currency, aritmetika integer
        │     └── dedupe via csvDedupeHash()         (duplikat dalam file)
        ├── _existingHashes()  → hash transaksi existing dari DB (pakai csvDedupeHash yang SAMA)
        └── AppDatabase.transaction {                ← SATU transaksi untuk seluruh batch
              per baris: _resolveCategory() → _resolveAccount() → transactionDao.insert()
            }
```

---

## 5. State management

- **Riverpod 2.x (`flutter_riverpod`), tanpa codegen.** Semua provider ditulis
  manual: `Provider`, `StreamProvider.autoDispose`, `FutureProvider.autoDispose`,
  `NotifierProvider`, `Provider.autoDispose.family`.
- Tidak ada `riverpod_annotation`/`riverpod_generator`, tidak ada `Notifier` async,
  tidak ada `AsyncNotifier`. Notifier yang ada (`OnboardingCompletedNotifier`,
  `DefaultCurrencyNotifier`) berbasis `Notifier<T>` sinkron yang membaca nilai awal
  dari `SettingsStorage` di `build()`.
- `ProviderScope` di-root sekali di `main.dart`, dengan override
  `sharedPreferencesProvider`.
- Tidak ada `Consumer`/`ref.listen`. Pola akses: `ref.watch` untuk baca reaktif di
  `build()`, `ref.read` untuk aksi di callback.
- Pemisahan file provider:
  - `core/di/providers.dart` — semua provider DB/repo/stream.
  - `core/settings/settings_providers.dart` — provider basis (SharedPreferences,
    SettingsStorage, onboarding, currency default).
  - `features/transactions/providers/transaction_providers.dart` — provider khusus
    form transaksi (filter kategori per tipe + use case).
- Konsistensi `autoDispose` **campur**: `transactionsProvider`, `accountsProvider`,
  `categoriesProvider`, `dashboardBalanceProvider`, `categoriesByTypeProvider` pakai
  `autoDispose`; provider repository (mis. `accountRepositoryProvider`) tidak.
- **State lokal yang signifikan**: form (`TransactionFormScreen`, `AccountFormScreen`,
  `CategoryFormScreen`) memakai `ConsumerStatefulWidget` + `setState` + `TextEditingController`.
  Tidak ada state management form khusus.

---

## 6. Dependency injection

DI dilakukan dengan Riverpod sebagai service locator, seluruh graph ditulis manual
di `lib/core/di/providers.dart`. Tidak ada `get_it`, `injectable`, atau annotation.

| Provider | Tipe | Dependensi | Dipakai di `lib/` di luar file definisinya |
|---|---|---|---|
| `appDatabaseProvider` | `Provider<AppDatabase>` | — (bikin `AppDatabase()`, `ref.onDispose(close)`) | **0** (hanya internal DI) |
| `accountRepositoryProvider` | `Provider<AccountsRepository>` (nilai nyata: `AccountRepository`) | `appDatabaseProvider` | 2 (`accounts_screen`, `account_form_screen`) |
| `categoryRepositoryProvider` | `Provider<CategoriesRepository>` (nilai nyata: `CategoryRepository`) | `appDatabaseProvider` | 2 (`categories_screen`/`category_form_screen`) |
| `transactionRepositoryProvider` | `Provider<TransactionsRepository>` | `appDatabaseProvider` | **0** |
| `currencyRepositoryProvider` | `Provider<CurrenciesRepository>` | `appDatabaseProvider` | **0** |
| `dashboardRepositoryProvider` | `Provider<DashboardData>` | `appDatabaseProvider`, `transactionRepositoryProvider`, `CurrencyConverter` | **0** |
| `reportsRepositoryProvider` | `Provider<ReportsRepository>` | `appDatabaseProvider`, `CurrencyConverter` | **0** |
| `csvImportServiceProvider` | `Provider<CsvImportService>` | — | **0** |
| `csvImportRepositoryProvider` | `Provider<CsvImportRepository>` | `appDatabaseProvider`, `csvImportServiceProvider`, DAO | **0** (dipakai 1 test) |
| `transactionsProvider` | `StreamProvider.autoDispose<List<Transaction>>` | `transactionRepositoryProvider.watchFiltered(TransactionFilter())` | **0** |
| `accountsProvider` | `StreamProvider.autoDispose<List<Account>>` | `accountRepositoryProvider.watchAll()` | 4 |
| `categoriesProvider` | `StreamProvider.autoDispose<List<Category>>` | `categoryRepositoryProvider.watchAll()` | 2 |
| `dashboardBalanceProvider` | `FutureProvider.autoDispose<BalanceSummary>` | `dashboardRepositoryProvider.totalBalance('IDR')` | **0 di seluruh repo** |
| `categoriesByTypeProvider` | `Provider.autoDispose.family<List<Category>, TransactionType>` | `categoriesProvider` | 2 |
| `createTransactionProvider` / `editTransactionProvider` | `Provider<UseCase>` | `appDatabaseProvider` | 1 masing-masing |
| `sharedPreferencesProvider` | `Provider<SharedPreferences>` | — (wajib di-override) | 1 (`main.dart`) |
| `settingsStorageProvider` | `Provider<SettingsStorage>` | `sharedPreferencesProvider` | 0 (internal) |
| `onboardingCompletedProvider` | `NotifierProvider<..., bool>` | `settingsStorageProvider` | 3 (router, onboarding, test) |
| `defaultCurrencyProvider` | `NotifierProvider<..., AppCurrency>` | `settingsStorageProvider` | 2 (onboarding, dashboard) |

Catatan: DAO **tidak** punya provider sendiri. DAO di-instantiate inline di dalam
provider repository (`AccountDao(db)`, dst.), dan `CurrencyConverter` di-instantiate
inline di `dashboardRepositoryProvider` **dan** `reportsRepositoryProvider`
(dua instance berbeda).

Pola override untuk test: `sharedPreferencesProvider.overrideWithValue(prefs)` dan
`accountRepositoryProvider.overrideWithValue(fake)` (lihat `test/providers_test.dart`).

---

## 7. Database layer

### 7.1 Koneksi

- `AppDatabase()` → `_openConnection()` → `LazyDatabase` → file
  `v_expense.sqlite` di `getApplicationDocumentsDirectory()`, dibuka via
  `NativeDatabase.createInBackground(file)`.
- `AppDatabase.forTesting(QueryExecutor)` dipakai unit test dengan
  `NativeDatabase.memory()` atau file temporer.
- `MigrationStrategy.beforeOpen` mengeksekusi `PRAGMA foreign_keys = ON` untuk
  seluruh sesi.

### 7.2 Tabel (`lib/core/data/tables.dart`)

| Tabel | Kolom | Kunci / constraint |
|---|---|---|
| `currencies` | `code` (TEXT), `minor_unit` (INT), `symbol` (TEXT) | PK = `code` |
| `accounts` | `id` (PK autoincrement), `name`, `type` (`textEnum<AccountType>`), `currency` → FK `currencies.code`, `opening_balance` (INT, default 0), `created_at` (DATETIME, default now) | **tidak ada kolom `balance`** |
| `categories` | `id` (PK), `name` (TEXT unique), `type` (`textEnum<CategoryType>`), `color` (TEXT nullable), `icon` (TEXT nullable), `created_at` | `name` unique |
| `transactions` | `id` (PK), `type` (`textEnum<TransactionType>`), `amount` (INT), `account_id` → FK `accounts.id` RESTRICT, `to_account_id` → FK `accounts.id` RESTRICT nullable, `category_id` → FK `categories.id` RESTRICT nullable, `description` nullable, `date`, `created_at`, `updated_at` | 5 `customConstraints` (lihat bawah) |
| `exchange_rates` | `from_currency` → FK `currencies.code`, `to_currency` → FK `currencies.code` default `'IDR'`, `rate` (REAL), `updated_at` | **PK = (`from_currency`,`to_currency`)** — natural key, itu sebabnya `upsert` pakai `insertOnConflictUpdate` |

Custom CHECK di `transactions`:

```sql
CHECK (type IN ('income','expense','transfer'))
CHECK (type != 'transfer' OR to_account_id IS NOT NULL)
CHECK (type != 'transfer' OR to_account_id != account_id)
CHECK (type != 'transfer' OR category_id IS NULL)
CHECK (type = 'transfer'   OR category_id IS NOT NULL)
```

Plus `amount > 0` sebagai `check()` kolom.

Enum disimpan sebagai **TEXT berisi nama entry** (`textEnum`), jadi rename entry
enum = breaking change schema.

### 7.3 Index

Dari `@TableIndex` di `tables.dart`:
`idx_transactions_account_id`, `idx_transactions_category_id`,
`idx_transactions_date`, `idx_transactions_to_account_id`,
`idx_transactions_date_category`, `idx_transactions_date_account`.

Dibuat manual di `database.dart` (DDL ekspresi, tidak bisa dideklarasikan di Drift):

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_name_lower   ON accounts (lower(name))
CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_name_lower ON categories (lower(name))
```

### 7.4 Versi & migrasi

- `_schemaVersion = 2` (`const int` privat di `database.dart`).
- **v1 → v2**: menambahkan unique index `lower(name)`. Urutan langkah di
  `_mergeCaseInsensitiveNameDuplicates()` sengaja ketat:
  1. `_renameCurrencyMismatchedDuplicates()` — akun dengan nama sama tapi currency
     berbeda **di-rename** (`cash (2)`), bukan di-merge (kalau di-merge, nominal USD
     jadi bermakna IDR = korupsi diam-diam).
  2. `_deleteTransfersBetweenSameNameAccounts()` — dibuang dulu, karena setelah
     repoint kedua sisi transfer jatuh ke akun yang sama dan CHECK
     `to_account_id != account_id` akan menolak UPDATE; throw di dalam `onUpgrade`
     membuat `user_version` tidak pernah naik → DB gagal dibuka selamanya.
  3. `_repointToKeeper()` untuk `transactions.account_id` dan `to_account_id`.
  4. `_deleteDuplicateNames('accounts')`.
  5. `_repointToKeeper()` untuk `transactions.category_id` + `_deleteDuplicateNames('categories')`.
- **Tidak ada** `stepByStep`/`onUpgradeStep`. Tidak ada `validateDatabaseSchema`.
- Tidak ada downgrade / `beforeOpen` data-fix selain PRAGMA.

### 7.5 Seed

Dijalankan di `onCreate` dan **idempotent** kalau DB dibuka ulang:

- `_seedCurrencies`: IDR 0 `Rp`, USD 2 `$`, JPY 0 `¥`, USDT 6 `₮`, SGD 2 `S$`,
  MYR 2 `RM`, THB 2 `฿` — via `insertAll(..., mode: insertOrIgnore)`.
- `_seedCategories` (11): income → `Gaji`, `Bonus`, `Bisnis / Lainnya`;
  expense → `Makan & Minum`, `Transport`, `Belanja`, `Tagihan & Utilitas`,
  `Hiburan`, `Kesehatan`, `Pendidikan`, `Lainnya` — dicek `getByName` dulu.
- **`exchange_rates` TIDAK di-seed** dan tidak ada jalur tulis rate dari UI.
  Efeknya: konversi mata uang lintas currency praktis selalu gagal kecuali via
  shortcut `from == to` di `CurrencyConverter`. Lihat §13-08.

---

## 8. DAO layer

Semua DAO adalah `DatabaseAccessor<AppDatabase>` dengan `@DriftAccessor` dan
memakai generated mixin `_$<Name>DaoMixin`. DAO tidak memanggil DAO lain.

| DAO | Method | Catatan |
|---|---|---|
| `AccountDao` | `getAll`, `watchAll`, `getById`, `getByName` (case-insensitive `lower()`), `insert`, `replace`, `remove` | urut `name` ASC |
| `CategoryDao` | `getAll`, `watchAll`, `getByType`, `getById`, `getByName`, `insert`, `replace`, `remove` | urut `name` ASC |
| `CurrencyDao` | `getAll`, `watchAll`, `getByCode`, `upsert` | urut `code` ASC |
| `ExchangeRateDao` | `getAll`, `watchAll`, `getPair`, `upsert` | satu-satunya baca `getPair` |
| `TransactionDao` | `getFiltered`, `watchFiltered`, `getById`, `getByAccount`, `getIncomingTransfers`, `countByAccount`, `countByCategory`, `reassignCategory`, `insert`, `replace`, `remove`, `count`, `totalIncome`, `totalExpense`, `expenseByCategory` | + kelas `TransactionFilter` & enum `TransactionSort {dateDesc, dateAsc, amountDesc, amountAsc}` |

- `TransactionFilter`: `type`, `accountId`, `categoryId`, `fromDate` (inklusif),
  `toDate` (inklusif), `search` (LIKE case-insensitive pada `description`).
- Query builder dipakai (`select(...)`, `selectOnly(...)`), **bukan raw SQL** —
  kecuali migrasi di `database.dart` yang memakai `customStatement`/`customUpdate`/`customSelect`.
- DAO yang belum dipakai dari manapun di `lib/`: `countByAccount`, `countByCategory`,
  `ExchangeRateDao.getAll/watchAll/upsert`, `CurrencyDao.watchAll/upsert`,
  `CategoryDao.getByType` (dipakai 5× termasuk repository).

---

## 9. Repository layer

### 9.1 Kontrak

`lib/core/data/repositories/repository_contracts.dart` mendefinisikan
`abstract interface class`:

| Interface | Anggota |
|---|---|
| `AccountsRepository` | `getAll`, `watchAll`, `getById`, `create`, `delete` |
| `CategoriesRepository` | `getAll`, `watchAll`, `getByType`, `getById`, `create`, `delete` |
| `TransactionsRepository` | `getFiltered`, `watchFiltered`, `getById`, `add`, `transfer`, `delete`, `balanceForAccount`, `totalIncome`, `totalExpense` |
| `DashboardData` | `totalBalance(String targetCurrency)`, `recentTransactions(int limit)` |
| `CsvImportRepository` | `preview(...)`, `importBytes(...)` |

`CurrenciesRepository` **tidak** ada di file kontrak itu — ia didefinisikan di
`currency_repository.dart` (§13-07).

### 9.2 Implementasi

| File | Kelas | Perilaku penting |
|---|---|---|
| `account_repository.dart` | `AccountRepository` + `sealed class DataException`, `AccountInUseException`, `DuplicateNameException` | `create` cek duplikat nama lalu insert; `update(account, {newName})` **tidak ada di interface**; `delete` di dalam `_db.transaction`, tolak kalau `getByAccount(id)` tidak kosong |
| `category_repository.dart` | `CategoryRepository` | `_findFallback(type, excludeId)` pilih `Lainnya` se-tipe (atau kategori pertama se-tipe); `delete` = `transactionDao.reassignCategory` + `remove` dalam satu DB transaction; lempar `StateError` kalau tidak ada fallback |
| `transaction_repository.dart` | `TransactionRepository` | `add()` validasi `type != transfer` & `amount > 0` lalu insert **tanpa** pembungkus `_db.transaction` (§13-09). `transfer()` validasi akun ada & currency sama, lalu insert. `update()` & `delete()` dibungkus `_db.transaction`. `balanceForAccount()` = `openingBalance + Σ(income) − Σ(expense) − Σ(transfer keluar) + Σ(transfer masuk)`, dihitung di Dart dari hasil DAO. `expenseByCategory()` **tidak ada di interface** |
| `dashboard_repository.dart` | `DashboardRepository` + `class BalanceSummary` | `totalBalance`: loop semua akun → `balanceForAccount` → `CurrencyConverter.convert` → jumlahkan; akun tanpa rate dikumpulkan ke `missingRateCurrencies` (tidak dipakai rate palsu). `recentTransactions(limit)`: ambil semua lalu `.take(limit)` di memori |
| `currency_repository.dart` | `CurrenciesRepository` (interface + impl di satu file) | hanya `getAll`, `getByCode`; `const` constructor; tidak dipakai UI |
| `csv_import_repository.dart` | `CsvImportRepositoryImpl` | lihat §11 |
| `features/reports/data/reports_repository.dart` | `ReportsRepository` | `expenseByCategory`, `incomeVsExpense` — konversi ke `targetCurrency` (default IDR), transfer dikecualikan, rate hilang dicatat bukan ditebak |

### 9.3 Konvensi exception

Tidak ada satu hierarki error yang dipakai konsisten:

- `DataException`/`DuplicateNameException`/`AccountInUseException` →
  didefinisikan **di dalam** `account_repository.dart`, di-`show` dari
  `category_repository.dart` dan `category_form_screen.dart`.
- `ArgumentError`/`StateError` → dipakai di repository & use case (validasi domain).
- `AppError`/`ValidationError`/`ConstraintError`/`StorageError`/`UnknownAppError` +
  `mapAppError()` → ada di `core/errors/app_error.dart` tapi **tidak dipakai**.
- UI menangkap exception spesifik di beberapa tempat
  (`DuplicateNameException`, `AccountInUseException`, `StateError`) dan menampilkan
  `$e` mentah di tempat lain (`'Gagal menyimpan: $e'`).

---

## 10. Domain / use case layer

Hanya ada **dua** file use case, keduanya memakai `AppDatabase` langsung
(bukan repository):

`lib/features/transactions/domain/transaction_use_cases.dart`
- `CreateTransactionUseCase.call({type, amount, accountId, categoryId, date, description})`
  → tolak `transfer`, tolak `amount <= 0`, lalu `_db.transaction { insert; getById }`.
- `EditTransactionUseCase.call(Transaction updated)`
  → `_db.transaction { getById (harus ada); _validate; replace(copyWith(updatedAt: now)); getById }`.
- `DeleteTransactionUseCase.call(int id)` → idempotent (`null` = no-op), tolak transfer.

`lib/features/transfers/transfer_use_cases.dart`
- `CreateTransferUseCase.call({fromAccountId, toAccountId, amount, date, description})`
  → tolak akun sama, `amount <= 0`, akun tidak ada, currency beda; satu baris
  `transactions` type `transfer` (`accountId` = asal, `toAccountId` = tujuan,
  `categoryId` absent), di dalam satu DB transaction.
- `DeleteTransferUseCase.call(int id)` → tolak kalau bukan transfer.

Keduanya + `class Money` berada di dalam folder `features/`, tapi konseptual
domain → ini satu-satunya tempat logika domain ditulis terpisah dari repository.

---

## 11. Feature / UI layer

Status setiap feature (apa yang benar-benar terhubung ke DB):

| Feature | Screen | Route | Baca DB | Tulis DB | Status |
|---|---|---|---|---|---|
| onboarding | `OnboardingScreen` | `/onboarding` | SharedPreferences | SharedPreferences | **jalan** |
| dashboard | `DashboardScreen` | `/dashboard` | hanya `defaultCurrencyProvider` | — | **placeholder** (masih menampilkan teks "Data transaksi menyusul") |
| accounts | `AccountsScreen`, `AccountFormScreen` | `/accounts` + push | `accountsProvider` | `AccountRepository` | CRUD **jalan** |
| categories | `CategoriesScreen`, `CategoryFormScreen` | `/categories` + push | `categoriesProvider` | `CategoryRepository` | CRUD **jalan** |
| transactions | `TransactionFormScreen` | push (FAB dashboard) | `accountsProvider`, `categoriesByTypeProvider` | use case create/edit | form **jalan**; **list transaksi belum ada** |
| transfers | — | — | — | — | **belum ada UI** (use case ada) |
| reports | — | — | `ReportsRepository` (via provider) | — | **belum ada UI**, `fl_chart` belum jadi dependency |
| settings / import CSV | — | — | — | `CsvImportRepository` (via provider) | **belum ada UI**; folder `lib/features/settings/` kosong |

Pola UI yang konsisten:
- Screen yang butuh DB = `ConsumerWidget`; yang butuh state lokal =
  `ConsumerStatefulWidget` + `setState`.
- Widget diberi `Key` string yang stabil untuk test
  (mis. `Key('transaction.form.save')`, `Key('accounts.item.${account.id}')`).
- Semua teks UI berbahasa Indonesia. Tidak ada lokalisasi formal.
- Tema: hanya `AppTheme.dark` (`ThemeMode.dark` permanen), Material 3.

Navigasi campur (§13-10):
- `context.push()` / `context.go()` (go_router) untuk `/accounts`, `/categories`, `/dashboard`.
- `Navigator.of(context).push(MaterialPageRoute(...))` untuk semua form
  (transaksi, akun, kategori).

---

## 12. Routing / navigation

File: `lib/core/router/app_router.dart` — `routerProvider = Provider<GoRouter>`.

| Path | Builder |
|---|---|
| `/` | `SizedBox.shrink()` (dilewati redirect) |
| `/onboarding` | `OnboardingScreen` |
| `/dashboard` | `DashboardScreen` |
| `/accounts` | `AccountsScreen` (`AccountsScreen.path`) |
| `/categories` | `CategoriesScreen` (`CategoriesScreen.path`) |

- `redirect` dibaca dengan `ref.read(onboardingCompletedProvider)` supaya router
  tidak di-recreate saat state berubah. Logika:
  - `completed == true` → `/onboarding` dan `/` dialihkan ke `/dashboard`, path lain lolos.
  - `completed == false` → apa pun selain `/onboarding` dialihkan ke `/onboarding`.
- Tidak ada `ShellRoute`/`StatefulShellRoute`, tidak ada nested route, tidak ada
  route guard berbasis auth, tidak ada deep link `:id`.
- Tidak ada route untuk reports, list transaksi, transfer, settings/import CSV.
- Parameter tidak pernah dikirim via path/query — data objek diteruskan sebagai
  argumen constructor widget (`AccountFormScreen(account: ...)`,
  `TransactionFormScreen(existing: ...)`) melalui `MaterialPageRoute`.

---

## 13. Known Architectural Issues

Severity: 🔴 menyangkut uang/data · 🟠 menyangkut struktur/konsistensi ·
🟡 kebersihan/dead code.

### 🟠 A1 — Dua jalur tulis transaksi yang paralel dan tidak identik
`TransactionsRepository.add/transfer/update/delete` **dan**
`CreateTransactionUseCase`/`EditTransactionUseCase`/`DeleteTransactionUseCase`/
`CreateTransferUseCase`/`DeleteTransferUseCase` sama-sama ada, sama-sama menulis
ke `transactions`. UI memakai use case; repository tidak dipakai UI sama sekali.
Perilakunya juga tidak identik: use case membungkus semua tulis dengan
`_db.transaction`, `TransactionRepository.add()` tidak. Pilih satu jalur sebelum
menambah fitur baru, karena bug harus diperbaiki di dua tempat.

### 🟠 A2 — `repository_contracts.dart` bergantung pada file implementasi
`repository_contracts.dart` mengimpor `dashboard_repository.dart` (untuk
`BalanceSummary`) — arah dependensi terbalik untuk sebuah file kontrak.

### 🟠 A3 — `core/` mengimpor `features/`
`core/di/providers.dart` mengimpor `features/reports/data/reports_repository.dart`.
`ReportsRepository` adalah satu-satunya repository yang tinggal di dalam
`features/`, sedangkan repository lain di `core/data/repositories/`. Dua lokasi
repository = dua tempat untuk dicari.

### 🟠 A4 — Dokumentasi stack menyimpang dari `pubspec.yaml`
`README.md`, `AGENTS.md`, dan `../AGENTS.md` menyebut `fl_chart` dan `file_picker`
sebagai bagian stack. Keduanya tidak ada di `pubspec.yaml`. `README.md` juga
menyebut `lib/features/transactions/` = "Transaksi list + form" (list tidak ada)
dan `lib/features/settings/` = "Pengaturan + import CSV" (folder kosong).

### 🟠 A5 — Provider yatim: data layer sudah jadi tapi tidak tersambung ke UI
Nol referensi di `lib/` di luar file definisinya untuk:
`transactionRepositoryProvider`, `currencyRepositoryProvider`,
`dashboardRepositoryProvider`, `reportsRepositoryProvider`,
`csvImportServiceProvider`, `csvImportRepositoryProvider`, `transactionsProvider`,
dan `dashboardBalanceProvider` (nol referensi di **seluruh repo**).
Artinya: import CSV (BE lengkap + 16 test), chart report (12 test), dan saldo
dashboard sudah berfungsi di level test tapi belum bisa dijangkau user.

### 🟠 A6 — `class Money` tidak terpakai
`lib/features/transactions/domain/money.dart` hanya mereferensikan dirinya sendiri
(3 refs). Nilai uang direpresentasikan sebagai `int` minor unit di seluruh kode.

### 🟠 A7 — `core/errors/app_error.dart` tidak terpakai
`AppError`/`ValidationError`/`ConstraintError`/`StorageError`/`UnknownAppError` dan
`mapAppError()` tidak dipanggil dari mana pun (8 refs, semuanya di dalam file itu
sendiri). Akibatnya error mapping tidak seragam: sebagian UI menampilkan `$e`
mentah, sebagian menangkap exception spesifik dari `account_repository.dart`.

### 🟡 A8 — `features/settings/` kosong
Direktori ada di filesystem, tapi **0 file tracked** di git. Berpotensi
membingungkan agent berikutnya (terlihat seperti "belum diisi", padahal belum
pernah ada isinya).

### 🟠 A9 — `exchange_rates` tidak punya sumber data
Tabel ada, DAO ada, `CurrencyConverter` ada, UI multi-currency ada — tapi tidak ada
seed, tidak ada jalur tulis dari UI, dan tidak ada jalur fetch rate. Satu-satunya
konversi yang benar-benar berhasil adalah `from == to`. Akibatnya
`DashboardRepository.totalBalance('IDR')` akan selalu melaporkan
`missingRateCurrencies` begitu ada akun non-IDR, dan `ReportsRepository` melewati
transaksi akun tersebut (`isComplete == false`). Desain ini eksplisit
("jangan pakai rate palsu"), tapi artinya fitur multi-currency belum usable
end-to-end. UNKNOWN: siapa/apa yang seharusnya mengisi rate.

### 🟠 A10 — Semantik zona waktu pada kolom `transactions.date` tidak seragam
`CsvImportRepository` menulis `date` sebagai date-only **UTC**
(`CsvDateParser` → `DateTime.utc(...)`) dan dedupe hash-nya **wajib** `.toUtc()`
untuk tetap cocok. Sedangkan `TransactionFormScreen` menulis `DateTime.now()` (waktu
**lokal**), dan `TransactionFilter.fromDate/toDate` membandingkan `DateTime` apa
adanya. Ini bisa membuat satu transaksi jatuh di hari yang berbeda antara input
manual vs hasil import, dan filter tanggal bisa meleset di timezone non-UTC.

### 🟠 A11 — `TransactionRepository.add()` tidak dibungkus `_db.transaction`
Doc comment-nya berbunyi "Validasi + insert dalam 1 transaksi DB", tapi
implementasinya memanggil `_transactionDao.insert()` langsung tanpa
`_db.transaction`. Terlihat seperti niat yang tidak terealisasi. Tidak berbahaya
untuk satu insert, tapi menyesatkan dan tidak konsisten dengan `add()` sesama
(`update`, `delete`, `transfer` di use case).

### 🟠 A12 — Repository interface tidak mencerminkan implementasi
Method yang ada di implementasi tapi tidak di interface:
`AccountRepository.update`, `CategoryRepository.update`,
`TransactionRepository.update` & `expenseByCategory`, semua method
`ReportsRepository`. Akibatnya UI melakukan **cast** ke tipe konkret
(`(repo as AccountRepository).update(...)`, `(repo as CategoryRepository).update(...)`)
— cast itu akan gagal kalau suatu saat provider di-override dengan fake yang
mengimplementasikan interface saja.

### 🟡 A13 — Repo belum `dart format`-clean
`dart format --set-exit-if-changed lib test` melaporkan 20 file akan berubah,
walaupun `../AGENTS.md` menulis "Format kode: `dart format`". Tidak ada CI juga
(`.github/` tidak ada), jadi tidak ada gerbang otomatis untuk analyze/test/format.

### 🟡 A14 — Branch lokal menumpuk, sebagian tidak ada di remote
8 branch lokal belum merged ke `main`; `fe/fe-08-import-csv`,
`be/csv-import-rebased`, `fe/fe-07-reports`, `feat/ui-mvp` tidak ada di `origin`.
Ini menyulitkan penentuan "source of truth" kalau bukan `main`.

### 🟠 A15 — Ketidakcocokan `namespace` vs `applicationId`
`android/app/build.gradle.kts` menetapkan `namespace = "com.sandacof003.v_expense"`
sedangkan `applicationId = "com.sandacof003.vexpense"`. Berfungsi, tapi mudah jadi
sumber bug saat menambah plugin/izin yang mengacu package name.

### 🟠 A16 — Repo release di-sign dengan debug key
`buildTypes.release { signingConfig = signingConfigs.getByName("debug") }` —
APK rilis saat ini tidak layak Play Store (sudah dicatat di README, tapi tetap
sebuah utang).

### 🔴 A17 — Repo proyek kembar dengan remote yang sama
Direktori sibling `../v_expense_ui` (akun remote juga
`sandacof003/vexpense`) masih ada, berada di commit `763a3a1` dengan
**3 file modified yang belum di-commit** (`lib/features/dashboard/dashboard_screen.dart`,
`pubspec.yaml`, `pubspec.lock`) dan dependency berbeda
(`flutter_riverpod ^3.3.2`, `fl_chart ^1.1.0`, `intl ^0.20.2`, `file_picker ^11.0.3`).
Juga memuat `AGENTS.md` yang isinya menduplikasi AGENTS.md `v_expense`.
Risiko: `git push` dari folder yang salah bisa menimpa `main`. Perlu keputusan
eksplisit: hapus, atau jadikan sumber UI yang sah (dan pindahkan dependency).

### 🟡 A18 — Tanggal `ExchangeRates.rate` bertipe REAL
Kurs disimpan sebagai `double` dan hasil konversi dibulatkan (`scaled.round()`).
Ini **konsisten** dengan desain "rate = display-only, bukan nilai uang"
(nilai uang selalu integer minor unit), jadi bukan bug — tapi setiap agregasi
lintas currency mengandung pembulatan, dan akumulasi pembulatan itu tidak
dites. Ditandai agar tidak ada yang menganggap angka agregat multi-currency eksak.

### 🟠 A19 — `dashboard_repository.recentTransactions(limit)` mengambil semua baris
Implementasinya memanggil `getFiltered` tanpa limit lalu `.take(limit)` di memori.
Di dataset besar ini O(n) per pemanggilan. (Catatan: "lazy fix" = tambah `limit()`
di query Drift kalau nanti jadi masalah nyata.)

### 🟡 A20 — `DashboardRepository.totalBalance` melakukan N+1 query
Untuk setiap akun dipanggil `balanceForAccount` (2–3 query) + `convert` (2–3 query).
Tidak masalah untuk puluhan akun, relevan kalau jumlah akun tumbuh.

---

## 14. Testing structure

Framework: `flutter_test` saja. **Tidak ada** mocking framework (tidak ada
`mockito`/`mocktail`) — pola yang dipakai: database in-memory nyata
(`AppDatabase.forTesting(NativeDatabase.memory())`), file DB temporer untuk test
migrasi, dan fake hand-written (`FakeAccountsRepository` di `test/providers_test.dart`).

| File | Test | Cakupan |
|---|---|---|
| `data_layer_test.dart` | 31 | schema & migration, currency DAO, account/category repository, CRUD transaksi + constraint, transfer, ledger & agregasi, filter & sorting, exchange rate DAO |
| `csv_import_test.dart` | 51 | parser angka/tanggal/encoding/header, service, `csvDedupeHash` |
| `accounts_categories_test.dart` | 18 | CRUD akun & kategori via widget + provider nyata, RESTRICT delete, fallback "Lainnya", seed idempotent |
| `transaction_mutation_test.dart` | 18 | create/edit/delete, transfer, rollback saat kegagalan DB |
| `csv_import_repository_test.dart` | 16 | preview read-only, import atomik, baris tak bisa dipetakan, DI wiring |
| `ledger_summary_test.dart` | 15 | `convertMinorUnit` (pure), `CurrencyConverter`, `DashboardRepository.totalBalance`, `recentTransactions` |
| `reports_repository_test.dart` | 12 | pie, bar, multi-currency + konversi IDR, missing rate, presisi |
| `transaction_form_test.dart` | 9 | create/validasi/edit form |
| `database_migration_test.dart` | 8 | migrasi + seed di file DB nyata (bukan in-memory) |
| `currency_settings_test.dart` | 5 | alur onboarding pilih currency + persistensi |
| `onboarding_flow_test.dart` | 4 | onboarding → dashboard, redirect |
| `app_theme_test.dart` | 2 | dark theme permanen |
| `formatters_validators_test.dart` | 28 | MoneyFormatter, DateFormatter, CurrencyFormat, validators, AmountField |
| `providers_test.dart` | 1 | override provider dengan fake repository |
| **Total** | **218** | semua pass |

Konvensi test yang terlihat:
- Nama test & `group` berbahasa Indonesia, deskriptif terhadap acceptance
  (`group('rollback pada kegagalan database', ...)`).
- Nama file mengikuti domain, bukan mengikuti nama file `lib/` (mis.
  `ledger_summary_test.dart` menguji `currency_converter.dart` + `dashboard_repository.dart`).
- Widget test memakai `Key` string, bukan finder berbasis teks/tipe.
- `test/widget_test.dart` bawaan Flutter sudah **dihapus** (commit `763a3a1`).
- Tidak ada `integration_test/`, tidak ada golden test, tidak ada coverage gate.

---

## 15. Konvensi untuk coding agent berikutnya

Aturan yang **sudah berlaku di codebase ini** dan harus diikuti (bukan usulan baru):

1. **Uang = `int` minor unit.** IDR/JPY minor unit 0, USD/SGD/MYR/THB 2,
   USDT 6. Jangan pernah `double`. Sumber minor unit runtime = tabel `currencies`
   (fallback statis `kCurrencyMinorUnits`/`kDefaultCurrencyFormats` hanya untuk
   jalur tanpa DB).
2. **Saldo dihitung dari ledger.** Tabel `accounts` tidak punya kolom `balance`.
   Jangan menambahkannya; saldo = `opening_balance + income − expense − transfer_keluar + transfer_masuk`.
3. **Tulis multi-langkah selalu di dalam satu `AppDatabase.transaction`**, dan
   rollback penuh saat error. Ini pola yang sudah dipakai di use case,
   `CsvImportRepository.importBytes`, `CategoryRepository.delete`,
   `AccountRepository.delete`.
4. **Validasi domain SEBELUM menulis** (use case/repository), bukan hanya di widget.
5. **UI tidak boleh menyentuh Drift/DAO langsung.** Lewat provider → repository/use case.
6. **Provider didaftarkan di `core/di/providers.dart`** (kecuali provider khusus
   fitur, seperti `features/transactions/providers/transaction_providers.dart` untuk
   `categoriesByTypeProvider` + use case provider).
7. **Named constructor Drift**: `...Companion.insert(...)` untuk baris baru;
   `Value(...)`/`Value.absent()` untuk kolom nullable saat insert/update.
8. **Perubahan schema WAJIB naikkan `_schemaVersion` dan tambahkan step migrasi.**
   Enum disimpan sebagai TEXT nama entry → rename entry = breaking change.
9. **File `*.g.dart` di-track di git.** Setelah mengubah `tables.dart`/DAO, jalankan
   codegen dan commit hasilnya (`dart run build_runner build`).
10. **Berikan `Key` string pada setiap widget yang perlu di-driver test**
    (pola `'<feature>.<area>.<action>'`, mis. `'transaction.form.save'`).
11. **Doc comment + pesan UI berbahasa Indonesia**; identifier & komentar teknis
    mengikuti gaya file sekitarnya (campur ID/EN).
12. **Fix bug = patch minimal**, jangan rewrite satu file penuh; commit terpisah
    `fix: <deskripsi>`; kalau menimbulkan regresi → revert commit itu
    (aturan dari `AGENTS.md`, sudah dipatuhi di riwayat commit).
13. **Conventional commits** + nomor PR/task ID: `feat(fe):`, `feat(be):`, `fix(test):`, `chore(release):`.
14. **Jangan commit** `build/`, `.dart_tool/`, `android/local.properties`,
    `android/.gradle/` (sudah di `.gitignore`).
15. **VPS RAM terbatas**: `android/gradle.properties` (daemon OFF, heap 2 GB) dan
    `kotlin.daemon.jvmargs` **jangan diubah**. Build APK:
    `flutter build apk --debug --no-pub`.
16. **Perintah verifikasi wajib** (dari `AGENTS.md`):
    `export PATH="/opt/flutter/bin:$PATH"` lalu `flutter analyze` (harus 0 issues),
    `flutter test` (harus pass).
17. **Jangan tambah dependency** tanpa keputusan user (aturan dalam tugas ini).
    Kalau butuh chart/file picker, itu keputusan produk — bukan keputusan agent.
18. **Kalau ragu, tandai UNKNOWN.** Jangan mengarang arsitektur/lapisan yang belum ada.

---

## 16. UNKNOWN (tidak bisa diverifikasi dari codebase)

1. **UNKNOWN** — siapa/apa yang dimaksudkan mengisi tabel `exchange_rates`
   (input manual? import? API?). Tidak ada kode, seed, dokumentasi, atau test yang
   menulisnya.
2. **UNKNOWN** — isi `PRD.md` §7 langkah-langkah final dan apakah requirement UI
   import CSV/report sudah disepakati bentuknya. PRD ada di luar folder ini
   (`../PRD.md`) dan tidak dibaca ulang untuk dokumen ini.
3. **UNKNOWN** — status `../v_expense_ui`: dibuang, prototipe, atau sumber UI yang
   akan dipakai? Remote-nya sama dengan repo ini dan working tree-nya tidak bersih.
4. **UNKNOWN** — apakah branch `fe/fe-08-import-csv` (import CSV UI) pernah
   diselesaikan; branch ada lokal, tidak ada di `remote`, dan tidak merged ke `main`.
5. **UNKNOWN** — target platform berikutnya (README/AGENTS menyebut "Android first",
   "iOS nyusul", tapi tidak ada folder `ios/` dan tidak ada konfigurasi platform lain).
6. **UNKNOWN** — apakah signing key release akan dibuat (release saat ini debug key).
7. **UNKNOWN** — apakah `currencies`/`exchange_rates` boleh diubah user dari UI
   (belum ada screen settings).
8. **UNKNOWN** — perilaku UI yang diharapkan untuk transaksi `transfer` yang
   sudah didukung di data layer (belum ada layar).
9. **UNKNOWN** — apakah pembagian task FE/BE (`AGENTS.md`: FE = Qwen, BE = deepseek,
   QA = Qwen Flash, PM = GPT-5.6 Luna) masih berlaku; tidak ada artefak kanban di repo.

---

## 17. Evidence (perintah verifikasi)

```bash
export PATH="/opt/flutter/bin:$PATH"
cd /home/ubuntu/Projects/money-tracking/v_expense

git log --oneline -11          # riwayat commit di atas
git branch --no-merged main    # 8 branch belum merged
git branch -r                  # branch yang ada di origin
git remote -v                  # https://.../sandacof003/vexpense.git

find lib -name '*.dart' ! -name '*.g.dart' | wc -l   # 53
find lib -name '*.g.dart' | wc -l                    # 6
find test -name '*.dart' | wc -l                     # 14
find lib test -name '*.dart' | xargs wc -l | tail -1 # 14619 total

flutter analyze   # No issues found! (ran in 7.0s)
flutter test      # 00:42 +218: All tests passed!
dart format --output=none --set-exit-if-changed lib test   # 20 file akan berubah
```

Semua angka, nama file, nama kelas, dan tanda tangan method di dokumen ini diambil
dari pembacaan file aktual di commit `29ff871`, bukan dari `README.md`/`AGENTS.md`
(dokumen-dokumen itu terbukti menyimpang di beberapa tempat — lihat A4).
