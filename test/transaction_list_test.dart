import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart'
    show TransactionFilter;
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/features/transactions/presentation/transaction_list_screen.dart';
import 'package:v_expense/features/transfers/transfer_form_screen.dart';

/// Test FE-05: daftar transaksi (filter tipe + search, konfirmasi hapus,
/// state kosong) + form transfer same-currency (sukses, validasi) di atas
/// database in-memory — repository, seed, dan use case atomik ikut berjalan.
///
/// Menutup acceptance:
/// - hapus tanpa konfirmasi tidak berjalan; konfirmasi → saldo kembali
/// - hapus transfer menghilangkan kedua sisi (satu baris)
/// - transfer = debit asal + kredit tujuan dalam SATU baris database
/// - tujuan hanya akun se-currency; akun sama & beda currency ditolak
/// - filter + search bersamaan tanpa mengubah data
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

  /// Dispose autoDispose stream provider (drift StreamQueryStore.markAsClosed)
  /// membuat timer 0-delay yang TIDAK ter-flush oleh pumpAndSettle — clock
  /// fake async harus benar-benar maju (pola sama dengan transaction_form_test).
  Future<void> flushTimers(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  /// pumpAndSettle + flush timer 0-delay drift.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await flushTimers(tester);
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TransactionListScreen()),
      ),
    );
    await settle(tester);
  }

  Future<Account> seedAccount({
    required String name,
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

  Future<Category> categoryByName(String name) async {
    final all = await container.read(categoryRepositoryProvider).getAll();
    return all.firstWhere((c) => c.name == name);
  }

  Future<Transaction> seedTx(
    Account account, {
    TransactionType type = TransactionType.expense,
    int amount = 10000,
    String category = 'Makan & Minum',
    DateTime? date,
    String? description,
  }) async {
    final cat = await categoryByName(category);
    return container
        .read(transactionRepositoryProvider)
        .add(
          type: type,
          amount: amount,
          accountId: account.id,
          categoryId: cat.id,
          date: date ?? DateTime(2026, 1, 10),
          description: description,
        );
  }

  group('daftar transaksi', () {
    testWidgets('state kosong saat belum ada transaksi', (tester) async {
      await seedAccount(name: 'Dompet');
      await pumpList(tester);
      expect(find.byKey(const Key('tx.empty')), findsOneWidget);
    });

    testWidgets('filter tipe + search bersamaan, data tidak berubah', (
      tester,
    ) async {
      final dompet = await seedAccount(name: 'Dompet');
      await seedTx(dompet, description: 'Nasi goreng');
      await seedTx(
        dompet,
        type: TransactionType.income,
        category: 'Gaji',
        description: 'Gaji bulanan',
      );
      await pumpList(tester);

      // Semua tampil (2 item).
      expect(find.textContaining('Nasi goreng'), findsOneWidget);
      expect(find.textContaining('Gaji bulanan'), findsOneWidget);
      final countBefore = await db.transactionDao.count();

      // Search 'nasi' → hanya 1.
      await tester.enterText(find.byKey(const Key('tx.search')), 'nasi');
      await settle(tester);
      expect(find.textContaining('Nasi goreng'), findsOneWidget);
      expect(find.textContaining('Gaji bulanan'), findsNothing);

      // + filter tipe expense → tetap 1 (search & filter hidup bersama).
      await tester.tap(find.byKey(const Key('tx.filter.open')));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('tx.filter.type')),
          matching: find.text('Keluar'),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('tx.filter.close')));
      await settle(tester);
      expect(find.textContaining('Nasi goreng'), findsOneWidget);
      expect(find.textContaining('Gaji bulanan'), findsNothing);

      // + filter tipe income → kosong (kombinasi tidak cocok).
      await tester.tap(find.byKey(const Key('tx.filter.open')));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('tx.filter.type')),
          matching: find.text('Masuk'),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('tx.filter.close')));
      await settle(tester);
      expect(find.byKey(const Key('tx.empty')), findsOneWidget);

      // Filter/search hanya query — jumlah baris DB tidak berubah.
      expect(await db.transactionDao.count(), countBefore);
    });

    testWidgets('tap item membuka detail; batal hapus tidak menghapus', (
      tester,
    ) async {
      final dompet = await seedAccount(name: 'Dompet', openingBalance: 50000);
      final tx = await seedTx(dompet, amount: 10000);
      await pumpList(tester);
      final balanceBefore = await container
          .read(transactionRepositoryProvider)
          .balanceForAccount(dompet.id);

      await tester.tap(find.byKey(Key('tx.item.${tx.id}')));
      await settle(tester);
      expect(find.byKey(const Key('tx.detail.amount')), findsOneWidget);
      expect(find.byKey(const Key('tx.detail.delete')), findsOneWidget);

      // Buka konfirmasi, lalu BATAL → tidak ada mutasi.
      await tester.tap(find.byKey(const Key('tx.detail.delete')));
      await settle(tester);
      expect(find.text('Hapus transaksi?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tx.delete.cancel')));
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await settle(tester);

      expect(await db.transactionDao.getById(tx.id), isNotNull);
      expect(
        await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(dompet.id),
        balanceBefore,
      );
    });

    testWidgets('konfirmasi hapus: baris hilang + saldo kembali semula', (
      tester,
    ) async {
      final dompet = await seedAccount(name: 'Dompet', openingBalance: 50000);
      final tx = await seedTx(dompet, amount: 10000);
      await pumpList(tester);

      await tester.tap(find.byKey(Key('tx.item.${tx.id}')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('tx.detail.delete')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('tx.delete.confirm')));
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await settle(tester);

      // Saldo kembali ke kondisi sebelum transaksi (opening saja).
      expect(await db.transactionDao.getById(tx.id), isNull);
      expect(
        await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(dompet.id),
        50000,
      );
      // Daftar refresh otomatis via stream → empty state.
      expect(find.byKey(const Key('tx.empty')), findsOneWidget);
    });
  });

  group('transfer', () {
    Future<void> pumpTransferForm(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: TransferFormScreen()),
        ),
      );
      await settle(tester);
    }

    Future<void> selectDropdown(
      WidgetTester tester,
      Key dropdownKey,
      String itemText,
    ) async {
      await tester.tap(find.byKey(dropdownKey));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<int>),
          matching: find.textContaining(itemText),
        ).last,
      );
      await settle(tester);
    }

    Future<void> scrollToSave(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('transfer.form.save')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets('sukses: satu baris debit asal + kredit tujuan', (
      tester,
    ) async {
      await seedAccount(name: 'Dompet', openingBalance: 100000);
      await seedAccount(name: 'Bank', openingBalance: 0);
      await pumpTransferForm(tester);

      await selectDropdown(tester, const Key('transfer.form.from'), 'Dompet');
      await selectDropdown(tester, const Key('transfer.form.to'), 'Bank');
      await tester.enterText(
        find.byKey(const Key('transfer.form.amount')),
        '25000',
      );
      await scrollToSave(tester);
      await tester.tap(find.byKey(const Key('transfer.form.save')));
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await settle(tester);

      // SATU baris database bertipe transfer, tanpa kategori.
      final all = await db.transactionDao.getFiltered(const TransactionFilter());
      expect(all, hasLength(1));
      final transfer = all.single;
      expect(transfer.type, TransactionType.transfer);
      expect(transfer.amount, 25000); // amount tunggal minor unit
      expect(transfer.categoryId, isNull);

      // Efek dua sisi dari satu baris: saldo asal berkurang, tujuan bertambah.
      final accounts = await container.read(accountRepositoryProvider).getAll();
      final dompet = accounts.firstWhere((a) => a.name == 'Dompet');
      final bank = accounts.firstWhere((a) => a.name == 'Bank');
      expect(
        await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(dompet.id),
        75000,
      );
      expect(
        await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(bank.id),
        25000,
      );
    });

    testWidgets('akun tujuan hanya menawarkan currency sama', (tester) async {
      await seedAccount(name: 'Dompet');
      await seedAccount(name: 'Bank');
      await seedAccount(name: 'USD Wallet', currency: 'USD');
      await pumpTransferForm(tester);

      await selectDropdown(tester, const Key('transfer.form.from'), 'Dompet');
      await tester.tap(find.byKey(const Key('transfer.form.to')));
      await settle(tester);

      // USD Wallet tidak muncul sebagai opsi tujuan (beda currency).
      expect(find.textContaining('USD Wallet'), findsNothing);
      expect(find.textContaining('Bank · IDR'), findsOneWidget);
    });

    testWidgets('akun asal == tujuan ditolak validasi, tidak ada baris', (
      tester,
    ) async {
      await seedAccount(name: 'Dompet');
      await seedAccount(name: 'Bank');
      await pumpTransferForm(tester);

      await selectDropdown(tester, const Key('transfer.form.from'), 'Dompet');
      // 'Dompet' sengaja tidak ditawarkan sebagai tujuan; simpan tanpa
      // memilih tujuan → validator menolak.
      await tester.enterText(
        find.byKey(const Key('transfer.form.amount')),
        '25000',
      );
      await scrollToSave(tester);
      await tester.tap(find.byKey(const Key('transfer.form.save')));
      await settle(tester);
      expect(find.text('Akun tujuan wajib dipilih'), findsOneWidget);
      expect(await db.transactionDao.count(), 0);
    });

    testWidgets('hapus transfer dari daftar: kedua sisi hilang atomik', (
      tester,
    ) async {
      final dompet = await seedAccount(name: 'Dompet', openingBalance: 100000);
      final bank = await seedAccount(name: 'Bank', openingBalance: 0);
      final transfer = await container
          .read(transactionRepositoryProvider)
          .transfer(
            fromAccountId: dompet.id,
            toAccountId: bank.id,
            amount: 25000,
            date: DateTime(2026, 1, 15),
            description: 'Pindah dana',
          );
      await pumpList(tester);

      await tester.tap(find.byKey(Key('tx.item.${transfer.id}')));
      await settle(tester);
      // Detail transfer: asal → tujuan, tanpa kategori, tanpa tombol edit.
      expect(find.byKey(const Key('tx.detail.from')), findsOneWidget);
      expect(find.byKey(const Key('tx.detail.to')), findsOneWidget);
      expect(find.byKey(const Key('tx.detail.edit')), findsNothing);

      await tester.tap(find.byKey(const Key('tx.detail.delete')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('tx.delete.confirm')));
      await settle(tester);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await settle(tester);

      // Tidak ada orphan di sisi mana pun: baris hilang, saldo kembali.
      expect(await db.transactionDao.getById(transfer.id), isNull);
      expect(await db.transactionDao.getIncomingTransfers(bank.id), isEmpty);
      expect(
        await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(dompet.id),
        100000,
      );
      expect(
        await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(bank.id),
        0,
      );
    });
  });
}
