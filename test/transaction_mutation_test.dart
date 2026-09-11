import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/data/enums.dart';
import 'package:v_expense/core/data/daos/transaction_dao.dart';
import 'package:v_expense/features/transactions/domain/transaction_use_cases.dart';
import 'package:v_expense/features/transfers/transfer_use_cases.dart';

/// Test mutasi transaksi atomik + transfer same-currency (BE-03).
///
/// Setup pakai DAO langsung (schema milik BE-01) supaya test ini fokus ke
/// use case yang jadi scope BE-03. Saldo dihitung dari ledger lewat
/// `TransactionRepository` (scope BE-02) — direferensikan hanya sebagai
/// *oracle* untuk memverifikasi "saldo akhir == ledger".
AppDatabase _open() => AppDatabase.forTesting(NativeDatabase.memory());

/// Saldo akun dari ledger (opening + income - expense - transfer_out + transfer_in).
Future<int> _ledger(AppDatabase db, int accountId) async {
  final acc = (await db.accountDao.getById(accountId))!;
  var balance = acc.openingBalance;
  final outgoing = await db.transactionDao.getByAccount(accountId);
  final incoming = await db.transactionDao.getIncomingTransfers(accountId);
  for (final t in outgoing) {
    switch (t.type) {
      case TransactionType.income:
        balance += t.amount;
      case TransactionType.expense:
        balance -= t.amount;
      case TransactionType.transfer:
        balance -= t.amount;
    }
  }
  for (final t in incoming) {
    balance += t.amount;
  }
  return balance;
}

void main() {
  late AppDatabase db;
  late CreateTransactionUseCase createTx;
  late EditTransactionUseCase editTx;
  late DeleteTransactionUseCase deleteTx;
  late CreateTransferUseCase createTransfer;
  late DeleteTransferUseCase deleteTransfer;

  late Account acc;
  late Account acc2;
  late Category incomeCat;
  late Category expenseCat;

  setUp(() async {
    db = _open();
    createTx = CreateTransactionUseCase(db);
    editTx = EditTransactionUseCase(db);
    deleteTx = DeleteTransactionUseCase(db);
    createTransfer = CreateTransferUseCase(db);
    deleteTransfer = DeleteTransferUseCase(db);

    acc = await db.accountDao
        .insert(
          AccountsCompanion.insert(
            name: 'Dompet',
            type: AccountType.cash,
            currency: 'IDR',
            openingBalance: Value(100000),
          ),
        )
        .then((id) => db.accountDao.getById(id))
        .then((a) => a!);
    acc2 = await db.accountDao
        .insert(
          AccountsCompanion.insert(
            name: 'Bank',
            type: AccountType.bank,
            currency: 'IDR',
            openingBalance: Value(0),
          ),
        )
        .then((id) => db.accountDao.getById(id))
        .then((a) => a!);
    incomeCat = await db.categoryDao
        .insert(
          CategoriesCompanion.insert(
            name: 'Gaji Test',
            type: CategoryType.income,
          ),
        )
        .then((id) => db.categoryDao.getById(id))
        .then((c) => c!);
    expenseCat = await db.categoryDao
        .insert(
          CategoriesCompanion.insert(name: 'Makan', type: CategoryType.expense),
        )
        .then((id) => db.categoryDao.getById(id))
        .then((c) => c!);
  });

  tearDown(() async {
    await db.close();
  });

  group('create transaksi biasa', () {
    test(
      'income & expense punya kategori, saldo tercermin di ledger',
      () async {
        final inc = await createTx(
          type: TransactionType.income,
          amount: 200000,
          accountId: acc.id,
          categoryId: incomeCat.id,
          date: DateTime(2026, 1, 1),
        );
        expect(inc.type, TransactionType.income);
        expect(inc.categoryId, incomeCat.id);
        expect(await _ledger(db, acc.id), 300000); // 100000 + 200000

        final exp = await createTx(
          type: TransactionType.expense,
          amount: 50000,
          accountId: acc.id,
          categoryId: expenseCat.id,
          date: DateTime(2026, 1, 2),
        );
        expect(exp.categoryId, expenseCat.id);
        expect(await _ledger(db, acc.id), 250000);
      },
    );

    test('amount <= 0 ditolak, tidak ada partial write', () async {
      await expectLater(
        createTx(
          type: TransactionType.expense,
          amount: 0,
          accountId: acc.id,
          categoryId: expenseCat.id,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(await db.transactionDao.count(), 0);
    });

    test('transfer via createTx ditolak', () async {
      await expectLater(
        createTx(
          type: TransactionType.transfer,
          amount: 100,
          accountId: acc.id,
          categoryId: expenseCat.id,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('edit transaksi', () {
    test('edit amount menghasilkan saldo akhir sama dengan ledger', () async {
      final tx = await createTx(
        type: TransactionType.expense,
        amount: 10000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await editTx(tx.copyWith(amount: 25000));
      expect(await _ledger(db, acc.id), 75000); // 100000 - 25000
      expect((await db.transactionDao.getById(tx.id))!.amount, 25000);
    });

    test('edit kategori (expense -> income) mengubah arah ledger', () async {
      final tx = await createTx(
        type: TransactionType.expense,
        amount: 30000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await editTx(
        tx.copyWith(
          type: TransactionType.income,
          categoryId: Value(incomeCat.id),
        ),
      );
      expect(await _ledger(db, acc.id), 130000); // 100000 + 30000
    });

    test('edit tanggal & account memindahkan efek ke akun tujuan', () async {
      final tx = await createTx(
        type: TransactionType.expense,
        amount: 40000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await editTx(tx.copyWith(accountId: acc2.id, date: DateTime(2026, 2, 1)));
      // efek lama (dari acc) hilang, efek baru (ke acc2) berlaku.
      expect(await _ledger(db, acc.id), 100000);
      expect(await _ledger(db, acc2.id), -40000);
      final updated = (await db.transactionDao.getById(tx.id))!;
      expect(updated.accountId, acc2.id);
      expect(updated.date, DateTime(2026, 2, 1));
    });

    test(
      'edit ke kategori NULL ditolak (income/expense wajib kategori)',
      () async {
        final tx = await createTx(
          type: TransactionType.expense,
          amount: 1000,
          accountId: acc.id,
          categoryId: expenseCat.id,
          date: DateTime(2026, 1, 1),
        );
        await expectLater(
          editTx(tx.copyWith(categoryId: const Value(null))),
          throwsArgumentError,
        );
      },
    );

    test('edit id tidak ada -> StateError, tidak ada perubahan', () async {
      await expectLater(
        editTx(
          Transaction(
            id: 99999,
            type: TransactionType.expense,
            amount: 100,
            accountId: acc.id,
            categoryId: expenseCat.id,
            date: DateTime(2026, 1, 1),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('delete transaksi biasa', () {
    test('delete mengembalikan saldo sebelum transaksi', () async {
      final tx = await createTx(
        type: TransactionType.expense,
        amount: 60000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      expect(await _ledger(db, acc.id), 40000);
      await deleteTx(tx.id);
      expect(await db.transactionDao.getById(tx.id), isNull);
      expect(await _ledger(db, acc.id), 100000); // kembali ke opening
    });

    test('delete id tidak ada = no-op (idempotent)', () async {
      await deleteTx(99999);
      expect(await db.transactionDao.count(), 0);
    });

    test('delete transfer via deleteTx ditolak', () async {
      final tr = await createTransfer(
        fromAccountId: acc.id,
        toAccountId: acc2.id,
        amount: 100,
        date: DateTime(2026, 1, 1),
      );
      await expectLater(deleteTx(tr.id), throwsArgumentError);
      expect(await db.transactionDao.getById(tr.id), isNotNull);
    });
  });

  group('transfer', () {
    test(
      'create transfer satu baris, category_id NULL, ledger dua arah',
      () async {
        final tr = await createTransfer(
          fromAccountId: acc.id,
          toAccountId: acc2.id,
          amount: 40000,
          date: DateTime(2026, 1, 1),
        );
        expect(tr.type, TransactionType.transfer);
        expect(tr.toAccountId, acc2.id);
        expect(tr.categoryId, isNull);
        expect(await db.transactionDao.count(), 1);
        expect(await _ledger(db, acc.id), 60000);
        expect(await _ledger(db, acc2.id), 40000);
      },
    );

    test('akun sama ditolak', () async {
      await expectLater(
        createTransfer(
          fromAccountId: acc.id,
          toAccountId: acc.id,
          amount: 100,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(await db.transactionDao.count(), 0);
    });

    test('currency berbeda ditolak di MVP', () async {
      final usd = await db.accountDao
          .insert(
            AccountsCompanion.insert(
              name: 'USD acc',
              type: AccountType.bank,
              currency: 'USD',
              openingBalance: Value(0),
            ),
          )
          .then((id) => db.accountDao.getById(id))
          .then((a) => a!);
      await expectLater(
        createTransfer(
          fromAccountId: acc.id,
          toAccountId: usd.id,
          amount: 100,
          date: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(await db.transactionDao.count(), 0);
    });

    test('delete transfer menghapus kedua sisi tanpa orphan', () async {
      final tr = await createTransfer(
        fromAccountId: acc.id,
        toAccountId: acc2.id,
        amount: 40000,
        date: DateTime(2026, 1, 1),
      );
      await deleteTransfer(tr.id);
      expect(await db.transactionDao.getById(tr.id), isNull);
      expect(await db.transactionDao.count(), 0);
      // tidak ada baris transfer tersisa (tidak ada orphan dua sisi).
      expect(
        await db.transactionDao.getFiltered(
          const TransactionFilter(type: TransactionType.transfer),
        ),
        isEmpty,
      );
      // ledger kembali ke kondisi awal kedua akun.
      expect(await _ledger(db, acc.id), 100000);
      expect(await _ledger(db, acc2.id), 0);
    });

    test('delete non-transfer via deleteTransfer ditolak', () async {
      final tx = await createTx(
        type: TransactionType.expense,
        amount: 100,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await expectLater(deleteTransfer(tx.id), throwsArgumentError);
      expect(await db.transactionDao.getById(tx.id), isNotNull);
    });
  });

  group('rollback pada kegagalan database', () {
    test('edit ke akun tidak ada (FK violation) rollback penuh', () async {
      final tx = await createTx(
        type: TransactionType.expense,
        amount: 5000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      // accountId 99999 tidak ada -> REFERENCES RESTRICT memicu error di replace.
      await expectLater(
        editTx(tx.copyWith(accountId: 99999)),
        throwsA(anything),
      );
      // baris tetap utuh (rollback), ledger tidak berubah.
      final intact = (await db.transactionDao.getById(tx.id))!;
      expect(intact.accountId, acc.id);
      expect(intact.amount, 5000);
      expect(await _ledger(db, acc.id), 95000);
    });

    test('edit ke kategori tidak ada (FK violation) rollback penuh', () async {
      final tx = await createTx(
        type: TransactionType.expense,
        amount: 7000,
        accountId: acc.id,
        categoryId: expenseCat.id,
        date: DateTime(2026, 1, 1),
      );
      await expectLater(
        editTx(tx.copyWith(categoryId: Value(99999))),
        throwsA(anything),
      );
      final intact = (await db.transactionDao.getById(tx.id))!;
      expect(intact.categoryId, expenseCat.id);
      expect(intact.amount, 7000);
      expect(await _ledger(db, acc.id), 93000);
    });
  });
}
