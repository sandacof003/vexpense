import 'package:shared_preferences/shared_preferences.dart';

import 'currency.dart';

/// Penyimpanan pengaturan aplikasi (status onboarding + currency default).
///
/// Dipakai SharedPreferences, bukan Drift: ini pengaturan UI yang harus
/// tersedia SEBELUM database siap, dan tidak ada dependensi jaringan.
/// (BE-01 owns `lib/core/data/` — jangan disentuh dari sini.)
class SettingsStorage {
  SettingsStorage(this._prefs);

  final SharedPreferences _prefs;

  static const onboardingCompletedKey = 'onboarding.completed';
  static const defaultCurrencyKey = 'settings.default_currency';

  /// `false` pada instalasi baru — onboarding harus tampil.
  bool get onboardingCompleted =>
      _prefs.getBool(onboardingCompletedKey) ?? false;

  Future<bool> setOnboardingCompleted(bool value) =>
      _prefs.setBool(onboardingCompletedKey, value);

  /// IDR bila belum pernah dipilih (default PRD).
  AppCurrency get defaultCurrency =>
      AppCurrency.fromCode(_prefs.getString(defaultCurrencyKey));

  Future<bool> setDefaultCurrency(AppCurrency currency) =>
      _prefs.setString(defaultCurrencyKey, currency.code);
}
