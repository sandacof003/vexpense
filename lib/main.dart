import 'package:flutter/material.dart';

import 'features/dashboard/dashboard_screen.dart';

void main() {
  runApp(const VExpenseApp());
}

class VExpenseApp extends StatelessWidget {
  const VExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V Expense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}
