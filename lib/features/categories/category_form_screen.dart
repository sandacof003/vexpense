import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/data/enums.dart';
import '../../core/data/repositories/account_repository.dart'
    show DuplicateNameException;
import '../../core/di/providers.dart';
import '../../core/validators/transaction_form_validators.dart';
import 'category_appearance.dart';
import 'domain/category_contract.dart';

/// Form tambah/edit kategori + picker warna & ikon.
///
/// Acceptance FE-06:
/// - Kategori income/expense memiliki type (SegmentedButton, wajib).
/// - Hapus kategori yang terpakai → transaksi dipindah ke fallback "Lainnya";
///   dialog konfirmasi menyebut fallback sebelum user setuju.
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key, this.category});

  /// `null` = mode tambah; terisi = mode edit.
  final Category? category;

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _nameController = TextEditingController();
  final _validators = const TransactionFormValidators();
  late CategoryType _type;
  late int _color;
  late String _icon;
  bool _saving = false;

  bool get _isEdit => widget.category != null;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController.text = category?.name ?? '';
    _type = category?.type ?? CategoryType.expense;
    _color = categoryColorRgb(category?.color);
    _icon = kCategoryIcons.containsKey(category?.icon)
        ? category!.icon!
        : kCategoryIcons.keys.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = _validators.validateNameRequired(_nameController.text);
    if (nameError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(nameError)));
      return;
    }
    setState(() => _saving = true);

    final repo = ref.read(categoryRepositoryProvider);
    final name = _nameController.text.trim();
    final colorHex = categoryColorHex(_color);
    try {
      if (_isEdit) {
        await repo.update(
          widget.category!,
          newName: name,
          color: colorHex,
          icon: _icon,
        );
      } else {
        final draft = CategoryDraft(
          name: name,
          type: _type,
          color: colorHex,
          icon: _icon,
        );
        await repo.create(
          name: draft.name,
          type: draft.type,
          color: draft.color,
          icon: draft.icon,
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
    final fallback = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus kategori?'),
        content: Text(
          'Kategori "${widget.category!.name}" akan dihapus. '
          'Transaksi yang memakainya dipindahkan ke kategori '
          '"Lainnya" (tipe ${widget.category!.type.name}).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('category.delete.confirm'),
            onPressed: () => Navigator.of(context).pop('yes'),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (fallback != 'yes' || !mounted) return;

    try {
      await ref.read(categoryRepositoryProvider).delete(widget.category!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on StateError catch (e) {
      // Tidak ada fallback se-tipe (mis. semua kategori income dihapus) —
      // hapus dibatalkan, data transaksi tetap utuh.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Kategori' : 'Tambah Kategori'),
        actions: [
          if (_isEdit)
            IconButton(
              key: const Key('category.delete'),
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
              key: const Key('category.form.name'),
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nama kategori'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<CategoryType>(
              segments: const [
                ButtonSegment(
                  value: CategoryType.expense,
                  label: Text('Pengeluaran'),
                ),
                ButtonSegment(
                  value: CategoryType.income,
                  label: Text('Pemasukan'),
                ),
              ],
              // Type dikunci saat edit: transaksi lama tetap income/expense
              // sesuai tipe semula; pindah tipe = laporan campur aduk.
              selected: {_type},
              onSelectionChanged: _isEdit
                  ? null
                  : (selected) => setState(() => _type = selected.first),
            ),
            const SizedBox(height: 24),
            Text('Warna', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in kCategoryColors)
                  InkWell(
                    key: Key('category.color.$color'),
                    onTap: () => setState(() => _color = color & 0xFFFFFF),
                    child: CircleAvatar(
                      backgroundColor: Color(color),
                      child: _color == (color & 0xFFFFFF)
                          ? const Icon(Icons.check, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Ikon', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in kCategoryIcons.entries)
                  InkWell(
                    key: Key('category.icon.${entry.key}'),
                    onTap: () => setState(() => _icon = entry.key),
                    child: CircleAvatar(
                      backgroundColor: _icon == entry.key
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      child: Icon(entry.value, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(_color | 0xFF000000),
                  child: Icon(categoryIcon(_icon), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _nameController.text.isEmpty
                        ? 'Pratinjau kategori'
                        : _nameController.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('category.form.save'),
              onPressed: _saving ? null : _save,
              child: Text(_isEdit ? 'Simpan Perubahan' : 'Buat Kategori'),
            ),
          ],
        ),
      ),
    );
  }
}
