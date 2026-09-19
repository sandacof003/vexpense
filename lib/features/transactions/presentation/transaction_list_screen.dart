import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/daos/transaction_dao.dart' show TransactionFilter;
import '../../../core/data/database.dart';
import '../../../core/data/enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/formatters/currency_format.dart';
import '../../../core/formatters/date_formatter.dart';
import '../../../core/formatters/money_formatter.dart';
import '../../categories/category_appearance.dart';
import '../../transfers/transfer_form_screen.dart';
import '../providers/transaction_providers.dart';
import 'transaction_form_screen.dart';

/// Daftar semua transaksi + filter + search + detail + hapus (FE-05).
///
/// Data live dari [filteredTransactionsProvider] (stream `watchFiltered`,
/// terbaru dulu). Filter (tipe/akun/kategori/tanggal) dan search description
/// hidup berdampingan di satu [TransactionFilter] — keduanya hanya mengubah
/// query, tidak pernah menyentuh data. Detail tampil sebagai bottom sheet;
/// hapus selalu lewat dialog konfirmasi dan use case atomik BE-02/BE-03
/// (transfer → [DeleteTransferUseCase], biasa → [DeleteTransactionUseCase]).
class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  static const path = '/transactions';

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  final _searchController = TextEditingController();
  final _dateFormatter = const DateFormatter();

  @override
  void initState() {
    super.initState();
    // Pulihkan teks search bila filter sudah terisi (mis. kembali ke layar).
    _searchController.text =
        ref.read(transactionListFilterProvider).search ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilter(TransactionFilter Function(TransactionFilter f) update) {
    final current = ref.read(transactionListFilterProvider);
    ref.read(transactionListFilterProvider.notifier).state = update(current);
  }

  /// Konfirmasi dulu, baru hapus — tanpa konfirmasi tidak ada mutasi.
  Future<void> _confirmDelete(Transaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: Text(
          tx.type == TransactionType.transfer
              ? 'Transfer ini akan dihapus dari kedua akun (asal dan tujuan).'
              : 'Transaksi ini akan dihapus dan saldo kembali seperti semula.',
        ),
        actions: [
          TextButton(
            key: const Key('tx.delete.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('tx.delete.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (tx.type == TransactionType.transfer) {
        await ref.read(deleteTransferProvider).call(tx.id);
      } else {
        await ref.read(deleteTransactionProvider).call(tx.id);
      }
      // Stream repository emit otomatis → daftar & saldo refresh sendiri.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('tx.delete.error'),
            content: Text('Gagal menghapus: $e'),
          ),
        );
      }
    }
  }

  void _openDetail(Transaction tx) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _TransactionDetailSheet(
        tx: tx,
        onEdit: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TransactionFormScreen(existing: tx)),
          );
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          _confirmDelete(tx);
        },
      ),
    );
  }

  void _openAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('tx.fab.income-expense'),
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Transaksi Baru'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TransactionFormScreen(),
                  ),
                );
              },
            ),
            ListTile(
              key: const Key('tx.fab.transfer'),
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer Baru'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TransferFormScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionListFilterProvider);
    final txsAsync = ref.watch(filteredTransactionsProvider);
    final hasActiveFilter =
        filter.type != null ||
        filter.accountId != null ||
        filter.categoryId != null ||
        filter.fromDate != null ||
        filter.toDate != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        actions: [
          IconButton(
            key: const Key('tx.filter.open'),
            icon: Badge(
              isLabelVisible: hasActiveFilter,
              child: const Icon(Icons.tune),
            ),
            tooltip: 'Filter',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => const _FilterSheet(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('tx.fab'),
        onPressed: _openAddSheet,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('tx.search'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari catatan…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filter.search?.isNotEmpty == true
                    ? IconButton(
                        key: const Key('tx.search.clear'),
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _updateFilter((f) => _copySearch(f, null));
                        },
                      )
                    : null,
              ),
              onChanged: (value) => _updateFilter(
                (f) => _copySearch(f, value.trim().isEmpty ? null : value),
              ),
            ),
          ),
          Expanded(
            child: txsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  key: Key('tx.loading'),
                ),
              ),
              error: (e, _) => _ErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(filteredTransactionsProvider),
              ),
              data: (list) => list.isEmpty
                  ? Center(
                      key: const Key('tx.empty'),
                      child: Text(
                        hasActiveFilter || filter.search?.isNotEmpty == true
                            ? 'Tidak ada transaksi yang cocok dengan filter.'
                            : 'Belum ada transaksi.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) => _TransactionTile(
                        tx: list[index],
                        formatter: MoneyFormatter(),
                        dateFormatter: _dateFormatter,
                        onTap: () => _openDetail(list[index]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static TransactionFilter _copySearch(TransactionFilter f, String? search) =>
      TransactionFilter(
        type: f.type,
        accountId: f.accountId,
        categoryId: f.categoryId,
        fromDate: f.fromDate,
        toDate: f.toDate,
        search: search,
      );
}

/// Satu baris transaksi. Nominal panjang → ellipsis (tidak ada overflow).
class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.tx,
    required this.formatter,
    required this.dateFormatter,
    required this.onTap,
  });

  final Transaction tx;
  final MoneyFormatter formatter;
  final DateFormatter dateFormatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    String accountName(int? id) =>
        accounts.where((a) => a.id == id).firstOrNull?.name ?? '?';
    String currencyCode(int? id) =>
        accounts.where((a) => a.id == id).firstOrNull?.currency ?? 'IDR';

    final (icon, label, color) = switch (tx.type) {
      TransactionType.income => (
        Icons.arrow_downward,
        'Pemasukan',
        Colors.green,
      ),
      TransactionType.expense => (
        Icons.arrow_upward,
        'Pengeluaran',
        theme.colorScheme.error,
      ),
      TransactionType.transfer => (
        Icons.swap_horiz,
        'Transfer',
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    final categoryName =
        tx.type == TransactionType.transfer
            ? '${accountName(tx.accountId)} → ${accountName(tx.toAccountId)}'
            : (categories
                      .where((c) => c.id == tx.categoryId)
                      .firstOrNull
                      ?.name ??
                  'Tanpa kategori');

    final amountText = formatter.format(
      tx.amount,
      CurrencyFormat.fromCode(currencyCode(tx.accountId)),
    );

    return ListTile(
      key: Key('tx.item.${tx.id}'),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          tx.categoryId != null
              ? categoryIcon(
                  categories
                      .where((c) => c.id == tx.categoryId)
                      .firstOrNull
                      ?.icon,
                )
              : icon,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        tx.description?.isNotEmpty == true ? tx.description! : categoryName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$label · $categoryName · '
        '${dateFormatter.format(tx.date, style: DateStyle.short)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        amountText,
        key: Key('tx.item.${tx.id}.amount'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Detail transaksi (bottom sheet) + aksi edit & hapus.
///
/// Transfer: tampil akun asal → tujuan, amount tunggal, tanggal, TANPA
/// kategori (sesuai skema 1 baris). Edit transfer tidak didukung MVP
/// ([EditTransactionUseCase] menolak transfer) → tombol edit hanya untuk
/// income/expense.
class _TransactionDetailSheet extends ConsumerWidget {
  const _TransactionDetailSheet({
    required this.tx,
    required this.onEdit,
    required this.onDelete,
  });

  final Transaction tx;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = MoneyFormatter();
    final dateFormatter = const DateFormatter();
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    Account? accountOf(int? id) =>
        accounts.where((a) => a.id == id).firstOrNull;
    final fromAccount = accountOf(tx.accountId);
    final currency = CurrencyFormat.fromCode(fromAccount?.currency ?? 'IDR');
    final category = categories.where((c) => c.id == tx.categoryId).firstOrNull;
    final isTransfer = tx.type == TransactionType.transfer;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTransfer ? 'Detail Transfer' : 'Detail Transaksi',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text(
              money.format(tx.amount, currency),
              key: const Key('tx.detail.amount'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            if (isTransfer) ...[
              _DetailRow(
                icon: Icons.account_balance_outlined,
                label: 'Dari',
                value:
                    '${fromAccount?.name ?? '?'} · ${fromAccount?.currency ?? ''}',
                rowKey: const Key('tx.detail.from'),
              ),
              _DetailRow(
                icon: Icons.account_balance_outlined,
                label: 'Ke',
                value:
                    '${accountOf(tx.toAccountId)?.name ?? '?'} · '
                    '${accountOf(tx.toAccountId)?.currency ?? ''}',
                rowKey: const Key('tx.detail.to'),
              ),
            ] else ...[
              _DetailRow(
                icon: Icons.account_balance_outlined,
                label: 'Akun',
                value:
                    '${fromAccount?.name ?? '?'} · ${fromAccount?.currency ?? ''}',
              ),
              _DetailRow(
                icon: categoryIcon(category?.icon),
                label: 'Kategori',
                value: category?.name ?? 'Tanpa kategori',
              ),
            ],
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Tanggal',
              value: dateFormatter.format(tx.date, style: DateStyle.full),
            ),
            if (tx.description?.isNotEmpty == true)
              _DetailRow(
                icon: Icons.notes_outlined,
                label: 'Catatan',
                value: tx.description!,
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isTransfer)
                  TextButton.icon(
                    key: const Key('tx.detail.edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                    onPressed: onEdit,
                  ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  key: const Key('tx.detail.delete'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus'),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.rowKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        key: rowKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Sheet filter: tipe, akun, kategori, rentang tanggal. Setiap perubahan
/// langsung dipakai query (live) — tanpa tombol apply, data tidak tersentuh.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(transactionListFilterProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final dateFormatter = const DateFormatter();

    void update(TransactionFilter next) =>
        ref.read(transactionListFilterProvider.notifier).state = next;

    Future<void> pickDate({required bool isFrom}) async {
      final initial =
          (isFrom ? filter.fromDate : filter.toDate) ?? DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      update(
        isFrom
            ? TransactionFilter(
                type: filter.type,
                accountId: filter.accountId,
                categoryId: filter.categoryId,
                fromDate: picked,
                toDate: filter.toDate,
                search: filter.search,
              )
            : TransactionFilter(
                type: filter.type,
                accountId: filter.accountId,
                categoryId: filter.categoryId,
                fromDate: filter.fromDate,
                // Inklusif sampai akhir hari terpilih.
                toDate: DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  23,
                  59,
                  59,
                ),
                search: filter.search,
              ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  key: const Key('tx.filter.reset'),
                  onPressed: () => update(
                    TransactionFilter(search: filter.search),
                  ),
                  child: const Text('Reset'),
                ),
                IconButton(
                  key: const Key('tx.filter.close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<TransactionType?>(
              key: const Key('tx.filter.type'),
              segments: const [
                ButtonSegment(value: null, label: Text('Semua')),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Masuk'),
                ),
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Keluar'),
                ),
                ButtonSegment(
                  value: TransactionType.transfer,
                  label: Text('Transfer'),
                ),
              ],
              selected: {filter.type},
              onSelectionChanged: (selected) => update(
                TransactionFilter(
                  type: selected.first,
                  accountId: filter.accountId,
                  categoryId: filter.categoryId,
                  fromDate: filter.fromDate,
                  toDate: filter.toDate,
                  search: filter.search,
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: const Key('tx.filter.account'),
              value: filter.accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Akun'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Semua akun')),
                for (final a in accounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.name} · ${a.currency}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => update(
                TransactionFilter(
                  type: filter.type,
                  accountId: value,
                  categoryId: filter.categoryId,
                  fromDate: filter.fromDate,
                  toDate: filter.toDate,
                  search: filter.search,
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: const Key('tx.filter.category'),
              value: filter.categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Semua kategori'),
                ),
                for (final c in categories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => update(
                TransactionFilter(
                  type: filter.type,
                  accountId: filter.accountId,
                  categoryId: value,
                  fromDate: filter.fromDate,
                  toDate: filter.toDate,
                  search: filter.search,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('tx.filter.from'),
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      filter.fromDate == null
                          ? 'Dari tanggal'
                          : dateFormatter.format(
                              filter.fromDate!,
                              style: DateStyle.short,
                            ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => pickDate(isFrom: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('tx.filter.to'),
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      filter.toDate == null
                          ? 'Sampai'
                          : dateFormatter.format(
                              filter.toDate!,
                              style: DateStyle.short,
                            ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 8),
          Text('Gagal memuat transaksi: $message', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
