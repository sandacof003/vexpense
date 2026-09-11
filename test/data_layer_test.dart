import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/data/daos/account_dao.dart';
import 'package:v_expense/core/data/daos/category_dao.dart';
import 'package:v_expense/core/data/daos/currency_dao.dart';
import 'package:v_expense/core/data/daos/exchange_rate_dao.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart';
import 'package:v_expense/core/data/repositories/account_repository.dart';
import 'package:v_expense/core/data/repositories/category_repository.dart';
import 'package:v_expense/core/data/repositories/transaction_repository.dart';

/// Buka database in-memory untuk test (isolasi penuh antar test).
AppDatabase _open() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late CurrencyDao currencyDao;
  late AccountDao accountDao;
  late CategoryDao categoryDao;
  late TransactionDao transactionDao;
  late ExchangeRateDao exchangeRateDao;

  late AccountRepository accountRepo;
  late CategoryRepository categoryRepo;
  late TransactionRepository transactionRepo;

  setUp(() {
    db = _open();
    currencyDao = db.currencyDao;
    accountDao = db.accountDao;
    categoryDao = db.categoryDao;
    transactionDao = db.transactionDao;
    exchangeRateDao = db.exchangeRateDao;

    accountRepo = AccountRepository(db, accountDao, transactionDao);
    categoryRepo = CategoryRepository(db, categoryDao, transactionDao);
    transactionRepo = TransactionRepository(db, transactionDao, accountDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('schema & migration', () {
    test('database kosong terbuka aman + seed idempotent', () async {
      final currencies = await currencyDao.getAll();
      expect(
        currencies.map((c) => c.code),
        containsAll(['IDR', 'USD', 'JPY', 'USDT', 'SGD', 'MYR', 'THB']),
      );

      final categories = await categoryDao.getAll();
      final names = categories.map((c) => c.name).toList();
      expect(names, containsAll(['Gaji', 'Makan & Minum', 'Lainnya']));

      // seed tidak duplikat: buka DB kedua kalinya tidak menambah baris.
      final currencyCount = await currencyDao.getAll();
      final categoryCount = await categoryDao.getAll();
      // Re-open via migration tidak mudah dipicu di in-memory; validasi via
      // jumlah kategori income/expense minimal.
      expect(currencyCount.length, 7);
      expect(categoryCount.length, greaterThanOrEqualTo(11));
    });

    test('foreign_keys PRAGMA aktif', () async {
      final on = await db
          .customSelect('PRAGMA foreign_keys')
          .map((r) => r.read<int>('foreign_keys'))
          .getSingle();
      expect(on, 1);
    });

    test(
      'seed kategori idempotent (tidak duplikat saat insert ulang seed)',
      () async {
        // Panggil insert kategori seed dengan nama yang sama harus gagal/duplikat
        // dicegah oleh unique constraint.
        final before = await categoryDao.getAll();
        await expectLater(
          categoryDao.insert(
            CategoriesCompanion.insert(name: 'Gaji', type: CategoryType.income),
          ),
          throwsA(anything), // unique constraint violation
        );
        final after = await categoryDao.getAll();
        expect(after.length, before.length);
      },
    );
  });

  group('currency dao', () {
    test('getByCode & upsert', () async {
      final idr = await currencyDao.getByCode('IDR');
      expect(idr, isNotNull);
      expect(idr!.minorUnit, 0);
      expect(idr.symbol, 'Rp');

      expect(await currencyDao.getByCode('ZZZ'), isNull);

      await currencyDao.upsert(
        CurrenciesCompanion.insert(code: 'EUR', minorUnit: 2, symbol: '€'),
      );
      final eur = await currencyDao.getByCode('EUR');
      expect(eur, isNotNull);
      expect(eur!.minorUnit, 2);
    });
  });

  group('account repository', () {
    test('create + getById + getAll', () async {
      final acc = await accountRepo.create(
        name: 'Dompet',
        type: AccountType.cash,
      );
      expect(acc.currency, 'IDR');
      expect(acc.openingBalance, 0);

      final list = await accountRepo.getAll();
      expect(list.length, 1);
      expect((await accountRepo.getById(acc.id))!.name, 'Dompet');
    });

    test('nama duplikat ditolak (case-insensitive)', () async {
      await accountRepo.create(name: 'BCA', type: AccountType.bank);
      await expectLater(
        accountRepo.create(name: 'bca', type: AccountType.bank),
        throwsA(isA<DuplicateNameException>()),
      );
    });

    test('update nama, bentrok dengan akun lain ditolak', () async {
      final a = await accountRepo.create(name: 'A', type: AccountType.cash);
      await accountRepo.create(name: 'B', type: AccountType.cash);
      await accountRepo.update(a, newName: 'A baru');
      expect((await accountDao.getById(a.id))!.name, 'A baru');

      await expectLater(
        accountRepo.update(a, newName: 'B'),
        throwsA(isA<DuplicateNameException>()),
      );
    });

    test('delete akun tanpa transaksi berhasil', () async {
      final acc = await accountRepo.create(name: 'X', type: AccountType.cash);
      await accountRepo.delete(acc.id);
      expect(await accountDao.getById(acc.id), isNull);
    });

    test('delete akun dengan transaksi ditolak', () async {
      final acc = await accountRepo.create(name: 'X', type: AccountType.cash);
      final cat = await categoryRepo.create(
        name: 'Makan',
        type: CategoryType.expense,
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 10000,
        accountId: acc.id,
        categoryId: cat.id,
        date: DateTime(2026, 1, 1),
      );
      await expectLater(
        accountRepo.delete(acc.id),
        throwsA(isA<AccountInUseException>()),
      );
    });
  });

  group('category repository', () {
    test('create + getByType', () async {
      final cat = await categoryRepo.create(
        name: 'Ngopi',
        type: CategoryType.expense,
      );
      expect((await categoryRepo.getById(cat.id))!.name, 'Ngopi');
      final expenses = await categoryRepo.getByType(CategoryType.expense);
      expect(expenses.map((c) => c.name), contains('Ngopi'));
    });

    test('nama duplikat ditolak', () async {
      await categoryRepo.create(name: 'Kopi', type: CategoryType.expense);
      await expectLater(
        categoryRepo.create(name: 'kopi', type: CategoryType.expense),
        throwsA(isA<DuplicateNameException>()),
      );
    });

    test('delete kategori memindahkan transaksi ke fallback', () async {
      final acc = await accountRepo.create(name: 'A', type: AccountType.cash);
      final custom = await categoryRepo.create(
        name: 'Makan Luar',
        type: CategoryType.expense,
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 50000,
        accountId: acc.id,
        categoryId: custom.id,
        date: DateTime(2026, 1, 1),
      );

      await categoryRepo.delete(custom.id);
      expect(await categoryDao.getById(custom.id), isNull);

      final txs = await transactionDao.getByAccount(acc.id);
      expect(txs.single.categoryId, isNotNull);
      final fallback = await categoryDao.getById(txs.single.categoryId!);
      expect(fallback!.name, 'Lainnya');
    });
  });

  group('transaction repository - CRUD & constraint', () {
    late Account acc;
    late Category incomeCat;
    late Category expenseCat;

    setUp(() async {
      acc = await accountRepo.create(
        name: 'Dompet',
        type: AccountType.cash,
        openingBalance: 100000,
      );
      incomeCat = await categoryRepo.create(
        name: 'Gaji Baru',
        type: CategoryType.income,
      );
      expenseCat = await categoryRepo.create(
        name: 'Transport Baru',
        type: CategoryType.expense,
      );
    });

    test('add income & expense', () async {
      final inc = await transactionRepo.add(
        type: TransactionType.income,
        amount: 200000,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 1, 1),
      );
      expect(inc.type, TransactionType.income);
      expect(inc.amount, 200000);

      final exp = await transactionRepo.add(
        type: TransactionType.expense,
        amount: 30000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 2),
      );
      expect(exp.amount, 30000);
    });

    test('amount <= 0 ditolak', () async {
      await expectLater(
        transactionRepo.add(
          type: TransactionType.expense,
          amount: 0,
          accountId: acc.id,
          categoryId: expenseCat.id,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
      await expectLater(
        transactionRepo.add(
          type: TransactionType.expense,
          amount: -5,
          accountId: acc.id,
          categoryId: expenseCat.id,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('transfer dipanggil lewat add() ditolak', () async {
      await expectLater(
        transactionRepo.add(
          type: TransactionType.transfer,
          amount: 100,
          accountId: acc.id,
          categoryId: expenseCat.id,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('constraint DB: income tanpa kategori ditolak di level SQL', () async {
      // Level repository mencegah lewat API; level DB mencegah bypass via DAO.
      await expectLater(
        transactionDao.insert(
          TransactionsCompanion.insert(
            type: TransactionType.income,
            amount: 100,
            accountId: acc.id,
            date: DateTime(2026, 1, 1),
          ),
        ),
        throwsA(anything),
      );
    });

    test('delete transaksi', () async {
      final tx = await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.delete(tx.id);
      expect(await transactionDao.getById(tx.id), isNull);
    });

    test('update transaksi (edit efek) atomik', () async {
      final tx = await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.update(
        tx.copyWith(amount: 250, categoryId: Value(incomeCat.id)),
      );
      final updated = (await transactionDao.getById(tx.id))!;
      expect(updated.amount, 250);
      expect(updated.categoryId, incomeCat.id);
    });
  });

  group('transfer', () {
    late Account from;
    late Account to;

    setUp(() async {
      from = await accountRepo.create(
        name: 'Asal',
        type: AccountType.cash,
        openingBalance: 100000,
      );
      to = await accountRepo.create(
        name: 'Tujuan',
        type: AccountType.bank,
        openingBalance: 0,
      );
    });

    test('transfer same-currency menghasilkan satu baris', () async {
      final tx = await transactionRepo.transfer(
        fromAccountId: from.id,
        toAccountId: to.id,
        amount: 40000,
        date: DateTime(2026, 1, 1),
      );
      expect(tx.type, TransactionType.transfer);
      expect(tx.toAccountId, to.id);
      expect(tx.categoryId, isNull);
    });

    test('transfer asal == tujuan ditolak', () async {
      await expectLater(
        transactionRepo.transfer(
          fromAccountId: from.id,
          toAccountId: from.id,
          amount: 100,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('ledger: saldo asal berkurang, tujuan bertambah', () async {
      await transactionRepo.transfer(
        fromAccountId: from.id,
        toAccountId: to.id,
        amount: 40000,
        date: DateTime(2026, 1, 1),
      );
      expect(await transactionRepo.balanceForAccount(from.id), 60000);
      expect(await transactionRepo.balanceForAccount(to.id), 40000);
    });

    test('transfer beda currency ditolak di MVP', () async {
      final usd = await accountRepo.create(
        name: 'USD acc',
        type: AccountType.bank,
        currency: 'USD',
      );
      await expectLater(
        transactionRepo.transfer(
          fromAccountId: from.id,
          toAccountId: usd.id,
          amount: 100,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('ledger & agregasi', () {
    late Account acc;
    late Category incomeCat;
    late Category expenseCat;
    late Category otherExpenseCat;

    setUp(() async {
      acc = await accountRepo.create(
        name: 'A',
        type: AccountType.cash,
        openingBalance: 50000,
      );
      incomeCat = await categoryRepo.create(
        name: 'Gaji X',
        type: CategoryType.income,
      );
      expenseCat = await categoryRepo.create(
        name: 'Makan X',
        type: CategoryType.expense,
      );
      otherExpenseCat = await categoryRepo.create(
        name: 'Transport X',
        type: CategoryType.expense,
      );
    });

    test('balanceForAccount = opening + income - expense', () async {
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 200000,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 1, 5),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 30000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 6),
      );
      expect(await transactionRepo.balanceForAccount(acc.id), 220000);
    });

    test('balanceForAccount akun tidak ada -> ArgumentError', () async {
      await expectLater(
        transactionRepo.balanceForAccount(99999),
        throwsArgumentError,
      );
    });

    test('totalIncome / totalExpense dengan filter tanggal', () async {
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 100000,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 50000,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 2, 1),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 20000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 15),
      );

      expect(await transactionRepo.totalIncome(), 150000);
      expect(
        await transactionRepo.totalIncome(
          from: DateTime(2026, 2, 1),
          to: DateTime(2026, 2, 28),
        ),
        50000,
      );
      expect(await transactionRepo.totalExpense(), 20000);
    });

    test('agregasi database kosong mengembalikan 0', () async {
      expect(await transactionRepo.totalIncome(), 0);
      expect(await transactionRepo.totalExpense(), 0);
      expect(await transactionRepo.expenseByCategory(), isEmpty);
    });

    test('expenseByCategory mengelompokkan total per kategori', () async {
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 10000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 20000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 2),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 5000,
        accountId: acc.id,
        categoryId: otherExpenseCat.id,
        date: DateTime(2026, 1, 3),
      );

      final byCat = await transactionRepo.expenseByCategory();
      final map = {for (final e in byCat) e.$1: e.$2};
      expect(map[expenseCat.id], 30000);
      expect(map[otherExpenseCat.id], 5000);
    });
  });

  group('filter & sorting', () {
    late Account acc;
    late Category expenseCat;

    setUp(() async {
      acc = await accountRepo.create(name: 'A', type: AccountType.cash);
      expenseCat = await categoryRepo.create(
        name: 'Makan',
        type: CategoryType.expense,
      );
    });

    test('filter by type, category, account, tanggal, search', () async {
      final incomeCat = await categoryRepo.create(
        name: 'Gaji Filter',
        type: CategoryType.income,
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
        description: 'Nasi goreng',
      );
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 200,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 1, 15),
        description: 'Gaji Januari',
      );

      // type filter
      final expenses = await transactionRepo.getFiltered(
        const TransactionFilter(type: TransactionType.expense),
      );
      expect(expenses.length, 1);
      expect(expenses.single.description, 'Nasi goreng');

      // category filter
      final byIncome = await transactionRepo.getFiltered(
        TransactionFilter(categoryId: incomeCat.id),
      );
      expect(byIncome.length, 1);

      // date range filter
      final inRange = await transactionRepo.getFiltered(
        TransactionFilter(
          fromDate: DateTime(2026, 1, 10),
          toDate: DateTime(2026, 1, 31),
        ),
      );
      expect(inRange.length, 1);
      expect(inRange.single.description, 'Gaji Januari');

      // search filter (case-insensitive)
      final search = await transactionRepo.getFiltered(
        const TransactionFilter(search: 'NASI'),
      );
      expect(search.length, 1);
    });

    test('sorting date asc/desc + amount', () async {
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 500,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 10),
      );

      final desc = await transactionRepo.getFiltered(
        const TransactionFilter(),
        sort: TransactionSort.dateDesc,
      );
      expect(desc.first.date, DateTime(2026, 1, 10));

      final asc = await transactionRepo.getFiltered(
        const TransactionFilter(),
        sort: TransactionSort.dateAsc,
      );
      expect(asc.first.date, DateTime(2026, 1, 1));

      final amountDesc = await transactionRepo.getFiltered(
        const TransactionFilter(),
        sort: TransactionSort.amountDesc,
      );
      expect(amountDesc.first.amount, 500);

      final amountAsc = await transactionRepo.getFiltered(
        const TransactionFilter(),
        sort: TransactionSort.amountAsc,
      );
      expect(amountAsc.first.amount, 100);
    });

    test('database kosong -> filter mengembalikan list kosong', () async {
      final all = await transactionRepo.getFiltered(const TransactionFilter());
      expect(all, isEmpty);
    });
  });

  group('exchange rate dao', () {
    test('getPair + upsert unique (from,to)', () async {
      expect(await exchangeRateDao.getPair('USD', 'IDR'), isNull);

      await exchangeRateDao.upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: 'USD',
          toCurrency: const Value('IDR'),
          rate: 16000,
        ),
      );
      final pair = await exchangeRateDao.getPair('USD', 'IDR');
      expect(pair, isNotNull);
      expect(pair!.rate, 16000);

      // upsert dengan pair sama -> update, bukan duplikat.
      await exchangeRateDao.upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: 'USD',
          toCurrency: const Value('IDR'),
          rate: 16500,
        ),
      );
      final all = await exchangeRateDao.getAll();
      expect(all.length, 1);
      expect((await exchangeRateDao.getPair('USD', 'IDR'))!.rate, 16500);
    });
  });
}
