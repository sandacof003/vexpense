import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'currency.dart';
import 'settings_storage.dart';

/// SharedPreferences asli — di-override di widget test.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider harus di-override '
    '(SharedPreferences.setMockInitialValues di test, '
    'SharedPreferences.getInstance() di main).',
  );
});

final settingsStorageProvider = Provider<SettingsStorage>(
  (ref) => SettingsStorage(ref.watch(sharedPreferencesProvider)),
);

/// State status onboarding. `false` pada instalasi baru.
final onboardingCompletedProvider =
    NotifierProvider<OnboardingCompletedNotifier, bool>(
      OnboardingCompletedNotifier.new,
    );

class OnboardingCompletedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsStorageProvider).onboardingCompleted;

  Future<void> complete() async {
    final storage = ref.read(settingsStorageProvider);
    await storage.setOnboardingCompleted(true);
    state = true;
  }
}

/// Currency default pilihan user; fallback IDR (PRD).
final defaultCurrencyProvider =
    NotifierProvider<DefaultCurrencyNotifier, AppCurrency>(
      DefaultCurrencyNotifier.new,
    );

class DefaultCurrencyNotifier extends Notifier<AppCurrency> {
  @override
  AppCurrency build() => ref.watch(settingsStorageProvider).defaultCurrency;

  Future<void> select(AppCurrency currency) async {
    final storage = ref.read(settingsStorageProvider);
    await storage.setDefaultCurrency(currency);
    state = currency;
  }
}
