import 'package:drift/drift.dart';

import '../../services/csv/csv_formats.dart';
import '../../services/csv/csv_import_models.dart';
import '../../services/csv/csv_import_service.dart';
import '../../services/csv/csv_parser.dart';
import '../daos/account_dao.dart';
import '../daos/category_dao.dart';
import '../daos/currency_dao.dart';
import '../daos/transaction_dao.dart';
import '../database.dart';
import '../enums.dart';
import 'repository_contracts.dart';

/// Entry point import CSV end-to-end (PRD §7).
///
/// Langkahnya sengaja dipisah dari [CsvImportService] (parser murni, tanpa DB):
/// - dedupe dihitung dari **DB**, bukan dari caller yang harus mengisi
///   `existingHashes` manual;
/// - mapping akun/kategori by name (auto-create kalau belum ada);
/// - seluruh insert batch dijalankan dalam SATU `AppDatabase.transaction`,
///   jadi kegagalan di tengah batch = rollback penuh.
///
/// Satu trade-off yang diketahui: kategori di-resolve (dan bisa dibuat) sebelum
/// akun, jadi baris yang ditolak karena currency akun tidak cocok bisa
/// meninggalkan kategori baru tanpa transaksi. Bukan korupsi data dan tidak
/// memengaruhi atomicity (transaksi tetap rollback penuh saat error), tapi
/// kategori itu tidak otomatis dibersihkan.
class CsvImportRepositoryImpl implements CsvImportRepository {
  CsvImportRepositoryImpl(
    this._db,
    this._service,
    this._transactionDao,
    this._accountDao,
    this._categoryDao,
    this._currencyDao,
  );

  final AppDatabase _db;
  final CsvImportService _service;
  final TransactionDao _transactionDao;
  final AccountDao _accountDao;
  final CategoryDao _categoryDao;
  final CurrencyDao _currencyDao;

  @override
  Future<CsvImportPreview> preview({
    required List<int> bytes,
    String? fileName,
  }) async {
    final prepared = await _prepare(
      bytes: bytes,
      fileName: fileName,
      existingHashes: await _existingHashes(),
    );
    return CsvImportPreview(
      result: CsvImportResult(
        rows: prepared.rows,
        errors: prepared.errors,
        summary: prepared.summary,
      ),
      accountsToCreate: _namesToCreate(
        prepared.rows.map((r) => r.accountName),
        _existingNames(await _accountDao.getAll(), (a) => a.name),
      ),
      categoriesToCreate: _namesToCreate(
        prepared.rows.map((r) => r.categoryName),
        _existingNames(await _categoryDao.getAll(), (c) => c.name),
      ),
    );
  }

  @override
  Future<CsvImportReport> importBytes({
    required List<int> bytes,
    String? fileName,
  }) {
    // Satu transaksi untuk seluruh batch. Hash existing dibaca ulang DI DALAM
    // transaksi ini supaya idempotensi tidak bergantung pada caller.
    return _db.transaction(() async {
      final prepared = await _prepare(
        bytes: bytes,
        fileName: fileName,
        existingHashes: await _existingHashes(),
      );

      final accountsByName = <String, Account>{
        for (final account in await _accountDao.getAll())
          account.name.trim().toLowerCase(): account,
      };
      final categoriesByName = <String, Category>{
        for (final category in await _categoryDao.getAll())
          category.name.trim().toLowerCase(): category,
      };

      final errors = <CsvRowError>[...prepared.errors];
      final seenHashes = <String>{};
      var inserted = 0;
      var createdAccounts = 0;
      var createdCategories = 0;

      for (final row in prepared.rows) {
        final hash = row.computeDedupeHash();
        if (!seenHashes.add(hash)) {
          errors.add(
            CsvRowError(
              code: CsvImportErrorCode.duplicate,
              rowNumber: row.rowNumber,
              message: 'Duplikat di dalam batch yang sama',
            ),
          );
          continue;
        }

        final category = await _resolveCategory(
          row: row,
          cache: categoriesByName,
          errors: errors,
          onCreated: () => createdCategories++,
        );
        if (category == null) continue;

        final account = await _resolveAccount(
          row: row,
          cache: accountsByName,
          errors: errors,
          onCreated: () => createdAccounts++,
        );
        if (account == null) continue;

        await insertTransaction(
          TransactionsCompanion.insert(
            type: TransactionType.values.byName(row.type),
            amount: row.amountMinorUnit,
            accountId: account.id,
            categoryId: Value(category.id),
            date: row.date,
            description: Value(row.note),
          ),
        );
        inserted++;
      }

      return CsvImportReport(
        insertedRows: inserted,
        createdAccounts: createdAccounts,
        createdCategories: createdCategories,
        errors: errors,
      );
    });
  }

  /// Insert satu transaksi.
  ///
  /// Dipisah jadi method supaya test bisa memaksa kegagalan di tengah batch dan
  /// membuktikan transaksinya rollback (bukan cuma "kode terlihat atomik").
  Future<int> insertTransaction(TransactionsCompanion tx) =>
      _transactionDao.insert(tx);

  /// Parse + validasi + dedupe. Jalur yang sama dipakai preview dan import,
  /// supaya hasil preview tidak bisa beda dari yang benar-benar di-import.
  Future<_PreparedCsvImport> _prepare({
    required List<int> bytes,
    required Set<String> existingHashes,
    String? fileName,
  }) async {
    final currencies = await _currencyDao.getAll();
    final result = _service.importBytes(
      bytes: bytes,
      fileName: fileName,
      options: CsvImportOptions(
        supportedCurrencyCodes: currencies.isEmpty
            ? kDefaultCurrencyCodes
            : currencies.map((c) => c.code).toSet(),
        // Minor unit juga dari tabel `currencies` — kalau tidak, currency
        // minor-0/3 yang cuma ada di DB akan diskalakan fallback 2 (100x).
        minorUnitsByCurrency: currencies.isEmpty
            ? kCurrencyMinorUnits
            : {for (final c in currencies) c.code: c.minorUnit},
        existingHashes: existingHashes,
      ),
    );

    final rows = <CsvParsedRow>[];
    final errors = <CsvRowError>[...result.errors];
    final accountNames = <String>{};
    final categoryNames = <String>{};
    var rejected = 0;

    for (final row in result.rows) {
      // Kontrak CSV MVP hanya punya satu kolom `Account`; transfer butuh akun
      // tujuan yang tidak ada di file, jadi ditolak dengan alasan eksplisit
      // (bukan di-drop diam-diam, bukan dipaksa jadi expense).
      if (row.type == TransactionType.transfer.name) {
        rejected++;
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.unsupportedTransfer,
            rowNumber: row.rowNumber,
            column: 'Type',
            message: 'Transfer belum didukung import CSV (butuh akun tujuan)',
          ),
        );
        continue;
      }
      rows.add(row);
      accountNames.add(row.accountName.trim());
      categoryNames.add(row.categoryName.trim());
    }

    return _PreparedCsvImport(
      rows: rows,
      errors: errors,
      summary: CsvImportSummary(
        totalRows: result.summary.totalRows,
        validRows: rows.length,
        duplicateRows: result.summary.duplicateRows,
        invalidRows: result.summary.invalidRows + rejected,
        distinctAccounts: accountNames.length,
        distinctCategories: categoryNames.where((n) => n.isNotEmpty).length,
      ),
    );
  }

  /// Semua hash transaksi existing di DB.
  ///
  /// Dihitung dari nama akun + kategori hasil join manual supaya memakai
  /// [csvDedupeHash] yang sama dengan jalur CSV — satu implementasi hash, tidak
  /// ada duplikasi rumus yang bisa menyimpang.
  ///
  /// `date` dikonversi `.toUtc()`: baris CSV disimpan date-only UTC, sedangkan
  /// drift mengembalikan DateTime dalam waktu lokal — tanpa ini hash bisa beda
  /// satu hari di timezone non-UTC dan import ulang menggandakan transaksi.
  Future<Set<String>> _existingHashes() async {
    final transactions = await _transactionDao.getFiltered(
      const TransactionFilter(),
    );
    if (transactions.isEmpty) return const <String>{};

    final accounts = {
      for (final a in await _accountDao.getAll()) a.id: a,
    };
    final categories = {
      for (final c in await _categoryDao.getAll()) c.id: c,
    };

    final hashes = <String>{};
    for (final tx in transactions) {
      final account = accounts[tx.accountId];
      if (account == null) continue; // dijaga FK: tidak terjadi
      final categoryId = tx.categoryId;
      hashes.add(
        csvDedupeHash(
          date: tx.date.toUtc(),
          type: tx.type.name,
          amountMinorUnit: tx.amount,
          currencyCode: account.currency,
          accountName: account.name,
          categoryName: categoryId == null
              ? ''
              : (categories[categoryId]?.name ?? ''),
          note: tx.description,
        ),
      );
    }
    return hashes;
  }

  /// Kategori untuk satu baris. `null` = baris di-skip (error sudah ditambahkan).
  Future<Category?> _resolveCategory({
    required CsvParsedRow row,
    required Map<String, Category> cache,
    required List<CsvRowError> errors,
    required void Function() onCreated,
  }) async {
    final name = row.categoryName.trim();
    if (name.isEmpty) {
      // Parser sudah menolak income/expense tanpa kategori; ini jaring pengaman.
      errors.add(
        CsvRowError(
          code: CsvImportErrorCode.requiredValueMissing,
          rowNumber: row.rowNumber,
          column: 'Category',
          message: 'Kategori wajib untuk ${row.type}',
        ),
      );
      return null;
    }

    final wanted = row.type == TransactionType.income.name
        ? CategoryType.income
        : CategoryType.expense;
    final existing = cache[name.toLowerCase()];
    if (existing != null) {
      // `categories.name` unik, jadi kategori bertipe lain tidak bisa dipakai
      // dan tidak bisa dibuat ulang dengan nama sama → butuh mapping manual.
      if (existing.type != wanted) {
        errors.add(
          CsvRowError(
            code: CsvImportErrorCode.categoryTypeMismatch,
            rowNumber: row.rowNumber,
            column: 'Category',
            message:
                'Kategori "$name" sudah ada bertipe ${existing.type.name}, '
                'sedangkan baris ini ${wanted.name}',
          ),
        );
        return null;
      }
      return existing;
    }

    final id = await _categoryDao.insert(
      CategoriesCompanion.insert(name: name, type: wanted),
    );
    final created = (await _categoryDao.getById(id))!;
    cache[name.toLowerCase()] = created;
    onCreated();
    return created;
  }

  /// Akun untuk satu baris. `null` = baris di-skip (error sudah ditambahkan).
  Future<Account?> _resolveAccount({
    required CsvParsedRow row,
    required Map<String, Account> cache,
    required List<CsvRowError> errors,
    required void Function() onCreated,
  }) async {
    final name = row.accountName.trim();
    final existing = cache[name.toLowerCase()];
    if (existing == null) {
      // CSV tidak punya kolom tipe akun; `cash` dipakai sebagai default dan
      // currency-nya mengikuti kolom Currency baris.
      final id = await _accountDao.insert(
        AccountsCompanion.insert(
          name: name,
          type: AccountType.cash,
          currency: row.currencyCode,
        ),
      );
      final created = (await _accountDao.getById(id))!;
      cache[name.toLowerCase()] = created;
      onCreated();
      return created;
    }

    // Transaksi mewarisi currency akun, jadi nominal baris tidak bisa dihormati
    // kalau currency-nya beda — selain itu dedupe jadi tidak stabil.
    if (existing.currency != row.currencyCode) {
      errors.add(
        CsvRowError(
          code: CsvImportErrorCode.accountCurrencyMismatch,
          rowNumber: row.rowNumber,
          column: 'Currency',
          message:
              'Akun "$name" memakai ${existing.currency}, '
              'sedangkan baris ini ${row.currencyCode}',
        ),
      );
      return null;
    }
    return existing;
  }

  /// Nama unik (case-insensitive) yang belum ada di DB — kandidat auto-create.
  List<String> _namesToCreate(Iterable<String> csvNames, Set<String> dbNames) {
    final created = <String>[];
    final seen = <String>{};
    for (final raw in csvNames) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (dbNames.contains(key) || !seen.add(key)) continue;
      created.add(name);
    }
    return created;
  }

  Set<String> _existingNames<T>(Iterable<T> rows, String Function(T row) name) =>
      {for (final row in rows) name(row).trim().toLowerCase()};
}

class _PreparedCsvImport {
  const _PreparedCsvImport({
    required this.rows,
    required this.errors,
    required this.summary,
  });

  final List<CsvParsedRow> rows;
  final List<CsvRowError> errors;
  final CsvImportSummary summary;
}
