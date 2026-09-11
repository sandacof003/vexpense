import 'package:flutter_test/flutter_test.dart';
import 'package:v_expense/core/formatters/app_locale.dart';
import 'package:v_expense/core/formatters/currency_format.dart';
import 'package:v_expense/core/formatters/date_formatter.dart';
import 'package:v_expense/core/formatters/money_formatter.dart';
import 'package:v_expense/core/validators/transaction_form_validators.dart';
import 'package:v_expense/core/widgets/amount_field.dart';
import 'package:flutter/material.dart';

void main() {
  final idr = kDefaultCurrencyFormats['IDR']!;
  final jpy = kDefaultCurrencyFormats['JPY']!;
  final usd = kDefaultCurrencyFormats['USD']!;
  final usdt = kDefaultCurrencyFormats['USDT']!;
  const id = MoneyFormatter(locale: AppLocale.id);
  const en = MoneyFormatter(locale: AppLocale.en);

  group('MoneyFormatter.format (minor unit → teks, per minor_unit)', () {
    test('IDR minorUnit 0: 1500000 minor → 1.500.000', () {
      expect(id.formatMinor(1500000, idr), '1.500.000');
      expect(id.format(1500000, idr), 'Rp 1.500.000');
    });
    test('JPY minorUnit 0: 12345 minor → 12.345 (tanpa desimal)', () {
      expect(id.formatMinor(12345, jpy), '12.345');
      expect(id.format(12345, jpy), '¥ 12.345');
    });
    test('USD minorUnit 2: 2550 minor → 25,50 (ID) / 25.50 (EN)', () {
      expect(id.formatMinor(2550, usd), '25,50');
      expect(en.formatMinor(2550, usd), '25.50');
      expect(id.format(2550, usd), r'$ 25,50');
    });
    test('USDT minorUnit 6: 1500000 minor → 1,500000', () {
      expect(id.formatMinor(1500000, usdt), '1,500000');
      expect(id.formatMinor(1, usdt), '0,000001');
    });
    test('nilai kecil & negatif', () {
      expect(id.formatMinor(500, idr), '500');
      expect(id.formatMinor(-2550, usd), '-25,50');
    });
    test('format dari Currency row DB (minorUnit/symbol dari tabel currencies)',
        () {
      // Simulasi baris dari CurrenciesRepository.
      final fromDb = CurrencyFormat(code: 'IDR', minorUnit: 0, symbol: 'Rp');
      expect(id.format(1500000, fromDb), 'Rp 1.500.000');
      final usdtDb = CurrencyFormat(code: 'USDT', minorUnit: 6, symbol: '₮');
      expect(id.format(1500000, usdtDb), '₮ 1,500000');
    });
  });

  group('MoneyFormatter.parseMinor (teks lokal → minor unit)', () {
    test('"1.500.000" locale ID → IDR 1500000', () {
      expect(id.parseMinor('1.500.000', idr), 1500000);
    });
    test('"25,50" locale ID → USD 2550 (dua decimal dipertahankan)', () {
      expect(id.parseMinor('25,50', usd), 2550);
      expect(id.parseMinor('25,5', usd), 2550); // "25,5" = 25.50
      expect(id.parseMinor('25', usd), 2500);
    });
    test('locale EN: "1,500,000" → IDR 1500000; "25.50" → USD 2550', () {
      expect(en.parseMinor('1,500,000', idr), 1500000);
      expect(en.parseMinor('25.50', usd), 2550);
    });
    test('USDT: "1,5" → 1500000 (fraksi di-pad kanan)', () {
      expect(id.parseMinor('1,5', usdt), 1500000);
      expect(id.parseMinor('0,000001', usdt), 1);
    });
    test('simbol currency di input diabaikan', () {
      expect(id.parseMinor('Rp 1.500.000', idr), 1500000);
      expect(id.parseMinor(r'$ 25,50', usd), 2550);
    });
    test('JPY tidak menerima desimal', () {
      expect(() => id.parseMinor('12,5', jpy), throwsFormatException);
    });
    test('fraksi melebihi minor_unit ditolak', () {
      expect(() => id.parseMinor('25,505', usd), throwsFormatException);
      expect(() => id.parseMinor('1,0000001', usdt), throwsFormatException);
    });
    test('bukan angka ditolak', () {
      expect(() => id.parseMinor('abc', idr), throwsFormatException);
      expect(() => id.parseMinor('', idr), throwsFormatException);
      expect(() => id.parseMinor('1,2,3', idr), throwsFormatException);
    });
    test('tidak ada floating point: hasil selalu integer exact', () {
      // 0.1 + 0.2 style trap: USD 10,10 + 20,20 harus exact 3030 minor.
      final a = id.parseMinor('10,10', usd);
      final b = id.parseMinor('20,20', usd);
      expect(a + b, 3030);
      expect(id.formatMinor(a + b, usd), '30,30');
    });
    test('round-trip format→parse konsisten semua currency', () {
      for (final c in kDefaultCurrencyFormats.values) {
        const minor = 1234567;
        expect(
          id.parseMinor(id.formatMinor(minor, c), c),
          minor,
          reason: 'round-trip gagal untuk ${c.code}',
        );
        expect(
          en.parseMinor(en.formatMinor(minor, c), c),
          minor,
          reason: 'round-trip EN gagal untuk ${c.code}',
        );
      }
    });
  });

  group('CurrencyFormat.fromCode', () {
    test('kode dikenal & fallback IDR', () {
      expect(CurrencyFormat.fromCode('USD').minorUnit, 2);
      expect(CurrencyFormat.fromCode('USDT').minorUnit, 6);
      expect(CurrencyFormat.fromCode(null).code, 'IDR');
      expect(CurrencyFormat.fromCode('XXX').code, 'IDR');
    });
    test('seed identik dengan AppCurrency enum (minor unit)', () {
      // Guard konsistensi: fallback offline = seed DB = AppCurrency.
      for (final c in kDefaultCurrencyFormats.values) {
        expect(c.minorUnit, CurrencyFormat.fromCode(c.code).minorUnit);
      }
    });
  });

  group('DateFormatter', () {
    final d = DateTime(2026, 8, 5, 14, 30);
    test('locale ID', () {
      const f = DateFormatter(locale: AppLocale.id);
      expect(f.format(d, style: DateStyle.full), '5 Agustus 2026');
      expect(f.format(d, style: DateStyle.medium), '5 Agu 2026');
      expect(f.format(d, style: DateStyle.short), '05/08/2026');
      expect(f.format(d, style: DateStyle.iso), '2026-08-05');
      expect(f.formatDateTime(d), '5 Agu 2026 14.30');
      expect(f.dayName(d), 'Rabu'); // 2026-08-05 memang Rabu
    });
    test('locale EN', () {
      const f = DateFormatter(locale: AppLocale.en);
      expect(f.format(d, style: DateStyle.full), 'August 5, 2026');
      expect(f.format(d, style: DateStyle.medium), 'Aug 5, 2026');
      expect(f.formatDateTime(d), 'Aug 5, 2026 14:30');
      expect(f.dayName(d), 'Wednesday');
    });
  });

  group('TransactionFormValidators', () {
    const v = TransactionFormValidators();
    test('amount positif diterima; nol/negatif ditolak', () {
      expect(v.validateAmount('1.500.000', idr).minorUnit, 1500000);
      expect(v.validateAmount('1.500.000', idr).error, isNull);
      expect(v.validateAmount('0', idr).minorUnit, isNull);
      expect(v.validateAmount('0', idr).error, 'Nominal harus lebih dari 0');
      expect(v.validateAmount('-100', idr).error, isNotNull);
      expect(v.validateAmount('0,00', usd).minorUnit, isNull);
      expect(v.validateAmount('0,00', usd).error, 'Nominal harus lebih dari 0');
    });
    test('amount kosong & invalid ditolak', () {
      expect(v.validateAmount('', idr).error, 'Nominal wajib diisi');
      expect(v.validateAmount('   ', idr).error, 'Nominal wajib diisi');
      expect(v.validateAmount('abc', idr).error, isNotNull);
    });
    test('kategori wajib untuk income/expense', () {
      expect(v.validateCategoryRequired(null), 'Kategori wajib dipilih');
      expect(v.validateCategoryRequired(3), isNull);
    });
    test('transfer menolak akun asal == tujuan', () {
      expect(
        v.validateTransferAccounts(1, 1),
        'Akun asal dan tujuan tidak boleh sama',
      );
      expect(v.validateTransferAccounts(1, 2), isNull);
      expect(v.validateTransferAccounts(null, 2), 'Akun asal wajib dipilih');
      expect(v.validateTransferAccounts(1, null), 'Akun tujuan wajib dipilih');
    });
    test('nama wajib diisi', () {
      expect(v.validateNameRequired(null), 'Nama wajib diisi');
      expect(v.validateNameRequired('  '), 'Nama wajib diisi');
      expect(v.validateNameRequired('Tunai'), isNull);
    });
  });

  group('AmountField (widget)', () {
    testWidgets('simbol tampil sebagai prefix, tidak masuk nilai', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmountField(controller: controller, currency: idr),
          ),
        ),
      );
      expect(find.text('Rp '), findsOneWidget); // prefixText
      await tester.enterText(find.byType(TextField), '1500000');
      // Formatter menulis ulang dengan grouping locale ID; simbol tidak
      // pernah masuk ke nilai teks.
      expect(controller.text, '1.500.000');
      expect(controller.text.contains('Rp'), isFalse);
      final field = tester.widget<AmountField>(find.byType(AmountField));
      expect(field.minorUnit, 1500000);
    });

    testWidgets('USD: minorUnit dari teks mempertahankan 2 decimal', (tester) async {
      final controller = TextEditingController(text: '25,50');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmountField(controller: controller, currency: usd),
          ),
        ),
      );
      final field = tester.widget<AmountField>(find.byType(AmountField));
      expect(field.minorUnit, 2550);
      expect(find.text(r'$ '), findsOneWidget);
    });

    testWidgets('input invalid → minorUnit null (tidak melempar)', (tester) async {
      final controller = TextEditingController(text: '');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmountField(controller: controller, currency: idr),
          ),
        ),
      );
      final field = tester.widget<AmountField>(find.byType(AmountField));
      expect(field.minorUnit, isNull);
    });
  });
}
