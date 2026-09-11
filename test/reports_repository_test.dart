import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/daos/account_dao.dart';
import 'package:v_expense/core/data/daos/category_dao.dart';
import 'package:v_expense/core/data/daos/exchange_rate_dao.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/data/repositories/account_repository.dart';
import 'package:v_expense/core/data/repositories/category_repository.dart';
import 'package:v_expense/core/data/repositories/transaction_repository.dart';
import 'package:v_expense/core/data/services/currency_converter.dart';
import 'package:v_expense/features/reports/data/reports_repository.dart';

AppDatabase _open() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late AccountDao accountDao;
  late CategoryDao categoryDao;
  late ExchangeRateDao exchangeRateDao;
  late TransactionDao transactionDao;

  late AccountRepository accountRepo;
  late CategoryRepository categoryRepo;
  late TransactionRepository transactionRepo;
  late CurrencyConverter converter;
  late ReportsRepository reportsRepo;

  setUp(() {
    db = _open();
    accountDao = db.accountDao;
    categoryDao = db.categoryDao;
    exchangeRateDao = db.exchangeRateDao;
    transactionDao = db.transactionDao;

    accountRepo = AccountRepository(db, accountDao, transactionDao);
    categoryRepo = CategoryRepository(db, categoryDao, transactionDao);
    transactionRepo = TransactionRepository(db, transactionDao, accountDao);
    converter = CurrencyConverter(db.currencyDao, exchangeRateDao);
    reportsRepo = ReportsRepository(
      transactionDao,
      accountDao,
      categoryDao,
      converter,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('expenseByCategory (pie)', () {
    late Account acc;
    late Category makan;
    late Category transport;

    setUp(() async {
      acc = await accountRepo.create(name: 'Dompet', type: AccountType.cash);
      makan = await categoryRepo.create(
        name: 'Makan',
        type: CategoryType.expense,
      );
      transport = await categoryRepo.create(
        name: 'Transport T',
        type: CategoryType.expense,
      );
    });

    test('total expense per kategori (minor unit) + urut menurun', () async {
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 10000,
        accountId: acc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 30000,
        accountId: acc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 2),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 5000,
        accountId: acc.id,
        categoryId: transport.id,
        date: DateTime(2026, 1, 3),
      );

      final report = await reportsRepo.expenseByCategory();
      expect(report.isComplete, isTrue);
      expect(report.missingRateCurrencies, isEmpty);

      final byId = {for (final c in report.categories) c.categoryId: c};
      expect(byId[makan.id]!.totalMinorUnit, 40000);
      expect(byId[makan.id]!.categoryName, 'Makan');
      expect(byId[transport.id]!.totalMinorUnit, 5000);

      // urut dari total terbesar.
      expect(report.categories.first.categoryId, makan.id);
    });

    test('batas tanggal inklusif', () async {
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 10000,
        accountId: acc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 20000,
        accountId: acc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 31),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 40000,
        accountId: acc.id,
        categoryId: makan.id,
        date: DateTime(2026, 2, 1),
      );

      final report = await reportsRepo.expenseByCategory(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );
      final single = report.categories.single;
      expect(single.totalMinorUnit, 30000); // 40000 (Feb) di luar rentang.
    });

    test('transfer tidak masuk chart', () async {
      final other = await accountRepo.create(
        name: 'Bank',
        type: AccountType.bank,
      );
      await transactionRepo.transfer(
        fromAccountId: acc.id,
        toAccountId: other.id,
        amount: 99999,
        date: DateTime(2026, 1, 15),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 10000,
        accountId: acc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 16),
      );

      final report = await reportsRepo.expenseByCategory();
      expect(report.categories.single.totalMinorUnit, 10000);
      expect(report.categories.single.categoryId, makan.id);
    });

    test('database kosong -> kategori kosong, complete', () async {
      final report = await reportsRepo.expenseByCategory();
      expect(report.categories, isEmpty);
      expect(report.isComplete, isTrue);
    });
  });

  group('incomeVsExpense (bar)', () {
    late Account acc;
    late Category incomeCat;
    late Category expenseCat;

    setUp(() async {
      acc = await accountRepo.create(name: 'Dompet', type: AccountType.cash);
      incomeCat = await categoryRepo.create(
        name: 'Gaji T',
        type: CategoryType.income,
      );
      expenseCat = await categoryRepo.create(
        name: 'Makan',
        type: CategoryType.expense,
      );
    });

    test('income dan expense per periode (minor unit)', () async {
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 100000,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 1, 5),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 25000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 10),
      );

      final report = await reportsRepo.incomeVsExpense();
      expect(report.incomeMinorUnit, 100000);
      expect(report.expenseMinorUnit, 25000);
      expect(report.isComplete, isTrue);
    });

    test('transfer tidak mempengaruhi income/expense', () async {
      final other = await accountRepo.create(
        name: 'Bank',
        type: AccountType.bank,
      );
      await transactionRepo.transfer(
        fromAccountId: acc.id,
        toAccountId: other.id,
        amount: 500000,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 100000,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 1, 2),
      );

      final report = await reportsRepo.incomeVsExpense();
      expect(report.incomeMinorUnit, 100000);
      expect(report.expenseMinorUnit, 0);
    });

    test('batas tanggal inklusif', () async {
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
        date: DateTime(2026, 1, 31),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 40000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 2, 1),
      );

      final report = await reportsRepo.incomeVsExpense(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );
      expect(report.expenseMinorUnit, 30000);
    });
  });

  group('multi-currency & konversi ke IDR', () {
    late Account idrAcc;
    late Account usdAcc;
    late Category makan;

    setUp(() async {
      idrAcc = await accountRepo.create(name: 'Dompet', type: AccountType.cash);
      usdAcc = await accountRepo.create(
        name: 'USD',
        type: AccountType.bank,
        currency: 'USD',
      );
      makan = await categoryRepo.create(
        name: 'Makan',
        type: CategoryType.expense,
      );
      await exchangeRateDao.upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: 'USD',
          toCurrency: const Value('IDR'),
          rate: 16000,
        ),
      );
    });

    test('nilai tersimpan tidak berubah setelah konversi', () async {
      final usdTx = await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100, // $1.00
        accountId: usdAcc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 1),
      );
      final report = await reportsRepo.expenseByCategory();
      expect(report.categories.single.totalMinorUnit, 16000);
      // Konversi display-only: nilai tersimpan tetap 100 minor USD.
      expect((await transactionDao.getById(usdTx.id))!.amount, 100);
    });

    test('campuran IDR + USD dijumlah dalam IDR', () async {
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 10000, // Rp 10.000
        accountId: idrAcc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100, // $1.00 -> Rp 16.000
        accountId: usdAcc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 2),
      );

      final report = await reportsRepo.expenseByCategory();
      expect(report.categories.single.totalMinorUnit, 26000);
      expect(report.isComplete, isTrue);
    });

    test('precision: rate REAL dibulatkan ke minor unit target', () async {
      // $1.00 (100 minor USD) * rate 16000.5 = 16000.5 IDR -> dibulatkan 16001.
      await exchangeRateDao.upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: 'USD',
          toCurrency: const Value('IDR'),
          rate: 16000.5,
        ),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100,
        accountId: usdAcc.id,
        categoryId: makan.id,
        date: DateTime(2026, 1, 1),
      );

      final report = await reportsRepo.expenseByCategory();
      expect(report.categories.single.totalMinorUnit, 16001);
    });
  });

  group('missing rate', () {
    test(
      'expenseByCategory: akun tanpa rate ditandai, bukan rate palsu',
      () async {
        final acc = await accountRepo.create(
          name: 'Dompet',
          type: AccountType.cash,
        );
        final usdAcc = await accountRepo.create(
          name: 'USD',
          type: AccountType.bank,
          currency: 'USD',
        );
        final makan = await categoryRepo.create(
          name: 'Makan',
          type: CategoryType.expense,
        );
        await transactionRepo.add(
          type: TransactionType.expense,
          amount: 10000,
          accountId: acc.id,
          categoryId: makan.id,
          date: DateTime(2026, 1, 1),
        );
        await transactionRepo.add(
          type: TransactionType.expense,
          amount: 100,
          accountId: usdAcc.id,
          categoryId: makan.id,
          date: DateTime(2026, 1, 2),
        );
        // Tanpa rate USD -> IDR.

        final report = await reportsRepo.expenseByCategory();
        expect(report.categories.single.totalMinorUnit, 10000); // hanya IDR
        expect(report.isComplete, isFalse);
        expect(report.missingRateCurrencies, ['USD']);
      },
    );

    test('incomeVsExpense: akun tanpa rate ditandai', () async {
      final acc = await accountRepo.create(
        name: 'Dompet',
        type: AccountType.cash,
      );
      final usdAcc = await accountRepo.create(
        name: 'USD',
        type: AccountType.bank,
        currency: 'USD',
      );
      final gaji = await categoryRepo.create(
        name: 'Gaji T',
        type: CategoryType.income,
      );
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 100000,
        accountId: acc.id,
        categoryId: gaji.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 100,
        accountId: usdAcc.id,
        categoryId: gaji.id,
        date: DateTime(2026, 1, 2),
      );

      final report = await reportsRepo.incomeVsExpense();
      expect(report.incomeMinorUnit, 100000);
      expect(report.isComplete, isFalse);
      expect(report.missingRateCurrencies, ['USD']);
    });
  });
}
