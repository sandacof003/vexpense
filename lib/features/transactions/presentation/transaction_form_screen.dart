import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/data/enums.dart';
import '../../../core/di/providers.dart';
import '../../../core/formatters/currency_format.dart';
import '../../../core/formatters/date_formatter.dart';
import '../../../core/formatters/money_formatter.dart';
import '../../../core/validators/transaction_form_validators.dart';
import '../../../core/widgets/amount_field.dart';
import '../../categories/category_appearance.dart';
import '../providers/transaction_providers.dart';

/// Form tambah/edit transaksi income/expense (FE-04, wireframe screen 3).
///
/// Acceptance FE-04:
/// - Amount tersimpan sebagai minor unit POSITIF currency akun.
/// - Kategori wajib; hanya kategori sesuai type yang ditawarkan.
/// - Hanya akun yang tersedia yang ditawarkan.
/// - Edit dapat mengubah semua field (type, amount, akun, kategori, tanggal,
///   note) dan memakai alur mutasi atomik BE-02 ([EditTransactionUseCase]):
///   reversal efek lama + apply nilai baru dalam satu DB transaction, gagal
///   → rollback penuh (tidak ada perubahan parsial; saldo & laporan mengikuti
///   nilai baru karena ledger dihitung dari data final).
/// - Submit ganda tidak membuat duplikasi (tombol disabled selama saving).
///
/// Transfer TIDAK ditangani di sini (ranah FE-05); segmented type hanya
/// income/expense.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.existing});

  /// `null` = mode tambah; terisi = mode edit.
  final Transaction? existing;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _validators = const TransactionFormValidators();
  final _dateFormatter = const DateFormatter();

  late TransactionType _type;
  int? _accountId;
  int? _categoryId;
  late DateTime _date;
  bool _saving = false;
  String? _amountError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    _type = tx?.type ?? TransactionType.expense;
    _accountId = tx?.accountId;
    _categoryId = tx?.categoryId;
    _date = tx?.date ?? DateTime.now();
    _noteController.text = tx?.description ?? '';
    if (tx != null) {
      _amountController.text = MoneyFormatter().formatMinor(
        tx.amount,
        CurrencyFormat.fromCode(_currencyCodeFor(tx.accountId)),
      );
    }
  }

  /// Currency akun terpilih (source of truth minor unit amount).
  String _currencyCodeFor(int? accountId) {
    if (accountId == null) return 'IDR';
    final accounts = ref.read(accountsProvider).valueOrNull ?? const [];
    for (final a in accounts) {
      if (a.id == accountId) return a.currency;
    }
    return 'IDR';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return; // guard submit ganda (tombol juga disabled)
    final currency = CurrencyFormat.fromCode(_currencyCodeFor(_accountId));
    final amount = _validators.validateAmount(
      _amountController.text,
      currency,
    );
    final categoryError = _validators.validateCategoryRequired(_categoryId);

    setState(() {
      _amountError = amount.error;
    });

    String? firstError = amount.error ?? categoryError;
    if (_accountId == null) firstError ??= 'Akun wajib dipilih';
    if (firstError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(firstError)));
      return;
    }

    setState(() => _saving = true);
    final note = _noteController.text.trim();
    try {
      if (_isEdit) {
        // Alur mutasi atomik repository/use case BE-02: satu DB transaction,
        // error apa pun → rollback penuh, baris lama tetap utuh.
        await ref
            .read(editTransactionProvider)
            .call(
              widget.existing!.copyWith(
                type: _type,
                amount: amount.minorUnit,
                accountId: _accountId,
                categoryId: Value(_categoryId),
                description: Value(note.isEmpty ? null : note),
                date: _date,
              ),
            );
      } else {
        await ref
            .read(createTransactionProvider)
            .call(
              type: _type,
              amount: amount.minorUnit!,
              accountId: _accountId!,
              categoryId: _categoryId!,
              date: _date,
              description: note.isEmpty ? null : note,
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Error state: alasan tampil, form tetap terbuka, tidak ada partial
      // write (rollback dijamin use case).
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('transaction.form.error'),
            content: Text('Gagal menyimpan: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountsAsync = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesByTypeProvider(_type));

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Transaksi' : 'Transaksi Baru')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Pengeluaran'),
                  icon: Icon(Icons.arrow_downward),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Pemasukan'),
                  icon: Icon(Icons.arrow_upward),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selected) => setState(() {
                final newType = selected.first;
                // Kategori lama belum tentu valid untuk tipe baru — cek
                // terhadap daftar tipe baru, reset bila tidak ada.
                if (!ref
                    .read(categoriesByTypeProvider(newType))
                    .any((c) => c.id == _categoryId)) {
                  _categoryId = null;
                }
                _type = newType;
              }),
            ),
            const SizedBox(height: 16),
            // --- Akun: hanya yang tersedia ---
            accountsAsync.when(
              data: (accounts) {
                // Mode tambah: preselect akun pertama (quick add satu tap).
                if (!_isEdit && _accountId == null && accounts.isNotEmpty) {
                  _accountId = accounts.first.id;
                }
                if (accounts.isEmpty) {
                  return Text(
                    'Belum ada akun — buat dulu lewat Kelola Akun.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  );
                }
                return DropdownButtonFormField<int>(
                  key: const Key('transaction.form.account'),
                  value: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Akun'),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.name} · ${a.currency}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _accountId = value),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Text('Gagal memuat akun: $e'),
            ),
            const SizedBox(height: 16),
            // --- Nominal (minor unit currency akun) ---
            AmountField(
              key: const Key('transaction.form.amount'),
              controller: _amountController,
              currency: CurrencyFormat.fromCode(_currencyCodeFor(_accountId)),
              errorText: _amountError,
              helperText: _accountId == null
                  ? null
                  : 'Disimpan minor unit ${_currencyCodeFor(_accountId)}.',
            ),
            const SizedBox(height: 16),
            // --- Kategori sesuai type (wajib) ---
            Text('Kategori', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (categories.isEmpty)
              Text(
                'Belum ada kategori ${_type == TransactionType.income ? 'pemasukan' : 'pengeluaran'}.',
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      key: Key('transaction.form.category.${c.id}'),
                      avatar: Icon(categoryIcon(c.icon), size: 16),
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() => _categoryId = c.id),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            // --- Tanggal (bisa diedit) ---
            ListTile(
              key: const Key('transaction.form.date'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Tanggal'),
              subtitle: Text(_dateFormatter.format(_date, style: DateStyle.full)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            // --- Note (bisa diedit) ---
            TextField(
              key: const Key('transaction.form.note'),
              controller: _noteController,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('transaction.form.save'),
              onPressed: _saving || accountsAsync.valueOrNull?.isEmpty == true
                  ? null
                  : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Simpan Perubahan' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
