import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/core/settings/settings_providers.dart';
import 'package:v_expense/features/dashboard/dashboard_screen.dart';

/// Test FE-03: dashboard saldo/ringkasan/transaksi terbaru di atas DB
/// in-memory (repository BE-02/BE-05 asli ikut berjalan).
///
/// Menutup acceptance:
/// - saldo gabungan multi-currency dikonversi ke IDR pakai rate tersimpan
/// - akun tanpa rate IDR → state data belum lengkap (bukan rate palsu)
/// - ringkasan bulan berjalan hanya menghitung transaksi bulan ini
/// - transfer tidak mengubah total gabungan
/// - empty state saat belum ada transaksi
/// - baris transaksi terbaru menampilkan tipe/nominal/akun/kategori/tanggal
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Teardown widget tree + flush timer drift (markAsClosed) supaya
  /// invariant "pending timer" tidak gagal (pola transaction_form_test).
  Future<void> settleDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Future<Account> seedAccount({
    String name = 'Dompet',
    AccountType type = AccountType.cash,
    String currency = 'IDR',
    int openingBalance = 0,
  }) => container
      .read(accountRepositoryProvider)
      .create(
        name: name,
        type: type,
        currency: currency,
        openingBalance: openingBalance,
      );

  Future<Category> seedCategory(String name, CategoryType type) =>
      container.read(categoryRepositoryProvider).create(name: name, type: type);

  Future<Transaction> seedTx({
    required TransactionType type,
    required int amount,
    required int accountId,
    required int categoryId,
    required DateTime date,
    String? description,
  }) => container
      .read(transactionRepositoryProvider)
      .add(
        type: type,
        amount: amount,
        accountId: accountId,
        categoryId: categoryId,
        date: date,
        description: description,
      );

  Future<void> seedRate(String from, String to, double rate) =>
      db.exchangeRateDao.upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: from,
          toCurrency: Value(to),
          rate: rate,
        ),
      );

  testWidgets('saldo multi-currency dikonversi ke IDR pakai rate tersimpan', (
    tester,
  ) async {
    await seedAccount(name: 'Dompet', openingBalance: 100000);
    await seedAccount(
      name: 'Bank USD',
      type: AccountType.bank,
      currency: 'USD',
      openingBalance: 100, // $1.00 (minor unit 2)
    );
    await seedRate('USD', 'IDR', 16000);

    await pumpDashboard(tester);

    expect(
      find.byKey(const Key('dashboard.total')),
      findsOneWidget,
    ); // 100000 + (100 minor USD -> 16000 IDR)
    expect(
      tester.widget<Text>(find.byKey(const Key('dashboard.total'))).data,
      'Rp 116.000',
    );
    expect(find.byKey(const Key('dashboard.rate.missing')), findsNothing);

    await settleDown(tester);
  });

  testWidgets('akun tanpa rate IDR → state data belum lengkap', (
    tester,
  ) async {
    await seedAccount(name: 'Dompet', openingBalance: 50000);
    await seedAccount(
      name: 'Bank USD',
      type: AccountType.bank,
      currency: 'USD',
      openingBalance: 100,
    ); // rate USD→IDR sengaja TIDAK di-seed

    await pumpDashboard(tester);

    expect(find.byKey(const Key('dashboard.rate.missing')), findsOneWidget);
    // Hanya saldo IDR yang dijumlah — bukan dikonversi pakai rate palsu.
    expect(
      tester.widget<Text>(find.byKey(const Key('dashboard.total'))).data,
      'Rp 50.000',
    );

    await settleDown(tester);
  });

  testWidgets('ringkasan bulan berjalan hanya menghitung transaksi bulan ini', (
    tester,
  ) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 10);
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    final acc = await seedAccount();
    final incomeCat = await seedCategory('Gaji D', CategoryType.income);
    final expenseCat = await seedCategory('Makan D', CategoryType.expense);

    await seedTx(
      type: TransactionType.income,
      amount: 500000,
      accountId: acc.id,
      categoryId: incomeCat.id,
      date: thisMonth,
    );
    await seedTx(
      type: TransactionType.expense,
      amount: 200000,
      accountId: acc.id,
      categoryId: expenseCat.id,
      date: thisMonth,
    );
    // Transaksi bulan lalu tidak boleh masuk ringkasan bulan berjalan.
    await seedTx(
      type: TransactionType.income,
      amount: 999999,
      accountId: acc.id,
      categoryId: incomeCat.id,
      date: lastMonth,
    );

    await pumpDashboard(tester);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard.monthly.income')))
          .data,
      'Rp 500.000',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard.monthly.expense')))
          .data,
      'Rp 200.000',
    );

    await settleDown(tester);
  });

  test('transfer tidak mengubah total gabungan', () async {
    // Jaga provider autoDispose tetap hidup selama test (kalau tidak,
    // provider ter-dispose di tengah loading saat invalidate).
    final sub = container.listen(dashboardBalanceProvider, (_, _) {});
    addTearDown(sub.close);

    final from = await seedAccount(name: 'Dompet', openingBalance: 100000);
    final to = await seedAccount(
      name: 'Bank',
      type: AccountType.bank,
      openingBalance: 50000,
    );

    final before = await container.read(dashboardBalanceProvider.future);
    await container
        .read(transactionRepositoryProvider)
        .transfer(
          fromAccountId: from.id,
          toAccountId: to.id,
          amount: 30000,
          date: DateTime(2026, 1, 5),
        );
    // Invalidate supaya FutureProvider menghitung ulang dari ledger.
    container.invalidate(dashboardBalanceProvider);
    final after = await container.read(dashboardBalanceProvider.future);

    expect(before.totalMinorUnit, 150000);
    expect(after.totalMinorUnit, before.totalMinorUnit);
  });

  testWidgets('empty state saat belum ada transaksi', (tester) async {
    await pumpDashboard(tester);

    expect(find.byKey(const Key('dashboard.empty')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('dashboard.total'))).data,
      'Rp 0',
    );

    await settleDown(tester);
  });

  testWidgets('transaksi terbaru menampilkan tipe, nominal, akun, kategori, tanggal', (
    tester,
  ) async {
    final acc = await seedAccount(name: 'Dompetku');
    final cat = await seedCategory('Makan T', CategoryType.expense);
    final tx = await seedTx(
      type: TransactionType.expense,
      amount: 25000,
      accountId: acc.id,
      categoryId: cat.id,
      date: DateTime(2026, 1, 5),
      description: 'Nasi goreng',
    );

    await pumpDashboard(tester);

    final tile = find.byKey(Key('dashboard.recent.${tx.id}'));
    expect(tile, findsOneWidget);
    final subtitle = tester
        .widget<Text>(find.descendant(of: tile, matching: find.byType(Text)).at(1))
        .data!;
    // tipe + akun + kategori + tanggal (dd/MM/yyyy)
    expect(subtitle, contains('Pengeluaran'));
    expect(subtitle, contains('Dompetku'));
    expect(subtitle, contains('Makan T'));
    expect(subtitle, contains('05/01/2026'));
    // nominal (mengikuti currency akun)
    expect(
      tester
          .widget<Text>(find.byKey(Key('dashboard.recent.${tx.id}.amount')))
          .data,
      'Rp 25.000',
    );
    // deskripsi muncul di baris judul
    expect(find.text('Nasi goreng'), findsOneWidget);

    await settleDown(tester);
  });
}
