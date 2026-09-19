import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/data/enums.dart';
import '../../core/data/repositories/account_repository.dart'
    show AccountInUseException, DuplicateNameException;
import '../../core/di/providers.dart';
import '../../core/formatters/currency_format.dart';
import '../../core/formatters/money_formatter.dart';
import '../../core/settings/currency.dart';
import '../../core/validators/transaction_form_validators.dart';
import '../../core/widgets/amount_field.dart';
import 'domain/account_contract.dart';

/// Form tambah/edit akun.
///
/// Acceptance FE-06:
/// - Akun menyimpan type, currency, opening_balance (minor unit), created_at
///   (created_at otomatis oleh DB default).
/// - Opening balance diinput sebagai nominal dan disimpan minor unit currency
///   akun (USD → cent, IDR → integer biasa).
/// - Hapus akun dengan transaksi ditolak [AccountInUseException] dan alasan
///   ditampilkan ke user (SnackBar), bukan crash senyap.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.account});

  /// `null` = mode tambah; terisi = mode edit.
  final Account? account;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  final _validators = const TransactionFormValidators();
  late AccountType _type;
  late AppCurrency _currency;
  String? _balanceError;
  bool _saving = false;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _nameController.text = account?.name ?? '';
    _type = account?.type ?? AccountType.cash;
    _currency = AppCurrency.fromCode(account?.currency);
    if (account != null) {
      _balanceController.text = MoneyFormatter().formatMinor(
        account.openingBalance,
        CurrencyFormat.fromCode(account.currency),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  /// Minor unit dari field saldo: kosong = 0, invalid = null.
  int? _openingBalanceMinorUnit() {
    final text = _balanceController.text.trim();
    if (text.isEmpty) return 0;
    try {
      return MoneyFormatter().parseMinor(
        text,
        CurrencyFormat.fromCode(_currency.code),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _save() async {
    final nameError = _validators.validateNameRequired(_nameController.text);
    final balance = _openingBalanceMinorUnit();
    setState(() {
      _balanceError = balance == null ? 'Nominal tidak valid' : null;
      _saving = nameError == null && balance != null;
    });
    if (nameError != null || balance == null) {
      if (nameError != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(nameError)));
      }
      return;
    }

    final repo = ref.read(accountRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(
          widget.account!.copyWith(
            type: _type,
            currency: _currency.code,
            openingBalance: balance,
          ),
          newName: _nameController.text.trim(),
        );
      } else {
        final draft = AccountDraft(
          name: _nameController.text.trim(),
          type: _type,
          currency: _currency.code,
          openingBalanceMinorUnit: balance,
        );
        await repo.create(
          name: draft.name,
          type: draft.type,
          currency: draft.currency,
          openingBalance: draft.openingBalanceMinorUnit,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on DuplicateNameException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus akun?'),
        content: Text('Akun "${widget.account!.name}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('account.delete.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(accountRepositoryProvider).delete(widget.account!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on AccountInUseException {
      // Alasan penolakan WAJIB tampil (acceptance: "tampilkan alasan ketika
      // akun ditolak untuk dihapus").
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('account.delete.restricted'),
            content: Text(
              'Akun masih punya transaksi — tidak bisa dihapus. '
              'Pindahkan atau hapus transaksinya dulu.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = CurrencyFormat.fromCode(_currency.code);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Akun' : 'Tambah Akun'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const Key('account.delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('account.form.name'),
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nama akun'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<AccountType>(
              segments: const [
                ButtonSegment(
                  value: AccountType.cash,
                  label: Text('Cash'),
                  icon: Icon(Icons.payments_outlined),
                ),
                ButtonSegment(
                  value: AccountType.bank,
                  label: Text('Bank'),
                  icon: Icon(Icons.account_balance_outlined),
                ),
                ButtonSegment(
                  value: AccountType.ewallet,
                  label: Text('E-Wallet'),
                  icon: Icon(Icons.account_balance_wallet_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selected) =>
                  setState(() => _type = selected.first),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AppCurrency>(
              key: const Key('account.form.currency'),
              value: _currency,
              decoration: InputDecoration(
                labelText: _isEdit
                    ? 'Currency (dikunci — akun punya riwayat minor unit)'
                    : 'Currency',
              ),
              items: [
                for (final c in AppCurrency.values)
                  DropdownMenuItem(
                    value: c,
                    child: Text('${c.code} — ${c.displayName}'),
                  ),
              ],
              // Currency dikunci saat edit: opening balance & transaksi lama
              // tersimpan dalam minor unit currency semula; ganti currency
              // di tengah riwayat = korupsi nominal diam-diam.
              onChanged: _isEdit
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _currency = value;
                        // Teks lama diformat dengan minor unit currency
                        // sebelumnya → reset supaya tidak salah makna.
                        _balanceController.clear();
                      });
                    },
            ),
            const SizedBox(height: 16),
            AmountField(
              key: const Key('account.form.balance'),
              controller: _balanceController,
              currency: currencyFormat,
              labelText: 'Saldo awal',
              helperText:
                  'Boleh 0. Disimpan sebagai minor unit ${_currency.code}.',
              errorText: _balanceError,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('account.form.save'),
              onPressed: _saving ? null : _save,
              child: Text(_isEdit ? 'Simpan Perubahan' : 'Buat Akun'),
            ),
          ],
        ),
      ),
    );
  }
}
