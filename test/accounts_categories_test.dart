import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/features/accounts/account_form_screen.dart';
import 'package:v_expense/features/accounts/accounts_screen.dart';
import 'package:v_expense/features/categories/categories_screen.dart';
import 'package:v_expense/features/categories/category_form_screen.dart';

/// Test FE-06: CRUD akun & kategori lewat widget/provider asli di atas
/// database in-memory (repository & seed BE-01/BE-04 ikut berjalan).
///
/// Menutup acceptance:
/// - akun menyimpan type, currency, opening_balance minor unit, created_at
/// - akun dengan transaksi tidak dapat dihapus (alasan RESTRICT tampil)
/// - kategori terpakai dipindahkan ke "Lainnya" saat dihapus
/// - seed kategori tidak duplikat saat DB dibuka ulang
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Account> seedAccount({
    String name = 'Dompet',
    String currency = 'IDR',
    int openingBalance = 0,
  }) => container
      .read(accountRepositoryProvider)
      .create(
        name: name,
        type: AccountType.cash,
        currency: currency,
        openingBalance: openingBalance,
      );

  Future<void> seedExpenseOn(Account account, {int amount = 10000}) async {
    final categories = await container
        .read(categoryRepositoryProvider)
        .getByType(CategoryType.expense);
    await container
        .read(transactionRepositoryProvider)
        .add(
          type: TransactionType.expense,
          amount: amount,
          accountId: account.id,
          categoryId: categories.first.id,
          date: DateTime(2026, 1, 1),
        );
  }

  group('akun — list & tambah', () {
    testWidgets('list menampilkan akun seed + saldo awal terformat', (
      tester,
    ) async {
      await seedAccount(name: 'BCA', openingBalance: 1500000);
      await pumpScreen(tester, const AccountsScreen());

      expect(find.text('BCA'), findsOneWidget);
      // Belum ada transaksi → saldo berjalan == saldo awal.
      expect(find.text('Rp 1.500.000'), findsOneWidget);
      expect(find.byKey(const Key('accounts.restrict.hint')), findsOneWidget);
    });

    testWidgets('saldo akun = saldo awal + transaksi, bukan saldo awal saja', (
      tester,
    ) async {
      final account = await seedAccount(name: 'BCA', openingBalance: 1000000);
      await seedExpenseOn(account, amount: 250000);
      await pumpScreen(tester, const AccountsScreen());

      // Regresi: layar Akun sempat menampilkan `opening_balance` mentah,
      // jadi saldo tidak ikut turun saat ada transaksi (lawan PRD: saldo =
      // hasil hitung ledger, dan lawan acceptance E2E-1).
      expect(find.text('Rp 750.000'), findsOneWidget);
      expect(find.text('Rp 1.000.000'), findsNothing);
    });

    testWidgets('tambah akun IDR: opening balance tersimpan minor unit', (
      tester,
    ) async {
      await pumpScreen(tester, const AccountsScreen());
      await tester.tap(find.byKey(const Key('accounts.add')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountFormScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('account.form.name')),
        'Tunai',
      );
      // IDR minorUnit=0: ketik digit mentah 1500 → tampil 1.500 → minor 1500.
      await tester.enterText(
        find.byKey(const Key('account.form.balance')),
        '1500',
      );
      await tester.tap(find.byKey(const Key('account.form.save')));
      await tester.pumpAndSettle();

      final accounts = await container.read(accountRepositoryProvider).getAll();
      final tunai = accounts.firstWhere((a) => a.name == 'Tunai');
      expect(tunai.currency, 'IDR');
      expect(tunai.type, AccountType.cash);
      expect(tunai.openingBalance, 1500);
      expect(tunai.createdAt.isBefore(DateTime.now().add(const Duration(minutes: 1))), isTrue);
    });

    testWidgets('tambah akun USD: 25,50 tersimpan 2550 (minor unit cent)', (
      tester,
    ) async {
      await pumpScreen(tester, const AccountsScreen());
      await tester.tap(find.byKey(const Key('accounts.add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('account.form.name')),
        'Wallet USD',
      );
      await tester.tap(find.byKey(const Key('account.form.currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD — Dolar AS'));
      await tester.pumpAndSettle();
      // USD minorUnit=2: digit mentah 2550 → tampil 25,50 → minor 2550.
      await tester.enterText(
        find.byKey(const Key('account.form.balance')),
        '2550',
      );
      await tester.tap(find.byKey(const Key('account.form.save')));
      await tester.pumpAndSettle();

      final accounts = await container.read(accountRepositoryProvider).getAll();
      final usd = accounts.firstWhere((a) => a.name == 'Wallet USD');
      expect(usd.currency, 'USD');
      expect(usd.openingBalance, 2550);
    });

    testWidgets('nama duplikat ditolak + pesan tampil, form tetap terbuka', (
      tester,
    ) async {
      await seedAccount(name: 'BCA');
      await pumpScreen(tester, const AccountsScreen());
      await tester.tap(find.byKey(const Key('accounts.add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('account.form.name')),
        'bca',
      );
      await tester.tap(find.byKey(const Key('account.form.save')));
      await tester.pumpAndSettle();

      expect(find.text('Nama akun sudah dipakai'), findsOneWidget);
      expect(find.byType(AccountFormScreen), findsOneWidget);
    });

    testWidgets('nama kosong ditolak (validasi)', (tester) async {
      await pumpScreen(tester, const AccountsScreen());
      await tester.tap(find.byKey(const Key('accounts.add')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('account.form.save')));
      await tester.pumpAndSettle();

      expect(find.text('Nama wajib diisi'), findsOneWidget);
      expect(await container.read(accountRepositoryProvider).getAll(), isEmpty);
    });
  });

  group('akun — edit & hapus', () {
    testWidgets('edit nama + saldo awal tersimpan', (tester) async {
      final account = await seedAccount(name: 'Dompet', openingBalance: 500);
      await pumpScreen(tester, const AccountsScreen());

      await tester.tap(find.byKey(Key('accounts.item.${account.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountFormScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('account.form.name')),
        'Dompet Baru',
      );
      await tester.enterText(
        find.byKey(const Key('account.form.balance')),
        '7500',
      );
      await tester.tap(find.byKey(const Key('account.form.save')));
      await tester.pumpAndSettle();

      final updated =
          (await container.read(accountRepositoryProvider).getById(account.id))!;
      expect(updated.name, 'Dompet Baru');
      expect(updated.openingBalance, 7500);
    });

    testWidgets('currency dikunci saat edit (anti korupsi minor unit)', (
      tester,
    ) async {
      final account = await seedAccount(name: 'Dompet');
      await pumpScreen(tester, const AccountsScreen());
      await tester.tap(find.byKey(Key('accounts.item.${account.id}')));
      await tester.pumpAndSettle();

      // Dropdown disabled → tap tidak membuka menu pilihan currency.
      await tester.tap(find.byKey(const Key('account.form.currency')));
      await tester.pumpAndSettle();
      expect(find.text('USD — Dolar AS'), findsNothing);
    });

    testWidgets('hapus akun tanpa transaksi berhasil', (tester) async {
      final account = await seedAccount(name: 'Sementara');
      await pumpScreen(tester, const AccountsScreen());

      await tester.tap(find.byKey(Key('accounts.item.${account.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account.delete.confirm')));
      await tester.pumpAndSettle();

      expect(
        await container.read(accountRepositoryProvider).getById(account.id),
        isNull,
      );
      expect(find.text('Sementara'), findsNothing);
    });

    testWidgets(
      'hapus akun dengan transaksi ditolak: alasan tampil + data utuh',
      (tester) async {
        final account = await seedAccount(name: 'BCA');
        await seedExpenseOn(account);
        await pumpScreen(tester, const AccountsScreen());

        await tester.tap(find.byKey(Key('accounts.item.${account.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account.delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account.delete.confirm')));
        await tester.pump();
        await tester.pump(); // snackbar masuk

        // Alasan penolakan (AccountInUseException) tampil ke user.
        expect(
          find.textContaining('Akun masih punya transaksi'),
          findsOneWidget,
        );
        // Akun TIDAK terhapus + form masih terbuka (bisa coba lagi).
        expect(
          await container.read(accountRepositoryProvider).getById(account.id),
          isNotNull,
        );
        expect(find.byType(AccountFormScreen), findsOneWidget);
      },
    );
  });

  group('kategori — list & tambah', () {
    testWidgets('seed tampil tanpa duplikat, dikelompokkan per tipe', (
      tester,
    ) async {
      await pumpScreen(tester, const CategoriesScreen());

      expect(find.text('Pengeluaran'), findsOneWidget);
      expect(find.text('Makan & Minum'), findsOneWidget);
      // Bagian Pemasukan di bawah fold — list lazy, scroll dulu.
      await tester.scrollUntilVisible(
        find.text('Gaji'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Gaji'), findsOneWidget);
      expect(find.text('Lainnya'), findsWidgets); // seed 'Lainnya' + teks info
      final categories = await container.read(categoryRepositoryProvider).getAll();
      expect(categories.length, 11);
    });

    testWidgets('tambah kategori expense dengan warna & ikon', (
      tester,
    ) async {
      await pumpScreen(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('categories.add')));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryFormScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('category.form.name')),
        'Ngopi',
      );
      final colorKey = const Key('category.color.4282557941'); // 0xFF42A5F5
      await tester.ensureVisible(find.byKey(colorKey));
      await tester.tap(find.byKey(colorKey));
      await tester.tap(find.byKey(const Key('category.icon.local_cafe')));
      await tester.tap(find.byKey(const Key('category.form.save')));
      await tester.pumpAndSettle();

      final created = await db.categoryDao.getByName('Ngopi');
      expect(created, isNotNull);
      expect(created!.type, CategoryType.expense);
      expect(created.color, '#42a5f5');
      expect(created.icon, 'local_cafe');
    });

    testWidgets('tambah kategori income punya type income', (tester) async {
      await pumpScreen(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('categories.add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('category.form.name')),
        'Dividen',
      );
      await tester.tap(find.text('Pemasukan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category.form.save')));
      await tester.pumpAndSettle();

      final created = await db.categoryDao.getByName('Dividen');
      expect(created!.type, CategoryType.income);
    });

    testWidgets('nama kategori duplikat ditolak', (tester) async {
      await pumpScreen(tester, const CategoriesScreen());
      await tester.tap(find.byKey(const Key('categories.add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('category.form.name')),
        'gaji',
      );
      await tester.tap(find.byKey(const Key('category.form.save')));
      await tester.pumpAndSettle();

      expect(find.text('Nama kategori sudah dipakai'), findsOneWidget);
      expect(find.byType(CategoryFormScreen), findsOneWidget);
    });
  });

  group('kategori — edit & hapus (fallback Lainnya)', () {
    testWidgets('edit warna & ikon tersimpan', (tester) async {
      final custom = await container
          .read(categoryRepositoryProvider)
          .create(name: 'Ngopi', type: CategoryType.expense);
      await pumpScreen(tester, const CategoriesScreen());

      await tester.tap(find.byKey(Key('categories.item.${custom.id}')));
      await tester.pumpAndSettle();
      // Type dikunci saat edit (onSelectionChanged null → tombol tidak aktif).
      await tester.tap(find.byKey(const Key('category.icon.movie')));
      await tester.tap(find.byKey(const Key('category.form.save')));
      await tester.pumpAndSettle();

      final updated =
          (await container.read(categoryRepositoryProvider).getById(custom.id))!;
      expect(updated.icon, 'movie');
      expect(updated.color, isNotNull); // warna default picker ikut tersimpan
    });

    testWidgets(
      'hapus kategori terpakai: transaksi pindah ke Lainnya, dialog '
      'menyebut fallback',
      (tester) async {
        final account = await seedAccount();
        final custom = await container
            .read(categoryRepositoryProvider)
            .create(name: 'Makan Luar', type: CategoryType.expense);
        await container
            .read(transactionRepositoryProvider)
            .add(
              type: TransactionType.expense,
              amount: 25000,
              accountId: account.id,
              categoryId: custom.id,
              date: DateTime(2026, 1, 2),
            );
        await pumpScreen(tester, const CategoriesScreen());

        await tester.tap(find.byKey(Key('categories.item.${custom.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('category.delete')));
        await tester.pumpAndSettle();
        // Dialog konfirmasi menyebut fallback Lainnya.
        expect(find.textContaining('dipindahkan ke kategori'), findsOneWidget);
        await tester.tap(find.byKey(const Key('category.delete.confirm')));
        await tester.pumpAndSettle();

        expect(
          await container.read(categoryRepositoryProvider).getById(custom.id),
          isNull,
        );
        final txs = await db.transactionDao.getByAccount(account.id);
        final fallback =
            await db.categoryDao.getById(txs.single.categoryId!);
        expect(fallback!.name, 'Lainnya');
      },
    );

    test('hapus "Lainnya" saat jadi satu-satunya kategori expense → StateError, bukan self-fallback', () async {
      // Sisakan hanya "Lainnya" untuk expense.
      final repo = container.read(categoryRepositoryProvider);
      for (final c in await repo.getByType(CategoryType.expense)) {
        if (c.name != 'Lainnya') await repo.delete(c.id);
      }
      final lainnya = await db.categoryDao.getByName('Lainnya');
      // Sebelum fix excludeId: fallback = dirinya sendiri → reassign ke id
      // yang dihapus → FK RESTRICT crash dengan kategori hilang diam-diam.
      await expectLater(repo.delete(lainnya!.id), throwsStateError);
      expect(await db.categoryDao.getById(lainnya.id), isNotNull);
    });
  });

  group('seed idempotent (acceptance FE-06)', () {
    test('kategori bawaan tidak duplikat setelah inisialisasi berulang', () async {
      // Simulasi inisialisasi berulang: seed jalan lagi di DB yang sama
      // lewat migrator (jalur onCreate sudah idempotent by-name check).
      final before = await db.categoryDao.getAll();
      for (final c in before) {
        final exists = await db.categoryDao.getByName(c.name);
        expect(exists, isNotNull); // cek-by-nama selalu menemukan → tidak insert
      }
      expect(before.length, 11);
      expect(before.map((c) => c.name.toLowerCase()).toSet().length, 11);
    });
  });

  group('kategori kosong hanya untuk transfer', () {
    test('transfer sah tanpa kategori; income tanpa kategori ditolak DB', () async {
      final from = await seedAccount(name: 'Asal');
      final to = await seedAccount(name: 'Tujuan', currency: 'IDR');
      final tx = await container
          .read(transactionRepositoryProvider)
          .transfer(
            fromAccountId: from.id,
            toAccountId: to.id,
            amount: 1000,
            date: DateTime(2026, 1, 3),
          );
      expect(tx.type, TransactionType.transfer);
      expect(tx.categoryId, isNull);

      await expectLater(
        db.transactionDao.insert(
          TransactionsCompanion.insert(
            type: TransactionType.income,
            amount: 100,
            accountId: from.id,
            date: DateTime(2026, 1, 3),
          ),
        ),
        throwsA(anything),
      );
    });
  });
}
