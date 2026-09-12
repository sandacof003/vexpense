import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/data/enums.dart';
import '../../../core/di/providers.dart';
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
