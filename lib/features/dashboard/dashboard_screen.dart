import 'package:flutter/material.dart';

/// Shell screen sementara — agent FE bakal ganti dengan implementasi penuh
/// (8 screen wireframe: onboarding, dashboard, transaksi, akun, kategori,
/// laporan, pengaturan).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('V Expense')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.savings_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Scaffold siap',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Mulai dari struktur feature-based\n(lihat PRD.md + AGENTS.md)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
