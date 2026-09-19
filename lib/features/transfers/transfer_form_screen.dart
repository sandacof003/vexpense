import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/di/providers.dart';
import '../../core/formatters/currency_format.dart';
import '../../core/formatters/date_formatter.dart';
import '../../core/validators/transaction_form_validators.dart';
import '../../core/widgets/amount_field.dart';
import '../transactions/providers/transaction_providers.dart';

/// Form transfer same-currency dua sisi (FE-05, wireframe screen 4).
///
/// Invariant (BE-03): transfer = SATU baris `transactions` — akun asal
/// (debit), akun tujuan (kredit), amount tunggal, tanggal, catatan, TANPA
/// kategori. Tujuan hanya menawarkan akun ber-currency sama dengan asal;
/// akun asal sendiri tidak ditawarkan sebagai tujuan. Submit lewat
/// [CreateTransferUseCase] (validasi ganda di use case: akun sama / beda
/// currency ditolak). Tidak ada mode edit (MVP: hapus + buat ulang).
class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key});

  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _validators = const TransactionFormValidators();
  final _dateFormatter = const DateFormatter();
  int? _fromAccountId;
  int? _toAccountId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _amountError;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Account? _accountById(int? id, List<Account> accounts) =>
      id == null ? null : accounts.where((a) => a.id == id).firstOrNull;

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
    if (_saving) return; // guard submit ganda
    final accounts = ref.read(accountsProvider).valueOrNull ?? const [];
    final fromAccount = _accountById(_fromAccountId, accounts);
    final currency = CurrencyFormat.fromCode(fromAccount?.currency ?? 'IDR');
    final amount = _validators.validateAmount(
      _amountController.text,
      currency,
    );
    final accountError = _validators.validateTransferAccounts(
      _fromAccountId,
      _toAccountId,
    );

    setState(() => _amountError = amount.error);
    final firstError = amount.error ?? accountError;
    if (firstError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(firstError)));
      return;
    }

    setState(() => _saving = true);
    final note = _noteController.text.trim();
    try {
      // Alur atomik BE-03: debit asal + kredit tujuan dalam SATU baris/DB
      // transaction; gagal → rollback penuh.
      await ref
          .read(createTransferProvider)
          .call(
            fromAccountId: _fromAccountId!,
            toAccountId: _toAccountId!,
            amount: amount.minorUnit!,
            date: _date,
            description: note.isEmpty ? null : note,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('transfer.form.error'),
            content: Text('Gagal menyimpan transfer: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final accounts = accountsAsync.valueOrNull ?? const <Account>[];
    final fromAccount = _accountById(_fromAccountId, accounts);
    final fromCurrency = fromAccount?.currency;

    // Tujuan: hanya akun currency sama, excluding akun asal (invariant
    // transfer same-currency dua sisi).
    final toOptions =
        fromCurrency == null
            ? const <Account>[]
            : accounts
                .where(
                  (a) => a.currency == fromCurrency && a.id != _fromAccountId,
                )
                .toList();
    if (_toAccountId != null &&
        !toOptions.any((a) => a.id == _toAccountId)) {
      _toAccountId = null;
    }

    final currency = CurrencyFormat.fromCode(fromCurrency ?? 'IDR');

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer Baru')),
      body: SafeArea(
        child: accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Gagal memuat akun: $e')),
          data: (list) {
            if (list.length < 2) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Transfer butuh minimal 2 akun dengan currency sama — '
                    'buat dulu lewat Kelola Akun.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<int>(
                  key: const Key('transfer.form.from'),
                  value: _fromAccountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Dari akun'),
                  items: [
                    for (final a in list)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.name} · ${a.currency}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _fromAccountId = value;
                    _toAccountId = null; // currency asal boleh berubah
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Icon(Icons.arrow_downward, size: 20),
                ),
                DropdownButtonFormField<int>(
                  key: const Key('transfer.form.to'),
                  value: _toAccountId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Ke akun',
                    helperText: fromCurrency == null
                        ? 'Pilih akun asal dulu'
                        : 'Hanya akun ber-currency $fromCurrency',
                  ),
                  items: [
                    if (toOptions.isEmpty)
                      const DropdownMenuItem<int>(
                        value: null,
                        enabled: false,
                        child: Text(
                          'Tidak ada akun se-currency',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final a in toOptions)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.name} · ${a.currency}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: toOptions.isEmpty
                      ? null
                      : (value) => setState(() => _toAccountId = value),
                ),
                const SizedBox(height: 16),
                // Amount TUNGGAL untuk kedua sisi, minor unit currency asal.
                AmountField(
                  key: const Key('transfer.form.amount'),
                  controller: _amountController,
                  currency: currency,
                  errorText: _amountError,
                  labelText: 'Nominal',
                  helperText: 'Disimpan minor unit ${currency.code}.',
                ),
                const SizedBox(height: 16),
                ListTile(
                  key: const Key('transfer.form.date'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Tanggal'),
                  subtitle: Text(
                    _dateFormatter.format(_date, style: DateStyle.full),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDate,
                ),
                TextField(
                  key: const Key('transfer.form.note'),
                  controller: _noteController,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('transfer.form.save'),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Simpan Transfer'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
