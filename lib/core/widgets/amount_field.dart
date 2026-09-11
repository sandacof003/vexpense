import 'package:flutter/material.dart';

import '../formatters/app_locale.dart';
import '../formatters/currency_format.dart';
import '../formatters/money_formatter.dart';
import 'amount_input_formatter.dart';

/// Field input nominal dengan simbol currency sebagai prefix.
///
/// Nilai yang dipegang controller MURNI nominal tanpa simbol
/// (mis. `1.500.000` locale ID), jadi simbol tidak pernah ikut tersimpan.
/// Ambil minor unit tersimpan lewat [minorUnit] (null bila input invalid/kosong).
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    this.locale = AppLocale.id,
    this.labelText,
    this.helperText,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final CurrencyFormat currency;
  final AppLocale locale;
  final String? labelText;
  final String? helperText;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// Minor unit dari teks saat ini; `null` bila kosong/invalid.
  /// Tidak melempar exception — cocok untuk recompute preview di UI.
  int? get minorUnit {
    try {
      return MoneyFormatter(locale: locale).parseMinor(
        controller.text,
        currency,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [
        AmountInputFormatter(currency: currency, locale: locale),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: labelText ?? 'Nominal',
        helperText: helperText,
        errorText: errorText,
        prefixText: '${currency.symbol} ',
      ),
    );
  }
}
