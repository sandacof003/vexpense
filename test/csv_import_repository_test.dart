import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/daos/account_dao.dart';
import 'package:v_expense/core/data/daos/category_dao.dart';
import 'package:v_expense/core/data/daos/currency_dao.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/data/repositories/csv_import_repository.dart';
import 'package:v_expense/core/data/repositories/repository_contracts.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/core/services/csv/csv_import_models.dart';
import 'package:v_expense/core/services/csv/csv_import_service.dart';

/// CSV valid dengan campuran kategori: `Makan` (baru), `Gaji` (seed income),
/// `Transport` (seed expense).
const String _csv =
    'Date,Type,Category,Account,Amount,Currency,Note\n'
    '2024-01-15,expense,Makan,Cash,25000,IDR,lunch\n'
    '2024-01-16,income,Gaji,BCA,5000000,IDR,gaji januari\n'
    '2024-01-17,expense,Transport,Cash,15000,IDR,ojek\n';

List<int> _bytes(String csv) => utf8.encode(csv);

AppDatabase _open() => AppDatabase.forTesting(NativeDatabase.memory());

CsvImportRepositoryImpl _repo(AppDatabase db) => CsvImportRepositoryImpl(
  db,
  const CsvImportService(),
  TransactionDao(db),
  AccountDao(db),
  CategoryDao(db),
  CurrencyDao(db),
);

/// Repository yang dipaksa gagal pada insert ke-[failAtCall] — untuk
/// membuktikan transaksi import benar-benar rollback, bukan cuma terlihat atomic.
// Nama parameter super bersifat privat di library-nya, jadi tidak bisa dipakai
// sebagai super parameter dari library test ini.
class _FailingCsvImportRepository extends CsvImportRepositoryImpl {
  // ignore: use_super_parameters
  _FailingCsvImportRepository(
    AppDatabase db,
    CsvImportService service,
    TransactionDao transactionDao,
    AccountDao accountDao,
    CategoryDao categoryDao,
    CurrencyDao currencyDao, {
    required this.failAtCall,
  }) : super(db, service, transactionDao, accountDao, categoryDao, currencyDao);

  final int failAtCall;
  int calls = 0;

  @override
  Future<int> insertTransaction(TransactionsCompanion tx) {
    final call = calls++;
    if (call == failAtCall) {
      throw StateError('forced failure di tengah batch');
    }
    return super.insertTransaction(tx);
  }
}

void main() {
  late AppDatabase db;
  late CsvImportRepositoryImpl repo;

  setUp(() {
    db = _open();
    repo = _repo(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('preview (read-only)', () {
    test('parse + dedupe + mapping tanpa menulis apa pun ke DB', () async {
      final preview = await repo.preview(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );

      expect(preview.rows, hasLength(3));
      expect(preview.summary.validRows, 3);
      expect(preview.summary.distinctAccounts, 2);
      expect(preview.summary.totalRows, 3);
      // Seed sudah punya Gaji & Transport; hanya Makan yang baru.
      expect(preview.accountsToCreate, ['Cash', 'BCA']);
      expect(preview.categoriesToCreate, ['Makan']);

      // Read-only: tidak ada yang tertulis.
      expect(await db.transactionDao.count(), 0);
      expect(await db.accountDao.getAll(), isEmpty);
    });

    test('error level file (bukan .csv) -> 0 baris, tidak menulis DB', () async {
      final preview = await repo.preview(
        bytes: _bytes(_csv),
        fileName: 'mutasi.txt',
      );
      expect(preview.rows, isEmpty);
      expect(preview.fileErrors.single.code, CsvImportErrorCode.notCsv);
      expect(await db.transactionDao.count(), 0);
    });
  });

  group('import atomic', () {
    test('import end-to-end: transaksi + akun + kategori ter-mapping', () async {
      final preview = await repo.preview(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );
      final report = await repo.importBytes(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );

      expect(report.insertedRows, 3);
      expect(report.createdAccounts, 2);
      expect(report.createdCategories, 1);
      expect(report.skippedRows, 0);
      expect(report.message, contains('Berhasil import 3 transaksi'));
      expect(report.summaryMatchesPreviewPlan(preview), isTrue);

      final transactions = await db.transactionDao.getFiltered(
        const TransactionFilter(),
      );
      expect(transactions, hasLength(3));

      final accounts = {
        for (final a in await db.accountDao.getAll()) a.name: a,
      };
      expect(accounts.keys, containsAll(['Cash', 'BCA']));
      expect(accounts['Cash']!.currency, 'IDR');

      final lunch = transactions.firstWhere((t) => t.description == 'lunch');
      expect(lunch.type, TransactionType.expense);
      expect(lunch.amount, 25000);
      // Drift mengembalikan DateTime dalam waktu lokal mesin; instant-nya harus
      // tetap sama dengan date-only UTC dari CSV (inilah yang bikin dedupe
      // stabil di timezone non-UTC — mesin test ini UTC+8).
      expect(lunch.date.toUtc(), DateTime.utc(2024, 1, 15));
      expect(lunch.accountId, accounts['Cash']!.id);

      final gaji = transactions.firstWhere((t) => t.description == 'gaji januari');
      expect(gaji.type, TransactionType.income);
      // Kategori seed 'Gaji' dipakai ulang, bukan dibuat baru.
      final gajiCategory = await db.categoryDao.getById(gaji.categoryId!);
      expect(gajiCategory!.name, 'Gaji');
    });

    test('import ulang file yang sama tidak menggandakan (idempotent)', () async {
      final first = await repo.importBytes(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );
      expect(first.insertedRows, 3);

      // Preview kedua: semuanya sudah ada di DB -> tidak ada baris siap-import.
      final previewAgain = await repo.preview(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );
      expect(previewAgain.rows, isEmpty);
      expect(
        previewAgain.errors.where(
          (e) => e.code == CsvImportErrorCode.duplicate,
        ),
        hasLength(3),
      );
      expect(previewAgain.accountsToCreate, isEmpty);
      expect(previewAgain.categoriesToCreate, isEmpty);

      // Jalur API yang sama, dijalankan dua kali: DB tidak bertambah.
      final second = await repo.importBytes(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );
      expect(second.insertedRows, 0);
      expect(second.duplicateRows, 3);
      expect(await db.transactionDao.count(), 3);
      // Akun tidak dibuat ulang juga.
      expect(await db.accountDao.getAll(), hasLength(2));
    });

    test('idempotent walau caller tidak mengirim hash apa pun (dedupe dari DB)', () async {
      // Bukti kontrak: API hanya butuh bytes — tidak ada parameter existingHashes.
      await repo.importBytes(bytes: _bytes(_csv), fileName: 'mutasi.csv');
      await repo.importBytes(bytes: _bytes(_csv), fileName: 'mutasi.csv');
      await repo.importBytes(bytes: _bytes(_csv), fileName: 'mutasi.csv');
      expect(await db.transactionDao.count(), 3);
    });

    test('gagal di tengah batch -> rollback penuh (0 transaksi, 0 akun)', () async {
      final categoriesBefore = await db.categoryDao.getAll();
      final failing = _FailingCsvImportRepository(
        db,
        const CsvImportService(),
        TransactionDao(db),
        AccountDao(db),
        CategoryDao(db),
        CurrencyDao(db),
        failAtCall: 1,
      );

      await expectLater(
        failing.importBytes(bytes: _bytes(_csv), fileName: 'mutasi.csv'),
        throwsA(isA<StateError>()),
      );

      expect(await db.transactionDao.count(), 0);
      expect(await db.accountDao.getAll(), isEmpty);
      expect(
        (await db.categoryDao.getAll()).length,
        categoriesBefore.length,
      );
    });

    test('gagal di baris pertama -> rollback penuh juga', () async {
      final failing = _FailingCsvImportRepository(
        db,
        const CsvImportService(),
        TransactionDao(db),
        AccountDao(db),
        CategoryDao(db),
        CurrencyDao(db),
        failAtCall: 0,
      );

      await expectLater(
        failing.importBytes(bytes: _bytes(_csv), fileName: 'mutasi.csv'),
        throwsA(isA<StateError>()),
      );
      expect(await db.transactionDao.count(), 0);
    });

    test('data persist setelah DB dibuka ulang', () async {
      final dir = await Directory.systemTemp.createTemp('vexpense_csv');
      final file = File('${dir.path}/test.sqlite');
      try {
        var reopened = AppDatabase.forTesting(NativeDatabase(file));
        final first = await _repo(reopened).importBytes(
          bytes: _bytes(_csv),
          fileName: 'mutasi.csv',
        );
        expect(first.insertedRows, 3);
        await reopened.close();

        reopened = AppDatabase.forTesting(NativeDatabase(file));
        expect(await reopened.transactionDao.count(), 3);
        final second = await _repo(reopened).importBytes(
          bytes: _bytes(_csv),
          fileName: 'mutasi.csv',
        );
        expect(second.insertedRows, 0);
        expect(await reopened.transactionDao.count(), 3);
        await reopened.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('baris yang tidak bisa dipetakan', () {
    test('transfer ditolak eksplisit, baris lain tetap masuk', () async {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,transfer,,BCA,25000,IDR,\n'
          '2024-01-16,expense,Makan,Cash,25000,IDR,lunch';
      final report = await repo.importBytes(
        bytes: _bytes(csv),
        fileName: 'mutasi.csv',
      );

      expect(report.insertedRows, 1);
      final rejected = report.errors.where(
        (e) => e.code == CsvImportErrorCode.unsupportedTransfer,
      );
      expect(rejected, hasLength(1));
      expect(rejected.single.rowNumber, 1);
      expect(await db.transactionDao.count(), 1);
    });

    test('currency baris beda dari akun existing -> ditolak, tidak masuk', () async {
      await db.accountDao.insert(
        AccountsCompanion.insert(
          name: 'Cash',
          type: AccountType.cash,
          currency: 'USD',
        ),
      );
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,25000,IDR,lunch';
      final report = await repo.importBytes(
        bytes: _bytes(csv),
        fileName: 'mutasi.csv',
      );

      expect(report.insertedRows, 0);
      expect(
        report.errors.single.code,
        CsvImportErrorCode.accountCurrencyMismatch,
      );
      expect(await db.transactionDao.count(), 0);
    });

    test('kategori bertipe beda -> ditolak (name unik, butuh mapping manual)', () async {
      // 'Makan & Minum' = seed expense; dipakai di baris income.
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-16,income,Makan & Minum,BCA,5000000,IDR,bonus';
      final report = await repo.importBytes(
        bytes: _bytes(csv),
        fileName: 'mutasi.csv',
      );

      expect(report.insertedRows, 0);
      expect(
        report.errors.single.code,
        CsvImportErrorCode.categoryTypeMismatch,
      );
      expect(report.errors.single.message, contains('expense'));
      expect(await db.transactionDao.count(), 0);
    });

    test('baris invalid tidak membatalkan baris valid (partial batch)', () async {
      const csv =
          'Date,Type,Category,Account,Amount,Currency,Note\n'
          '2024-01-15,expense,Makan,Cash,0,IDR,nol\n'
          '2024-01-16,expense,Makan,Cash,25000,IDR,ok';
      final report = await repo.importBytes(
        bytes: _bytes(csv),
        fileName: 'mutasi.csv',
      );

      expect(report.insertedRows, 1);
      expect(report.invalidRows, 1);
      expect(report.errors.single.code, CsvImportErrorCode.zeroAmount);
      expect(await db.transactionDao.count(), 1);
    });
  });

  group('DI wiring (providers)', () {
    test('csvImportRepositoryProvider -> import lewat provider nyata', () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final CsvImportRepository fromDi = container.read(
        csvImportRepositoryProvider,
      );
      final report = await fromDi.importBytes(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );

      expect(report.insertedRows, 3);
      expect(await db.transactionDao.count(), 3);

      final again = await fromDi.importBytes(
        bytes: _bytes(_csv),
        fileName: 'mutasi.csv',
      );
      expect(again.insertedRows, 0);
      expect(await db.transactionDao.count(), 3);
    });
  });
}

extension on CsvImportReport {
  /// Rencana di preview harus sama dengan yang benar-benar dilakukan import:
  /// jumlah baris yang masuk, dan daftar akun/kategori yang dibuat.
  bool summaryMatchesPreviewPlan(CsvImportPreview preview) =>
      preview.summary.validRows == insertedRows &&
      preview.accountsToCreate.length == createdAccounts &&
      preview.categoriesToCreate.length == createdCategories;
}
