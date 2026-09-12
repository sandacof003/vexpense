import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart'
    show TransactionFilter;
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/features/transactions/domain/transaction_use_cases.dart';
import 'package:v_expense/features/transactions/presentation/transaction_form_screen.dart';
import 'package:v_expense/features/transactions/providers/transaction_providers.dart';

/// Test FE-04: form tambah/edit transaksi income/expense di atas database
/// in-memory (repository, seed, dan use case mutasi atomik ikut berjalan).
///
/// Menutup acceptance:
/// - transaksi tersimpan dengan amount minor unit positif; kategori wajib
/// - form hanya menawarkan kategori sesuai type
/// - edit mengubah semua field; saldo mengikuti nilai baru
/// - kegagalan tidak meninggalkan perubahan parsial (rollback)
/// - submit ganda tidak membuat duplikasi
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

  /// Tombol Simpan ada di bawah fold (ListView lazy — item belum dibangun
  /// sampai di-scroll) → scrollUntilVisible dulu. Setelah form pop, dispose
  /// autoDispose stream provider (drift StreamQueryStore.markAsClosed)
  /// membuat timer 0-delay yang TIDAK ter-flush oleh pumpAndSettle maupun
  /// pump(Duration.zero) — clock fake async harus benar-benar maju, kalau
  /// tidak invariant "pending timer" gagal dan tearDown db.close() deadlock.
  Future<void> tapSave(WidgetTester tester) async {
    final save = find.byKey(const Key('transaction.form.save'));
    await tester.scrollUntilVisible(
      save,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Future<Account> seedAccount({
    String name = 'Dompet',
    String currency = 'IDR',
  }) => container
      .read(accountRepositoryProvider)
      .create(name: name, type: AccountType.cash, currency: currency);

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

  group('create', () {
    testWidgets(
      'submit expense: tersimpan minor unit positif + kategori + akun',
      (tester) async {
        final account = await seedAccount();
        final makan = await categoryByName('Makan & Minum');
        await pumpScreen(tester, const TransactionFormScreen());

        // Akun pertama otomatis terpilih (quick add satu tap).
        await tester.enterText(
          find.byKey(const Key('transaction.form.amount')),
          '25000',
        );
        await tester.tap(
          find.byKey(Key('transaction.form.category.${makan.id}')),
        );
        await tester.enterText(
          find.byKey(const Key('transaction.form.note')),
          'Nasi goreng',
        );
        await tapSave(tester);

        final txs = await container
            .read(transactionRepositoryProvider)
            .getFiltered(const TransactionFilter());
        expect(txs, hasLength(1));
        expect(txs.single.type, TransactionType.expense);
        expect(txs.single.amount, 25000); // minor unit positif IDR
        expect(txs.single.accountId, account.id);
        expect(txs.single.categoryId, makan.id);
        expect(txs.single.description, 'Nasi goreng');
      },
    );

    testWidgets('income: hanya kategori pemasukan ditawarkan', (tester) async {
      await seedAccount();
      final makan = await categoryByName('Makan & Minum');
      final gaji = await categoryByName('Gaji');
      await pumpScreen(tester, const TransactionFormScreen());

      // Default expense: chip kategori expense tampil, income tidak.
      expect(
        find.byKey(Key('transaction.form.category.${makan.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('transaction.form.category.${gaji.id}')),
        findsNothing,
      );

      await tester.tap(find.text('Pemasukan'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('transaction.form.category.${gaji.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('transaction.form.category.${makan.id}')),
        findsNothing,
      );
    });

    testWidgets('amount USD 25,50 → tersimpan 2550 minor unit', (
      tester,
    ) async {
      await seedAccount(name: 'Wallet USD', currency: 'USD');
      final gaji = await categoryByName('Gaji');
      await pumpScreen(tester, const TransactionFormScreen());
      await tester.tap(find.text('Pemasukan'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('transaction.form.amount')),
        '2550',
      );
      await tester.tap(find.byKey(Key('transaction.form.category.${gaji.id}')));
      await tapSave(tester);

      final txs = await db.transactionDao.getByAccount(1);
      expect(txs.single.amount, 2550);
    });
  });

  group('validasi', () {
    testWidgets('amount kosong ditolak, tidak ada transaksi', (tester) async {
      await seedAccount();
      final makan = await categoryByName('Makan & Minum');
      await pumpScreen(tester, const TransactionFormScreen());
      await tester.tap(find.byKey(Key('transaction.form.category.${makan.id}')));
      await tapSave(tester);

      expect(find.text('Nominal wajib diisi'), findsWidgets);
      expect(find.byType(TransactionFormScreen), findsOneWidget);
      expect(
        await container
            .read(transactionRepositoryProvider)
            .getFiltered(const TransactionFilter()),
        isEmpty,
      );
    });

    testWidgets('kategori kosong ditolak (kategori wajib)', (tester) async {
      await seedAccount();
      await pumpScreen(tester, const TransactionFormScreen());
      await tester.enterText(
        find.byKey(const Key('transaction.form.amount')),
        '5000',
      );
      await tapSave(tester);

      expect(find.text('Kategori wajib dipilih'), findsOneWidget);
      expect(
        await container
            .read(transactionRepositoryProvider)
            .getFiltered(const TransactionFilter()),
        isEmpty,
      );
    });

    testWidgets('submit ganda tidak membuat duplikasi', (tester) async {
      await seedAccount();
      final makan = await categoryByName('Makan & Minum');
      await pumpScreen(tester, const TransactionFormScreen());
      await tester.enterText(
        find.byKey(const Key('transaction.form.amount')),
        '7500',
      );
      await tester.tap(find.byKey(Key('transaction.form.category.${makan.id}')));
      final save = find.byKey(const Key('transaction.form.save'));
      await scrollTo(tester, save);
      await tester.tap(save);
      await tester.pump(); // mulai saving, tombol disabled
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      // Flush timer 0-delay dispose drift (lihat komentar tapSave) — form
      // pop setelah submit sukses; tanpa flush, invariant pending timer
      // gagal dan tearDown db.close() deadlock.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(
        await container
            .read(transactionRepositoryProvider)
            .getFiltered(const TransactionFilter()),
        hasLength(1),
      );
    });
  });

  group('edit', () {
    testWidgets(
      'edit amount + kategori + tanggal + note; saldo mengikuti nilai baru',
      (tester) async {
        final account = await seedAccount();
        final tx = await seedTx(account, amount: 10000);
        final belanja = await categoryByName('Belanja');
        await pumpScreen(tester, TransactionFormScreen(existing: tx));

        // Prefill: note lama kosong, amount lama tampil.
        expect(find.textContaining('10.000'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('transaction.form.amount')),
          '25000',
        );
        await tester.tap(
          find.byKey(Key('transaction.form.category.${belanja.id}')),
        );
        await tester.enterText(
          find.byKey(const Key('transaction.form.note')),
          'Belanja bulanan',
        );
        // Tanggal: buka picker, pilih tanggal 17, OK.
        await scrollTo(tester, find.byKey(const Key('transaction.form.date')));
        await tester.tap(find.byKey(const Key('transaction.form.date')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('17'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await tapSave(tester);

        final updated = (await container
            .read(transactionRepositoryProvider)
            .getById(tx.id))!;
        expect(updated.amount, 25000);
        expect(updated.categoryId, belanja.id);
        expect(updated.description, 'Belanja bulanan');
        expect(updated.date, DateTime(2026, 1, 17));
        expect(updated.updatedAt.isAfter(tx.updatedAt), isTrue);

        // Saldo ledger mengikuti nilai baru: 0 - 25000 (expense).
        final balance = await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(account.id);
        expect(balance, -25000);

        // Daftar transaksi tetap satu baris (bukan tambah baru).
        expect(
          await container
              .read(transactionRepositoryProvider)
              .getFiltered(const TransactionFilter()),
          hasLength(1),
        );
      },
    );

    testWidgets('ganti type expense → income tersimpan', (tester) async {
      final account = await seedAccount();
      final tx = await seedTx(account);
      final gaji = await categoryByName('Gaji');
      await pumpScreen(tester, TransactionFormScreen(existing: tx));

      await tester.tap(find.text('Pemasukan'));
      await tester.pumpAndSettle();
      // Kategori lama (expense) direset saat ganti type → wajib pilih ulang.
      await tester.tap(find.byKey(Key('transaction.form.category.${gaji.id}')));
      await tapSave(tester);

      final updated = (await container
          .read(transactionRepositoryProvider)
          .getById(tx.id))!;
      expect(updated.type, TransactionType.income);
      expect(updated.categoryId, gaji.id);
      final balance = await container
          .read(transactionRepositoryProvider)
          .balanceForAccount(account.id);
      expect(balance, 10000); // income menambah saldo
    });

    testWidgets(
      'kegagalan edit: error tampil, form tetap terbuka, data lama utuh '
      '(tidak ada perubahan parsial)',
      (tester) async {
        final account = await seedAccount();
        final tx = await seedTx(account, amount: 10000, description: 'lama');

        // Override use case edit dengan yang selalu gagal — mensimulasikan
        // kegagalan di tengah mutasi atomik (rollback penuh oleh DB).
        final failing = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            editTransactionProvider.overrideWithValue(_FailingEdit(db)),
          ],
        );
        addTearDown(failing.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: failing,
            child: MaterialApp(home: TransactionFormScreen(existing: tx)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('transaction.form.amount')),
          '99000',
        );
        await tester.enterText(
          find.byKey(const Key('transaction.form.note')),
          'harusnya gagal',
        );
        await scrollTo(
          tester,
          find.byKey(const Key('transaction.form.save')),
        );
        await tester.tap(find.byKey(const Key('transaction.form.save')));
        await tester.pumpAndSettle();

        // Error state tampil + form masih terbuka + tombol aktif lagi.
        expect(
          find.byKey(const Key('transaction.form.error')),
          findsOneWidget,
        );
        expect(find.byType(TransactionFormScreen), findsOneWidget);

        // Data lama utuh — tidak ada perubahan parsial.
        final after = (await container
            .read(transactionRepositoryProvider)
            .getById(tx.id))!;
        expect(after.amount, 10000);
        expect(after.description, 'lama');
        final balance = await container
            .read(transactionRepositoryProvider)
            .balanceForAccount(account.id);
        expect(balance, -10000);
      },
    );
  });
}

/// EditTransactionUseCase yang selalu gagal — untuk test error rollback.
class _FailingEdit extends EditTransactionUseCase {
  _FailingEdit(super.db);

  @override
  Future<Transaction> call(Transaction updated) async {
    throw StateError('simulasi gagal di tengah mutasi');
  }
}
