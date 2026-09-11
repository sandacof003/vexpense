import 'package:drift/drift.dart';

import '../database.dart';
import '../enums.dart';
import '../tables.dart';

part 'category_dao.g.dart';

/// Akses baca/tulis tabel `categories`.
@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Future<List<Category>> getAll() =>
      (select(categories)..orderBy([(c) => OrderingTerm.asc(c.name)])).get();

  Stream<List<Category>> watchAll() =>
      (select(categories)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  /// Kategori dengan tipe tertentu (income / expense).
  Future<List<Category>> getByType(CategoryType type) =>
      (select(categories)
            ..where((c) => c.type.equalsValue(type))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  Future<Category?> getById(int id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Cari kategori berdasarkan nama (case-insensitive, exact match).
  Future<Category?> getByName(String name) => (select(
    categories,
  )..where((c) => c.name.lower().equals(name.toLowerCase()))).getSingleOrNull();

  Future<int> insert(CategoriesCompanion category) =>
      into(categories).insert(category);

  Future<bool> replace(Category category) =>
      update(categories).replace(category);

  Future<int> remove(int id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();
}
