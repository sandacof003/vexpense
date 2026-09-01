import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v_expense/app/v_expense_app.dart';
import 'package:v_expense/core/settings/currency.dart';
import 'package:v_expense/core/settings/settings_providers.dart';
import 'package:v_expense/features/dashboard/dashboard_screen.dart';

Future<SharedPreferences> freshPrefs() {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget buildScope(SharedPreferences prefs) => ProviderScope(
  overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  child: const VExpenseApp(),
);

/// Tap item currency di list onboarding (scroll dulu bila di luar viewport).
Future<void> tapCurrency(WidgetTester tester, String code) async {
  final key = find.byKey(Key('onboarding.currency.$code'));
  await tester.dragUntilVisible(
    key,
    find.byType(ListView),
    const Offset(0, -80),
  );
  await tester.tap(key);
}

void main() {
  test('currency default bernilai IDR bila tidak dipilih', () async {
    final prefs = await freshPrefs();

    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(defaultCurrencyProvider), AppCurrency.idr);
    expect(prefs.getString('settings.default_currency'), isNull);
  });

  testWidgets('currency yang dipilih di onboarding tersimpan ke storage', (
    tester,
  ) async {
    final prefs = await freshPrefs();
    await tester.pumpWidget(buildScope(prefs));
    await tester.pumpAndSettle();

    await tapCurrency(tester, 'SGD');
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding.continue')));
    await tester.pumpAndSettle();

    expect(prefs.getString('settings.default_currency'), 'SGD');
    expect(find.text('Currency default: SGD'), findsOneWidget);
  });

  testWidgets('skip onboarding tidak menulis currency; tetap tampil IDR', (
    tester,
  ) async {
    final prefs = await freshPrefs();
    await tester.pumpWidget(buildScope(prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding.skip')));
    await tester.pumpAndSettle();

    expect(prefs.getString('settings.default_currency'), isNull);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Currency default: IDR'), findsOneWidget);
  });

  testWidgets('currency tersimpan bertahan setelah restart', (tester) async {
    final prefs = await freshPrefs();
    await tester.pumpWidget(buildScope(prefs));
    await tester.pumpAndSettle();

    await tapCurrency(tester, 'JPY');
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding.continue')));
    await tester.pumpAndSettle();

    // Restart: tree baru membaca ulang storage yang sama.
    await tester.pumpWidget(buildScope(prefs));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Currency default: JPY'), findsOneWidget);
  });

  test('fromCode fallback ke IDR untuk kode kosong/tidak dikenal', () {
    expect(AppCurrency.fromCode(null), AppCurrency.idr);
    expect(AppCurrency.fromCode(''), AppCurrency.idr);
    expect(AppCurrency.fromCode('XXX'), AppCurrency.idr);
  });
}
