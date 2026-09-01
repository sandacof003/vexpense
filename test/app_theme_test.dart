import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:v_expense/app/v_expense_app.dart';
import 'package:v_expense/core/settings/settings_providers.dart';
import 'package:v_expense/core/theme/app_theme.dart';

Widget buildApp(WidgetRef? _) => const VExpenseApp();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  testWidgets('instalasi baru selalu membuka dark theme', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(await prefs())],
        child: const VExpenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);
    expect(materialApp.theme!.brightness, Brightness.dark);
    expect(materialApp.theme, same(AppTheme.dark));
  });

  testWidgets('screen onboarding ikut dark theme (theme diterapkan app-wide)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(await prefs())],
        child: const VExpenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(scaffoldContext).brightness, Brightness.dark);
    expect(Theme.of(scaffoldContext).colorScheme.brightness, Brightness.dark);
  });
}
