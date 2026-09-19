import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/accounts_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/transactions/presentation/transaction_list_screen.dart';
import '../settings/settings_providers.dart';

/// Routing aplikasi: onboarding vs area utama.
///
/// Router dibuat STABIL (tidak recreate saat state berubah); redirect
/// membaca status onboarding terbaru via `ref.read` sehingga:
/// - boot instalasi baru → `/onboarding`
/// - boot setelah selesai → `/dashboard`
/// - onboarding tidak bisa diakses lagi setelah selesai
/// Navigasi setelah selesai onboarding dilakukan eksplisit dengan
/// `context.go('/dashboard')` dari [OnboardingScreen].
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final completed = ref.read(onboardingCompletedProvider);
      final path = state.matchedLocation;

      if (completed) {
        return (path == '/onboarding' || path == '/') ? '/dashboard' : null;
      }
      return path == '/onboarding' ? null : '/onboarding';
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: AccountsScreen.path,
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: CategoriesScreen.path,
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: TransactionListScreen.path,
        builder: (context, state) => const TransactionListScreen(),
      ),
    ],
  );
});
