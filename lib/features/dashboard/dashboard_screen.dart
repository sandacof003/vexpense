import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/settings_providers.dart';
import '../accounts/accounts_screen.dart';
import '../categories/categories_screen.dart';

/// Area utama aplikasi (placeholder FE-01).
///
/// FE-03 akan mengisi saldo/summary/transaksi dari repository (BE-01).
/// Sampai saat itu layar ini TIDAK menampilkan data dummy — hanya status
/// yang benar-benar tersimpan (currency default dari settings storage).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(defaultCurrencyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('V Expense')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.savings_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'Currency default: ${currency.code}',
              key: const Key('dashboard.currency'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Data transaksi menyusul (BE-01 repository).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Navigasi kelola akun & kategori (FE-06) — wireframe screen 8.
            TextButton.icon(
              key: const Key('dashboard.goto.accounts'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Kelola Akun'),
              onPressed: () => context.push(AccountsScreen.path),
            ),
            TextButton.icon(
              key: const Key('dashboard.goto.categories'),
              icon: const Icon(Icons.category_outlined),
              label: const Text('Kelola Kategori'),
              onPressed: () => context.push(CategoriesScreen.path),
            ),
          ],
        ),
      ),
    );
  }
}
