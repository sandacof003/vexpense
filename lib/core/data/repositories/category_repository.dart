import 'package:drift/drift.dart';

import '../database.dart';
import '../enums.dart';
import '../daos/category_dao.dart';
import '../daos/transaction_dao.dart';
import 'account_repository.dart' show DuplicateNameException;
import 'repository_contracts.dart';

/// Repository kategori: CRUD + kebijakan hapus (pindah ke "Lainnya").
class CategoryRepository implements CategoriesRepository {
  CategoryRepository(this._db, this._categoryDao, this._transactionDao);

  final AppDatabase _db;
  final CategoryDao _categoryDao;
  final TransactionDao _transactionDao;

  @override
  Future<List<Category>> getAll() => _categoryDao.getAll();
  @override
  Stream<List<Category>> watchAll() => _categoryDao.watchAll();
  @override
  Future<List<Category>> getByType(CategoryType type) =>
      _categoryDao.getByType(type);
  @override
  Future<Category?> getById(int id) => _categoryDao.getById(id);

  /// Kategori "Lainnya" untuk tipe tertentu (fallback saat hapus kategori).
  /// [excludeId] = kategori yang sedang dihapus — tidak boleh jadi fallback
  /// dirinya sendiri (hapus "Lainnya" saat cuma "Lainnya" yang tersisa
  /// membuat reassign menunjuk baris yang dihapus → FK RESTRICT gagal).
  Future<Category?> _findFallback(
    CategoryType type, {
    required int excludeId,
  }) async {
    final byName = await _categoryDao.getByName('Lainnya');
    if (byName != null && byName.type == type && byName.id != excludeId) {
      return byName;
    }
    final sameType = await _categoryDao.getByType(type);
    final candidates = sameType.where((c) => c.id != excludeId).toList();
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<Category> create({
    required String name,
    required CategoryType type,
    String? color,
    String? icon,
  }) async {
    final existing = await _categoryDao.getByName(name);
    if (existing != null) {
      throw const DuplicateNameException('Nama kategori sudah dipakai');
    }
    final id = await _categoryDao.insert(
      CategoriesCompanion.insert(
        name: name,
        type: type,
        color: Value(color),
        icon: Value(icon),
      ),
    );
    return (await _categoryDao.getById(id))!;
  }

  @override
  Future<void> update(
    Category category, {
    required String newName,
    String? color,
    String? icon,
  }) async {
    final existing = await _categoryDao.getByName(newName);
    if (existing != null && existing.id != category.id) {
      throw const DuplicateNameException('Nama kategori sudah dipakai');
    }
    await _categoryDao.replace(
      category.copyWith(name: newName, color: Value(color), icon: Value(icon)),
    );
  }

  /// Hapus kategori. Transaksi yang memakainya dipindah ke "Lainnya" (fallback
  /// dengan tipe sama). Lempar [StateError] bila tidak ada fallback.
  @override
  Future<void> delete(int id) async {
    final category = await _categoryDao.getById(id);
    if (category == null) return;

    final fallback = await _findFallback(category.type, excludeId: id);
    if (fallback == null) {
      throw StateError(
        'Tidak ada kategori fallback untuk tipe ${category.type.name}',
      );
    }

    await _db.transaction(() async {
      await _transactionDao.reassignCategory(id, fallback.id);
      await _categoryDao.remove(id);
    });
  }
}
