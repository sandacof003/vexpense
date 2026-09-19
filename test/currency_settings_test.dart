import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v_expense/app/v_expense_app.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/core/settings/currency.dart';
import 'package:v_expense/core/settings/settings_providers.dart';
import 'package:v_expense/features/dashboard/dashboard_screen.dart';

Future<SharedPreferences> freshPrefs() {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget buildScope(SharedPreferences prefs) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    // Dashboard FE-03 membaca DB; pakai in-memory supaya tidak menyentuh
    // path_provider (tidak tersedia di flutter_test).
    appDatabaseProvider.overrideWithValue(
      AppDatabase.forTesting(NativeDatabase.memory()),
    ),
  ],
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

/// Dashboard FE-03 membuka drift stream; bongkar tree lalu majukan clock
/// supaya timer 0-delay drift ter-flush (pola transaction_form_test).
Future<void> flushDashboardTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
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

    await flushDashboardTimers(tester);
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

    await flushDashboardTimers(tester);
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

    await flushDashboardTimers(tester);
  });

  test('fromCode fallback ke IDR untuk kode kosong/tidak dikenal', () {
    expect(AppCurrency.fromCode(null), AppCurrency.idr);
    expect(AppCurrency.fromCode(''), AppCurrency.idr);
    expect(AppCurrency.fromCode('XXX'), AppCurrency.idr);
  });
}
