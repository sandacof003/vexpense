import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v_expense/app/v_expense_app.dart';
import 'package:v_expense/core/data/database.dart';
import 'package:v_expense/core/di/providers.dart';
import 'package:v_expense/core/settings/settings_providers.dart';
import 'package:v_expense/features/dashboard/dashboard_screen.dart';
import 'package:v_expense/features/onboarding/onboarding_screen.dart';

Future<ProviderScope> buildApp() async {
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
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
}

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

/// Dashboard FE-03 membuka drift stream (watchAll/watchFiltered). Dispose
/// autoDispose saat tree dibongkar menjadwalkan timer 0-delay drift yang
/// TIDAK ter-flush pumpAndSettle — bongkar tree lalu majukan clock (pola
/// transaction_form_test) supaya invariant "pending timer" tidak gagal.
Future<void> flushDashboardTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  setUp(() {
    // Instalasi baru per test; test restart sengaja TIDAK reset di tengah.
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('instalasi baru redirect ke onboarding', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  testWidgets('onboarding selesai (pilih USD) langsung ke dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tapCurrency(tester, 'USD');
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding.continue')));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('dashboard.quick.add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transaction.form.account')), findsOneWidget);

    await flushDashboardTimers(tester);
  });

  testWidgets('onboarding bisa dilewati dan tetap masuk dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding.skip')));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);

    await flushDashboardTimers(tester);
  });

  testWidgets(
    'status selesai bertahan setelah restart (tanpa onboarding lagi)',
    (tester) async {
      // Sesi 1: selesaikan onboarding.
      await tester.pumpWidget(await buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding.skip')));
      await tester.pumpAndSettle();

      // Simulasi restart: tree baru dibangun di atas SharedPreferences store
      // yang sama (persisten di device) — provider reload state dari storage.
      await tester.pumpWidget(await buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);

      await flushDashboardTimers(tester);
    },
  );
}
