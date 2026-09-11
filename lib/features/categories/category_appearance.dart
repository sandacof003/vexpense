import 'package:flutter/material.dart';

/// Palet warna kategori. Disimpan ke DB sebagai string `#rrggbb`
/// (kolom `categories.color`, nullable — seed bawaan = null).
const List<int> kCategoryColors = [
  0xFFEF5350,
  0xFFFF7043,
  0xFFFFA726,
  0xFFFFCA28,
  0xFF9CCC65,
  0xFF26A69A,
  0xFF42A5F5,
  0xFF5C6BC0,
  0xFFAB47BC,
  0xFFEC407A,
  0xFF8D6E63,
  0xFF78909C,
];

/// Ikon kategori: nama Material icon → disimpan di kolom `categories.icon`.
const Map<String, IconData> kCategoryIcons = {
  'restaurant': Icons.restaurant,
  'local_cafe': Icons.local_cafe,
  'directions_bus': Icons.directions_bus,
  'shopping_cart': Icons.shopping_cart,
  'receipt_long': Icons.receipt_long,
  'movie': Icons.movie,
  'favorite': Icons.favorite,
  'school': Icons.school,
  'work': Icons.work,
  'card_giftcard': Icons.card_giftcard,
  'payments': Icons.payments,
  'flight': Icons.flight,
  'home': Icons.home,
  'sports_esports': Icons.sports_esports,
  'pets': Icons.pets,
  'more_horiz': Icons.more_horiz,
};

/// Warna default kategori tanpa warna (seed bawaan).
const Color kCategoryColorFallback = Color(0xFF374151);

/// Parse `#rrggbb` dari DB; fallback abu-abu bila null/rusak (jangan crash
/// hanya karena satu baris aneh — list kategori tetap tampil).
Color categoryColor(String? hex) => Color(categoryColorRgb(hex) | 0xFF000000);

/// Parse `#rrggbb` dari DB jadi nilai RGB 24-bit (tanpa alpha).
/// Fallback = abu-abu [kCategoryColorFallback] (0x374151).
int categoryColorRgb(String? hex) {
  const fallback = 0x374151;
  if (hex == null) return fallback;
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null ? fallback : value & 0xFFFFFF;
}

/// Serialize warna palet jadi `#rrggbb` untuk disimpan.
String categoryColorHex(int color) =>
    '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Resolve nama ikon dari DB; fallback ikon label generik.
IconData categoryIcon(String? name) => kCategoryIcons[name] ?? Icons.label_outline;
