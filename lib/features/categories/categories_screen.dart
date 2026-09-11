import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/data/enums.dart';
import '../../core/di/providers.dart';
import 'category_appearance.dart';
import 'category_form_screen.dart';

/// List kategori, dikelompokkan per tipe (Pengeluaran / Pemasukan) sesuai
/// wireframe screen 7. Data live dari [categoriesProvider].
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  static const path = '/categories';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kategori')),
      floatingActionButton: FloatingActionButton(
        key: const Key('categories.add'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CategoryFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat kategori: $e')),
        data: (list) {
          final expense =
              list.where((c) => c.type == CategoryType.expense).toList();
          final income =
              list.where((c) => c.type == CategoryType.income).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle(context, 'Pengeluaran'),
              ...expense.map((c) => _tile(context, c)),
              const SizedBox(height: 16),
              _sectionTitle(context, 'Pemasukan'),
              ...income.map((c) => _tile(context, c)),
              const SizedBox(height: 8),
              Text(
                'ℹ️ Kategori yang dipakai transaksi tidak hilang datanya: '
                'saat dihapus, transaksinya dipindahkan ke kategori '
                '"Lainnya" (atau kategori lain dengan tipe sama).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall,
    ),
  );

  Widget _tile(BuildContext context, Category category) => ListTile(
    key: Key('categories.item.${category.id}'),
    leading: CircleAvatar(
      backgroundColor: categoryColor(category.color),
      child: Icon(categoryIcon(category.icon), size: 20),
    ),
    title: Text(category.name),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryFormScreen(category: category),
      ),
    ),
  );
}
