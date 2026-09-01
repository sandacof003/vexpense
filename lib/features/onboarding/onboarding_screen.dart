import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/currency.dart';
import '../../core/settings/settings_providers.dart';

/// Onboarding satu langkah: pilih currency default, lalu lanjut ke dashboard.
///
/// Acceptance FE-01:
/// - Currency default terpilih tersimpan; bila user tidak memilih apa pun
///   dan langsung "Lewati", nilai tetap IDR (default PRD).
/// - Tombol "Lewati" menyelesaikan onboarding tanpa memilih currency.
/// - Status selesai ditulis ke storage, bertahan setelah restart.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  AppCurrency _selected = AppCurrency.idr;

  Future<void> _finish() async {
    await ref.read(defaultCurrencyProvider.notifier).select(_selected);
    await ref.read(onboardingCompletedProvider.notifier).complete();
    if (mounted) context.go('/dashboard');
  }

  Future<void> _skip() async {
    // Sengaja tidak memanggil select() — storage fallback ke IDR,
    // memenuhi acceptance "bernilai IDR bila tidak dipilih".
    await ref.read(onboardingCompletedProvider.notifier).complete();
    if (mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Selamat datang'),
        actions: [
          TextButton(
            key: const Key('onboarding.skip'),
            onPressed: _skip,
            child: const Text('Lewati'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 64),
              const SizedBox(height: 16),
              Text('V Expense', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Pilih currency default untuk mulai mencatat pengeluaran.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: AppCurrency.values.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final currency = AppCurrency.values[index];
                    final selected = currency == _selected;
                    return Card(
                      elevation: selected ? 2 : 0,
                      child: ListTile(
                        key: Key('onboarding.currency.${currency.code}'),
                        title: Text(currency.code),
                        subtitle: Text(currency.displayName),
                        trailing: selected
                            ? Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () => setState(() => _selected = currency),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('onboarding.continue'),
                onPressed: _finish,
                child: const Text('Mulai'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
