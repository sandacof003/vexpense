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
import 'package:v_expense/core/data/repositories/dashboard_repository.dart';
import 'package:v_expense/core/data/repositories/transaction_repository.dart';
import 'package:v_expense/core/data/services/currency_converter.dart';

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
  late DashboardRepository dashboardRepo;

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
    dashboardRepo = DashboardRepository(
      accountDao,
      transactionDao,
      transactionRepo,
      converter,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('convertMinorUnit (pure)', () {
    test('USD(2) -> IDR(0) pakai rate 16000', () {
      // $1.00 = 100 minor USD -> Rp 16.000 = 16000 minor IDR.
      expect(
        convertMinorUnit(
          amount: 100,
          fromMinorUnit: 2,
          toMinorUnit: 0,
          rate: 16000,
        ),
        16000,
      );
    });

    test('IDR(0) -> USD(2) pakai rate kebalikan', () {
      // Rp 16.000 = 16000 minor IDR -> $1.00 = 100 minor USD.
      expect(
        convertMinorUnit(
          amount: 16000,
          fromMinorUnit: 0,
          toMinorUnit: 2,
          rate: 1 / 16000,
        ),
        100,
      );
    });

    test('nominal 0 tetap 0', () {
      expect(
        convertMinorUnit(amount: 0, fromMinorUnit: 0, toMinorUnit: 6, rate: 1),
        0,
      );
    });

    test('minor unit sama -> perkalian rate langsung', () {
      // USD -> SGD (sama-sama 2): $1.00 * 1.35 = S$1.35 = 135 minor.
      expect(
        convertMinorUnit(
          amount: 100,
          fromMinorUnit: 2,
          toMinorUnit: 2,
          rate: 1.35,
        ),
        135,
      );
    });
  });

  group('CurrencyConverter', () {
    test('from == to identitas tanpa butuh rate', () async {
      final c = await converter.convert(5000, from: 'IDR', to: 'IDR');
      expect(c.isSuccess, isTrue);
      expect(c.amountMinorUnit, 5000);
      expect(c.rate, 1);
    });

    test('konversi sukses dengan rate tersimpan', () async {
      await exchangeRateDao.upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: 'USD',
          toCurrency: const Value('IDR'),
          rate: 16000,
        ),
      );
      final c = await converter.convert(100, from: 'USD', to: 'IDR');
      expect(c.isSuccess, isTrue);
      expect(c.amountMinorUnit, 16000);
      expect(c.rate, 16000);
    });

    test('rate hilang -> status missingRate, bukan rate palsu', () async {
      final c = await converter.convert(100, from: 'USD', to: 'IDR');
      expect(c.status, CurrencyConversionStatus.missingRate);
      expect(c.isSuccess, isFalse);
    });

    test('mata uang tidak dikenal -> unknownCurrency', () async {
      final c = await converter.convert(100, from: 'ZZZ', to: 'IDR');
      expect(c.status, CurrencyConversionStatus.unknownCurrency);
    });
  });

  group('DashboardRepository.totalBalance', () {
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
        name: 'Gaji S',
        type: CategoryType.income,
      );
      expenseCat = await categoryRepo.create(
        name: 'Makan S',
        type: CategoryType.expense,
      );
    });

    test('opening balance + income - expense', () async {
      await transactionRepo.add(
        type: TransactionType.income,
        amount: 200000,
        accountId: acc.id,
        categoryId: incomeCat.id,
        date: DateTime(2026, 1, 1),
      );
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 30000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 2),
      );

      final summary = await dashboardRepo.totalBalance('IDR');
      expect(summary.totalMinorUnit, 270000);
      expect(summary.convertedCount, 1);
      expect(summary.isComplete, isTrue);
    });

    test('multi-currency dikonversi ke IDR', () async {
      await accountRepo.create(
        name: 'USD',
        type: AccountType.bank,
        currency: 'USD',
        openingBalance: 100, // $1.00
      );
      await exchangeRateDao.upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: 'USD',
          toCurrency: const Value('IDR'),
          rate: 16000,
        ),
      );

      // Dompet = 100000 IDR, USD = 100 minor -> 16000 IDR.
      final summary = await dashboardRepo.totalBalance('IDR');
      expect(summary.totalMinorUnit, 116000);
      expect(summary.convertedCount, 2);
      expect(summary.isComplete, isTrue);
    });

    test('rate hilang -> akun ditandai, tidak pakai rate palsu', () async {
      await accountRepo.create(
        name: 'USD',
        type: AccountType.bank,
        currency: 'USD',
        openingBalance: 100,
      );
      // Tanpa insert rate USD->IDR.
      final summary = await dashboardRepo.totalBalance('IDR');
      expect(summary.convertedCount, 1); // hanya Dompet (IDR)
      expect(summary.totalMinorUnit, 100000);
      expect(summary.missingRateCurrencies, ['USD']);
      expect(summary.isComplete, isFalse);
    });

    test('transfer tidak mengubah total gabungan (net-zero)', () async {
      final from = await accountRepo.create(
        name: 'Asal',
        type: AccountType.cash,
        openingBalance: 100000,
      );
      final to = await accountRepo.create(
        name: 'Tujuan',
        type: AccountType.bank,
        openingBalance: 0,
      );

      final before = await dashboardRepo.totalBalance('IDR');
      expect(before.totalMinorUnit, 200000);

      await transactionRepo.transfer(
        fromAccountId: from.id,
        toAccountId: to.id,
        amount: 40000,
        date: DateTime(2026, 1, 1),
      );

      final after = await dashboardRepo.totalBalance('IDR');
      expect(after.totalMinorUnit, 200000); // gabungan tidak berubah
      expect(await transactionRepo.balanceForAccount(from.id), 60000);
      expect(await transactionRepo.balanceForAccount(to.id), 40000);
    });
  });

  group('DashboardRepository.recentTransactions', () {
    late Account acc;
    late Category cat;

    setUp(() async {
      acc = await accountRepo.create(name: 'A', type: AccountType.cash);
      cat = await categoryRepo.create(
        name: 'Makan R',
        type: CategoryType.expense,
      );
    });

    test('mengembalikan N terbaru, urut date DESC', () async {
      for (var i = 1; i <= 5; i++) {
        await transactionRepo.add(
          type: TransactionType.expense,
          amount: i * 100,
          accountId: acc.id,
          categoryId: cat.id,
          date: DateTime(2026, 1, i),
        );
      }

      final recent = await dashboardRepo.recentTransactions(3);
      expect(recent.length, 3);
      expect(recent.first.date, DateTime(2026, 1, 5));
      expect(recent.last.date, DateTime(2026, 1, 3));
    });

    test('limit > jumlah data -> kembalikan semua', () async {
      await transactionRepo.add(
        type: TransactionType.expense,
        amount: 100,
        accountId: acc.id,
        categoryId: cat.id,
        date: DateTime(2026, 1, 1),
      );
      final recent = await dashboardRepo.recentTransactions(10);
      expect(recent.length, 1);
    });

    test('database kosong -> list kosong', () async {
      expect(await dashboardRepo.recentTransactions(5), isEmpty);
    });
  });
}
