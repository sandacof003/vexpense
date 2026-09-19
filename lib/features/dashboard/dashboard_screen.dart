import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/database.dart';
import '../../core/data/enums.dart';
import '../../core/di/providers.dart';
import '../../core/formatters/currency_format.dart';
import '../../core/formatters/date_formatter.dart';
import '../../core/formatters/money_formatter.dart';
import '../../core/settings/settings_providers.dart';
import '../accounts/accounts_screen.dart';
import '../categories/categories_screen.dart';
import '../reports/presentation/reports_screen.dart';
import '../transactions/presentation/transaction_form_screen.dart';
import '../transactions/presentation/transaction_list_screen.dart';

/// Dashboard FE-03: total balance (IDR), ringkasan bulan berjalan, dan
/// transaksi terbaru. Semua saldo dihitung dari ledger (BE-02/BE-05) —
/// tidak ada kolom balance yang dibaca dari DB.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const _recentLimit = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(defaultCurrencyProvider);
    final balance = ref.watch(dashboardBalanceProvider);
    final monthly = ref.watch(dashboardMonthlyProvider);
    final transactions = ref.watch(transactionsProvider);
    final theme = Theme.of(context);
    final money = MoneyFormatter();
    final idr = CurrencyFormat.fromCode('IDR');

    return Scaffold(
      appBar: AppBar(title: const Text('V Expense')),
      // Quick add transaksi (PRD dashboard: quick add button).
      floatingActionButton: FloatingActionButton(
        key: const Key('dashboard.quick.add'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TransactionFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Currency default: ${currency.code}',
            key: const Key('dashboard.currency'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // --- Total balance gabungan (konversi ke IDR) ---
          balance.when(
            loading: () => const Center(
              key: Key('dashboard.loading'),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => _ErrorState(
              key: const Key('dashboard.error'),
              message: 'Gagal memuat saldo: $e',
              onRetry: () => ref.invalidate(dashboardBalanceProvider),
            ),
            data: (summary) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Saldo (IDR)', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(
                      money.format(summary.totalMinorUnit, idr),
                      key: const Key('dashboard.total'),
                      style: theme.textTheme.headlineMedium,
                    ),
                    if (!summary.isComplete) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Data belum lengkap: rate '
                        '${summary.missingRateCurrencies.join(', ')} '
                        'ke IDR belum ada, saldo akun tersebut belum dihitung.',
                        key: const Key('dashboard.rate.missing'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- Income vs expense bulan berjalan ---
          monthly.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => _ErrorState(
              message: 'Gagal memuat ringkasan bulan ini: $e',
              onRetry: () => ref.invalidate(dashboardMonthlyProvider),
            ),
            data: (report) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bulan Ini', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Pemasukan'),
                        Text(
                          money.format(report.incomeMinorUnit, idr),
                          key: const Key('dashboard.monthly.income'),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Pengeluaran'),
                        Text(
                          money.format(report.expenseMinorUnit, idr),
                          key: const Key('dashboard.monthly.expense'),
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (!report.isComplete)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Sebagian transaksi belum terkonversi '
                          '(rate ${report.missingRateCurrencies.join(', ')} '
                          'belum ada).',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // --- Transaksi terbaru ---
          Text('Transaksi Terbaru', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          transactions.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _ErrorState(
              message: 'Gagal memuat transaksi: $e',
              onRetry: () => ref.invalidate(transactionsProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    key: const Key('dashboard.empty'),
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Belum ada transaksi.\n'
                        'Tambahkan akun lalu catat transaksi pertama lewat '
                        'tombol + di bawah.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (final tx in list.take(_recentLimit))
                    _RecentTransactionTile(tx: tx),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          // Navigasi kelola akun & kategori (FE-06) — wireframe screen 8.
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                key: const Key('dashboard.goto.transactions'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Semua Transaksi'),
                onPressed: () => context.push(TransactionListScreen.path),
              ),
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
              TextButton.icon(
                key: const Key('dashboard.goto.reports'),
                icon: const Icon(Icons.bar_chart_outlined),
                label: const Text('Reports'),
                onPressed: () => context.push(ReportsScreen.path),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Satu baris transaksi terbaru: tipe, nominal, akun, kategori, tanggal.
/// Tap → form edit transaksi (FE-04).
class _RecentTransactionTile extends ConsumerWidget {
  const _RecentTransactionTile({required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    String accountName(int? id) {
      for (final a in accounts) {
        if (a.id == id) return a.name;
      }
      return '?';
    }

    Account? accountById(int? id) {
      for (final a in accounts) {
        if (a.id == id) return a;
      }
      return null;
    }

    final account = accountById(tx.accountId);
    final currency = CurrencyFormat.fromCode(account?.currency);
    final money = MoneyFormatter();
    final amountText = money.format(tx.amount, currency);

    final (icon, label, color) = switch (tx.type) {
      TransactionType.income => (
        Icons.south_west,
        'Pemasukan',
        theme.colorScheme.primary,
      ),
      TransactionType.expense => (
        Icons.north_east,
        'Pengeluaran',
        theme.colorScheme.error,
      ),
      TransactionType.transfer => (
        Icons.swap_horiz,
        'Transfer',
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    final categoryName = tx.categoryId == null
        ? (tx.type == TransactionType.transfer
              ? '${accountName(tx.accountId)} → ${accountName(tx.toAccountId)}'
              : 'Tanpa kategori')
        : (categories.where((c) => c.id == tx.categoryId).firstOrNull?.name ??
              'Tanpa kategori');

    return ListTile(
      key: Key('dashboard.recent.${tx.id}'),
      leading: Icon(icon, color: color),
      title: Text(
        tx.description?.isNotEmpty == true ? tx.description! : categoryName,
      ),
      subtitle: Text(
        '$label · ${accountName(tx.accountId)} · $categoryName · '
        '${const DateFormatter().format(tx.date, style: DateStyle.short)}',
      ),
      trailing: Text(
        amountText,
        key: Key('dashboard.recent.${tx.id}.amount'),
        style: theme.textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TransactionFormScreen(existing: tx),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
