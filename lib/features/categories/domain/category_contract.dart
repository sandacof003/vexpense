import '../../../core/data/enums.dart';

class CategoryDraft {
  const CategoryDraft({
    required this.name,
    required this.type,
    this.color,
    this.icon,
  });

  final String name;
  final CategoryType type;
  final String? color;
  final String? icon;
}
