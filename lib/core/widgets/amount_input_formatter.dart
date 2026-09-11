import 'package:flutter/services.dart';

import '../formatters/app_locale.dart';
import '../formatters/currency_format.dart';

/// InputFormatter untuk field nominal: mengetik digit apa pun langsung
/// ditulis ulang sebagai nominal dengan grouping ribuan sesuai locale.
///
/// Model input = "digit mentah": setiap ketikan digit diperlakukan sebagai
/// digit minor-unit berikutnya (seperti kalkator/kasir). Contoh locale ID:
/// - IDR (minorUnit 0): ketik 1,5,0 → `1.500.000` (fraksi selalu 0)
/// - USD (minorUnit 2): ketik 2,5,5,0 → `25,50`
///
/// Simbol currency TIDAK pernah masuk ke nilai teks — simbol tampil sebagai
/// prefix widget [AmountField], sehingga `controller.text` selalu murni
/// nominal dan aman diparse lewat `MoneyFormatter.parseMinor`.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({
    required this.currency,
    this.locale = AppLocale.id,
  });

  final CurrencyFormat currency;
  final AppLocale locale;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final text = _formatDigits(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _formatDigits(String digits) {
    if (currency.minorUnit == 0) return _group(digits);
    if (digits.length <= currency.minorUnit) {
      return '0${locale.decimalSeparator}$digits';
    }
    final frac = digits.substring(digits.length - currency.minorUnit);
    final major = digits.substring(0, digits.length - currency.minorUnit);
    return '${_group(major)}${locale.decimalSeparator}$frac';
  }

  String _group(String digits) {
    if (digits.length <= 3) return digits;
    final parts = <String>[];
    var rest = digits;
    while (rest.length > 3) {
      parts.insert(0, rest.substring(rest.length - 3));
      rest = rest.substring(0, rest.length - 3);
    }
    parts.insert(0, rest);
    return parts.join(locale.groupSeparator);
  }
}
