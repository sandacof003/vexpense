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
import 'package:v_expense/features/reports/presentation/reports_screen.dart';

/// Test FE-07: reports (pie Expense by Category + bar Income vs Expense)
/// di atas DB in-memory — repository BE-05 asli ikut berjalan.
///
/// Menutup acceptance:
/// - hanya expense yang masuk pie chart
/// - income dan expense masuk bar chart; transfer tidak dihitung
/// - multi-currency dikonversi ke IDR pakai rate tersimpan; tanpa rate →
///   peringatan (bukan rate palsu)
/// - filter tanggal inklusif; ganti rentang memuat ulang kedua chart
/// - periode tanpa data → empty state, bukan chart rusak
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

  Future<void> pumpReports(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Teardown widget tree + flush timer drift (pola dashboard_screen_test).
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
  }) => container
      .read(accountRepositoryProvider)
      .create(name: name, type: type, currency: currency);

  Future<Category> seedCategory(String name, CategoryType type) => container
      .read(categoryRepositoryProvider)
      .create(name: name, type: type);

  Future<Transaction> seedTx({
    required TransactionType type,
    required int amount,
    required int accountId,
    required DateTime date,
    required int categoryId,
  }) => container
      .read(transactionRepositoryProvider)
      .add(
        type: type,
        amount: amount,
        accountId: accountId,
        categoryId: categoryId,
        date: date,
      );

  Future<void> seedRate(String from, String to, double rate) => db
      .exchangeRateDao
      .upsert(
        ExchangeRatesCompanion.insert(
          fromCurrency: from,
          toCurrency: Value(to),
          rate: rate,
        ),
      );

  testWidgets('empty state saat periode tanpa data', (tester) async {
    await pumpReports(tester);

    expect(find.byKey(const Key('reports.pie.empty')), findsOneWidget);
    expect(find.byKey(const Key('reports.bar.empty')), findsOneWidget);

    await settleDown(tester);
  });

  testWidgets('pie hanya expense; bar tampilkan income vs expense', (
    tester,
  ) async {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 10);
    final acc = await seedAccount();
    final gaji = await seedCategory('Gaji R', CategoryType.income);
    final makan = await seedCategory('Makan R', CategoryType.expense);
    final transport = await seedCategory('Transport R', CategoryType.expense);

    await seedTx(
      type: TransactionType.income,
      amount: 900000,
      accountId: acc.id,
      date: date,
      categoryId: gaji.id,
    );
    await seedTx(
      type: TransactionType.expense,
      amount: 150000,
      accountId: acc.id,
      date: date,
      categoryId: makan.id,
    );
    await seedTx(
      type: TransactionType.expense,
      amount: 50000,
      accountId: acc.id,
      date: date,
      categoryId: transport.id,
    );

    await pumpReports(tester);

    // Bar: income & expense.
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.income'))).data,
      'Rp 900.000',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.expense'))).data,
      'Rp 200.000',
    );

    // Pie: hanya kategori expense, income tidak muncul di legenda.
    expect(find.byKey(Key('reports.legend.${makan.id}')), findsOneWidget);
    expect(find.byKey(Key('reports.legend.${transport.id}')), findsOneWidget);
    expect(find.byKey(Key('reports.legend.${gaji.id}')), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key('reports.legend.${makan.id}')),
              matching: find.byType(Text),
            ).at(1),
          )
          .data,
      'Rp 150.000',
    );

    await settleDown(tester);
  });

  testWidgets('transfer tidak dihitung sebagai income/expense', (
    tester,
  ) async {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 10);
    final from = await seedAccount(name: 'Dompet T');
    final to = await seedAccount(name: 'Bank T', type: AccountType.bank);
    final cat = await seedCategory('Makan T2', CategoryType.expense);

    await seedTx(
      type: TransactionType.expense,
      amount: 75000,
      accountId: from.id,
      date: date,
      categoryId: cat.id,
    );
    await container
        .read(transactionRepositoryProvider)
        .transfer(
          fromAccountId: from.id,
          toAccountId: to.id,
          amount: 500000,
          date: date,
        );

    await pumpReports(tester);

    // Transfer 500.000 tidak masuk income maupun expense.
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.income'))).data,
      'Rp 0',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.expense'))).data,
      'Rp 75.000',
    );

    await settleDown(tester);
  });

  testWidgets('multi-currency dikonversi ke IDR pakai rate tersimpan', (
    tester,
  ) async {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 10);
    final idr = await seedAccount(name: 'Dompet M');
    final usd = await seedAccount(
      name: 'Bank USD M',
      type: AccountType.bank,
      currency: 'USD',
    );
    final cat = await seedCategory('Makan M', CategoryType.expense);
    await seedRate('USD', 'IDR', 16000);

    await seedTx(
      type: TransactionType.expense,
      amount: 100000,
      accountId: idr.id,
      date: date,
      categoryId: cat.id,
    );
    // $10.00 (minor unit 2) → Rp 160.000
    await seedTx(
      type: TransactionType.expense,
      amount: 1000,
      accountId: usd.id,
      date: date,
      categoryId: cat.id,
    );

    await pumpReports(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.expense'))).data,
      'Rp 260.000',
    );
    expect(find.byKey(const Key('reports.rate.missing')), findsNothing);

    await settleDown(tester);
  });

  testWidgets('tanpa rate → peringatan, bukan nilai palsu', (tester) async {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 10);
    final acc = await seedAccount(
      name: 'Bank USD X',
      type: AccountType.bank,
      currency: 'USD',
    );
    final cat = await seedCategory('Makan X', CategoryType.expense);
    await seedTx(
      type: TransactionType.expense,
      amount: 1000,
      accountId: acc.id,
      date: date,
      categoryId: cat.id,
    );

    await pumpReports(tester);

    expect(find.byKey(const Key('reports.rate.missing')), findsWidgets);
    // Expense USD tanpa rate tidak masuk pie (bukan dikonversi rate palsu).
    expect(find.byKey(const Key('reports.pie.empty')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.expense'))).data,
      'Rp 0',
    );

    await settleDown(tester);
  });

  testWidgets('ganti preset rentang memuat ulang kedua chart', (
    tester,
  ) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 10);
    final lastYear = DateTime(now.year - 1, 6, 15);
    final acc = await seedAccount();
    final cat = await seedCategory('Makan F', CategoryType.expense);

    await seedTx(
      type: TransactionType.expense,
      amount: 30000,
      accountId: acc.id,
      date: thisMonth,
      categoryId: cat.id,
    );
    await seedTx(
      type: TransactionType.expense,
      amount: 70000,
      accountId: acc.id,
      date: lastYear,
      categoryId: cat.id,
    );

    await pumpReports(tester);

    // Default bulan ini: hanya transaksi bulan ini.
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.expense'))).data,
      'Rp 30.000',
    );

    // Preset "Tahun ini" (masih bulan ini saja, lastYear di luar).
    await tester.tap(find.byKey(const Key('reports.preset.year')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.expense'))).data,
      'Rp 30.000',
    );

    // "30 hari terakhir": transaksi bulan lalu juga di luar.
    await tester.tap(find.byKey(const Key('reports.preset.last30')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('reports.bar.expense'))).data,
      'Rp 30.000',
    );

    await settleDown(tester);
  });

  test('provider mengirim from/to inklusif sesuai rentang aktif', () async {
    final sub1 = container.listen(expenseByCategoryProvider, (_, _) {});
    final sub2 = container.listen(incomeVsExpenseRangeProvider, (_, _) {});
    addTearDown(sub1.close);
    addTearDown(sub2.close);

    final acc = await seedAccount();
    final cat = await seedCategory('Makan B', CategoryType.expense);
    final incomeCat = await seedCategory('Gaji B', CategoryType.income);

    // Batas rentang: 1 hari sebelum, tepat di from, tepat di to, 1 hari
    // sesudah. Hanya dua transaksi di tengah yang boleh terhitung.
    final from = DateTime(2026, 3, 1);
    final to = DateTime(
      2026,
      3,
      31,
      23,
      59,
      59,
      999,
      999,
    );
    await seedTx(
      type: TransactionType.expense,
      amount: 11111,
      accountId: acc.id,
      date: from.subtract(const Duration(days: 1)),
      categoryId: cat.id,
    );
    await seedTx(
      type: TransactionType.expense,
      amount: 22222,
      accountId: acc.id,
      date: from,
      categoryId: cat.id,
    );
    await seedTx(
      type: TransactionType.expense,
      amount: 33333,
      accountId: acc.id,
      date: to,
      categoryId: cat.id,
    );
    await seedTx(
      type: TransactionType.income,
      amount: 44444,
      accountId: acc.id,
      date: to.add(const Duration(days: 1)),
      categoryId: incomeCat.id,
    );

    container.read(reportsRangeProvider.notifier).state = (from, to);
    final pie = await container.read(expenseByCategoryProvider.future);
    final bar = await container.read(incomeVsExpenseRangeProvider.future);

    // Batas from & to inklusif; di luar batas tidak dihitung.
    expect(pie.categories.single.categoryName, 'Makan B');
    expect(pie.categories.single.totalMinorUnit, 22222 + 33333);
    expect(bar.incomeMinorUnit, 0);
    expect(bar.expenseMinorUnit, 22222 + 33333);
    expect(pie.isComplete, isTrue);
    expect(bar.isComplete, isTrue);
  });
}
