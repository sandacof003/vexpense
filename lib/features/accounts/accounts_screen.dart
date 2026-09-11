import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/enums.dart';
import '../../core/di/providers.dart';
import '../../core/formatters/currency_format.dart';
import '../../core/formatters/money_formatter.dart';
import 'account_form_screen.dart';

/// List akun (cash / bank / e-wallet) + saldo awal minor unit.
///
/// Data live dari [accountsProvider] (stream repository). Saldo berjalan
/// per transaksi tampil nanti di FE-03 dashboard; di sini cukup opening
/// balance yang tersimpan di akun (acceptance FE-06).
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  static const path = '/accounts';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final money = MoneyFormatter();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      floatingActionButton: FloatingActionButton(
        key: const Key('accounts.add'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AccountFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: accounts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat akun: $e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Belum ada akun'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final account = list[index];
                        final currency = CurrencyFormat.fromCode(
                          account.currency,
                        );
                        return ListTile(
                          key: Key('accounts.item.${account.id}'),
                          leading: Icon(_accountIcon(account.type)),
                          title: Text(account.name),
                          subtitle: Text(
                            '${account.type.name} · ${account.currency}',
                          ),
                          trailing: Text(
                            money.format(account.openingBalance, currency),
                            style: theme.textTheme.bodyMedium,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AccountFormScreen(
                                account: account,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'ℹ️ Akun dengan transaksi tidak bisa dihapus — '
              'pindahkan transaksinya dulu.',
              key: const Key('accounts.restrict.hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _accountIcon(AccountType type) => switch (type) {
    AccountType.cash => Icons.payments_outlined,
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.ewallet => Icons.account_balance_wallet_outlined,
  };
}
