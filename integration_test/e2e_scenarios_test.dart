
// E2E skenario dari docs/E2E-TEST-SCENARIOS.md, dijalankan lewat UI NYATA
// (VExpenseApp + router + drift di atas sqlite3 nyata, bukan in-memory).
//
// Batas yang jujur: di VPS headless ini (`flutter_tester`, tidak ada /dev/kvm,
// emulator tidak terpasang) yang dibuktikan adalah seluruh widget tree + router
// + database file nyata dalam satu proses, BUKAN proses Android yang
// di-install ulang. Itu sebabnya langkah "restart app" di dokumen diterjemahkan
// menjadi: bongkar tree, lalu bangun ulang tree baru di atas file database +
// prefs yang sama — persis yang terjadi saat user force-close lalu buka lagi.
// APK/Android nyata tetap perlu uji manual.
//
// Jalankan (WAJIB pakai device, integration_test tidak jalan di flutter_tester):
//   xvfb-run -a flutter test integration_test/e2e_scenarios_test.dart -d linux
// Di CI/host dengan emulator: `-d <emulator-id>` atau `-d android`.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v_expense/app/v_expense_app.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/core/settings/settings_providers.dart';
import 'package:v_expense/features/accounts/accounts_screen.dart';
import 'package:v_expense/features/dashboard/dashboard_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late File dbFile;
  late SharedPreferences prefs;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('vexpense_e2e_');
    dbFile = File('${tmpDir.path}/v_expense.sqlite');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // Instalasi baru: onboarding belum selesai → app harus mendarat di
    // /onboarding, bukan /dashboard.
    await prefs.remove('onboarding.completed');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  AppDatabase openDb() => AppDatabase.forTesting(NativeDatabase(dbFile));

  /// Tree aplikasi baru di atas file database + prefs yang sama.
  Widget buildApp(AppDatabase db) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
    child: const VExpenseApp(),
  );

  /// Flush timer 0-delay drift sebelum tree dibongkar (pola test lain).
  Future<void> settleDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  /// Baris transaksi pertama di daftar (key `tx.item.<id>`).
  Finder txTile() => find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('tx.item.') &&
        !(w.key as ValueKey<String>).value.endsWith('.amount'),
  );

  String labelText(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  /// Isi AmountField — widget custom, jadi tulis ke TextField di dalamnya.
  Future<void> typeAmount(WidgetTester tester, Key key, String value) async {
    final field = find.descendant(
      of: find.byKey(key),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  testWidgets('E2E-1 saldo akun & total dashboard sinkron setelah '
      'create → edit → delete → restart', (tester) async {
    var db = openDb();

    // --- Boot instalasi baru → onboarding, bukan dashboard ---
    await tester.pumpWidget(buildApp(db));
    await tester.pumpAndSettle();
    expect(find.text('Selamat datang'), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);

    // --- 1. Selesaikan onboarding: akun "Tunai" otomatis dibuat ---
    await tester.tap(find.byKey(const Key('onboarding.skip')));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);

    // Saldo awal 0 + kosong.
    expect(labelText(tester, const Key('dashboard.total')), 'Rp 0');
    expect(find.byKey(const Key('dashboard.empty')), findsOneWidget);

    // --- 2. Isi opening balance akun Tunai = 1.000.000 lewat UI Akun ---
    await tester.tap(find.byKey(const Key('dashboard.goto.accounts')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget);

    await tester.tap(find.text('Tunai'));
    await tester.pumpAndSettle();
    await typeAmount(tester, const Key('account.form.balance'), '1.000.000');
    await tester.tap(find.byKey(const Key('account.form.save')));
    await tester.pumpAndSettle();

    // Balik ke dashboard: total = opening balance.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(labelText(tester, const Key('dashboard.total')), 'Rp 1.000.000');

    // --- 3. Catat expense 50.000 lewat form transaksi nyata ---
    await tester.tap(find.byKey(const Key('dashboard.quick.add')));
    await tester.pumpAndSettle();
    await typeAmount(tester, const Key('transaction.form.amount'), '50.000');
    await tester.tap(find.text('Makan & Minum'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transaction.form.save')));
    await tester.pumpAndSettle();

    // --- 4. Saldo turun 50.000, empty state hilang ---
    expect(labelText(tester, const Key('dashboard.total')), 'Rp 950.000');
    expect(find.byKey(const Key('dashboard.empty')), findsNothing);

    // --- 5. Edit jadi income 50.000 (reversal, bukan hitung dua kali) ---
    await tester.tap(find.byKey(const Key('dashboard.goto.transactions')));
    await tester.pumpAndSettle();
    // Buka detail baris transaksi pertama (key `tx.item.<id>`).
    await tester.tap(txTile());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tx.detail.edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pemasukan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaji'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transaction.form.save')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 1.000.000 + 50.000 (expense lama sudah dibalik).
    expect(labelText(tester, const Key('dashboard.total')), 'Rp 1.050.000');

    // --- 6. Hapus transaksi → kembali persis ke nilai awal ---
    await tester.tap(find.byKey(const Key('dashboard.goto.transactions')));
    await tester.pumpAndSettle();
    await tester.tap(txTile());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tx.detail.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tx.delete.confirm')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(labelText(tester, const Key('dashboard.total')), 'Rp 1.000.000');
    expect(find.byKey(const Key('dashboard.empty')), findsOneWidget);

    // --- 7. "Restart": bongkar tree, tutup DB, buka file yang sama lagi ---
    await settleDown(tester);
    await db.close();
    db = openDb();
    await tester.pumpWidget(buildApp(db));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(labelText(tester, const Key('dashboard.total')), 'Rp 1.000.000');
    expect(find.byKey(const Key('dashboard.empty')), findsOneWidget);

    await settleDown(tester);
    await db.close();
    // Database benar-benar tersimpan ke disk, bukan state in-memory.
    expect(dbFile.existsSync(), isTrue);
  });

  testWidgets('E2E-2 satu kurs dipakai di semua layar; transfer '
      'same-currency tidak mengubah total portofolio', (tester) async {
    final db = openDb();
    // Seed lewat repository (jalur data yang sama dipakai UI).
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    final repo = container.read(accountRepositoryProvider);
    final idr = await repo.create(
      name: 'Dompet IDR',
      type: AccountType.cash,
      openingBalance: 500000,
    );
    // USD 100,00 → minor unit 2 = 10000.
    final usd = await repo.create(
      name: 'Bank USD',
      type: AccountType.bank,
      currency: 'USD',
      openingBalance: 10000,
    );
    await db.exchangeRateDao.upsert(
      ExchangeRatesCompanion.insert(
        fromCurrency: 'USD',
        toCurrency: const Value('IDR'),
        rate: 16000,
      ),
    );
    // USD 10,00 → minor unit 2 = 1000. Expense di akun USD.
    final categoryId = (await container
            .read(categoryRepositoryProvider)
            .getAll())
        .firstWhere((c) => c.name == 'Makan & Minum')
        .id;
    await container
        .read(transactionRepositoryProvider)
        .add(
          type: TransactionType.expense,
          amount: 1000,
          accountId: usd.id,
          categoryId: categoryId,
          date: DateTime.now(),
        );
    final idr2 = await repo.create(
      name: 'Dompet IDR 2',
      type: AccountType.cash,
      openingBalance: 0,
    );

    // Transfer beda currency ditolak (batas MVP) — bukan bug, tapi kontrak.
    await expectLater(
      container
          .read(transactionRepositoryProvider)
          .transfer(
            fromAccountId: idr.id,
            toAccountId: usd.id,
            amount: 200000,
            date: DateTime.now(),
          ),
      throwsArgumentError,
      reason: 'PRD: transfer beda currency belum didukung di MVP',
    );

    // Transfer same-currency dipindah-pindahkan saja: total portofolio TIDAK
    // boleh berubah (bukan income/expense).
    await container
        .read(transactionRepositoryProvider)
        .transfer(
          fromAccountId: idr.id,
          toAccountId: idr2.id,
          amount: 200000,
          date: DateTime.now(),
        );

    await container.read(settingsStorageProvider).setOnboardingCompleted(true);
    container.dispose();

    await tester.pumpWidget(buildApp(db));
    await tester.pumpAndSettle();

    // Rp 500.000 (IDR) + USD 90 × 16.000 = Rp 1.440.000 → Rp 1.940.000.
    // Satu kurs dipakai di dashboard; nilai mentah USD tidak pernah
    // dijumlah langsung ke IDR.
    expect(labelText(tester, const Key('dashboard.total')), 'Rp 1.940.000');
    expect(find.byKey(const Key('dashboard.rate.missing')), findsNothing);
    // Transfer tidak menambah/mengurangi total portofolio (checked di bawah
    // lewat restart: nilainya harus identik).

    // Layar Akun menampilkan saldo USD di satuan USD (tidak dikonversi).
    await tester.tap(find.byKey(const Key('dashboard.goto.accounts')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget);
    // Layar Akun menampilkan nominal dalam currency akun masing-masing
    // (IDR tanpa desimal, USD 2 desimal) — bukan dipaksa jadi IDR.
    // 500.000 − 200.000 transfer = 300.000; akun tujuan 200.000.
    expect(find.text('Rp 300.000'), findsOneWidget);
    expect(find.text('Rp 200.000'), findsOneWidget);
    // USD 100,00 − expense USD 10,00 = USD 90,00 (saldo berjalan, bukan
    // saldo awal). Ditampilkan di satuan USD tanpa dikonversi ke IDR.
    expect(find.text(r'$ 90,00'), findsOneWidget);

    // --- Restart: kurs & nilai tetap konsisten ---
    await settleDown(tester);
    await db.close();
    final db2 = openDb();
    await tester.pumpWidget(buildApp(db2));
    await tester.pumpAndSettle();
    expect(labelText(tester, const Key('dashboard.total')), 'Rp 1.940.000');

    await settleDown(tester);
    await db2.close();
  });
}
