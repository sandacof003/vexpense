import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/data/enums.dart';
import '../../../core/di/providers.dart';
import '../../transfers/transfer_use_cases.dart';
import '../domain/transaction_use_cases.dart';

/// Kategori sesuai tipe transaksi untuk form (FE-04).
///
/// Acceptance: "form hanya menawarkan kategori sesuai type" — filter di sini
/// supaya UI tinggal render. Kosong selama stream masih loading.
final categoriesByTypeProvider = Provider.autoDispose
    .family<List<Category>, TransactionType>((ref, type) {
      final categoryType =
          type == TransactionType.income
              ? CategoryType.income
              : CategoryType.expense;
      final categories =
          ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
      return categories.where((c) => c.type == categoryType).toList();
    });

/// Alur mutasi atomik BE-02: create/edit income-expense dalam SATU DB
/// transaction (edit = reversal efek lama + apply nilai baru sekaligus,
/// gagal → rollback penuh, tidak ada perubahan parsial).
final createTransactionProvider = Provider<CreateTransactionUseCase>(
  (ref) => CreateTransactionUseCase(ref.watch(appDatabaseProvider)),
);

final editTransactionProvider = Provider<EditTransactionUseCase>(
  (ref) => EditTransactionUseCase(ref.watch(appDatabaseProvider)),
);

/// Hapus transaksi biasa (BE-02) — transfer ditolak use case, wajib lewat
/// [deleteTransferProvider].
final deleteTransactionProvider = Provider<DeleteTransactionUseCase>(
  (ref) => DeleteTransactionUseCase(ref.watch(appDatabaseProvider)),
);

/// Transfer same-currency dua sisi (BE-03): create/hapus atomik.
final createTransferProvider = Provider<CreateTransferUseCase>(
  (ref) => CreateTransferUseCase(ref.watch(appDatabaseProvider)),
);

final deleteTransferProvider = Provider<DeleteTransferUseCase>(
  (ref) => DeleteTransferUseCase(ref.watch(appDatabaseProvider)),
);
