import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_providers.dart';

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
          ],
        ),
      ),
    );
  }
}
