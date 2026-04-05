import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'core/providers/currency_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/home/presentation/screens/dashboard_screen.dart';
import 'features/expenses/presentation/screens/expense_list_screen.dart';
import 'features/expenses/presentation/screens/add_expense_screen.dart';
import 'features/ocr/presentation/screens/ocr_screen.dart';
import 'features/auth/presentation/screens/profile_screen.dart';

// Global Hive box references
late Box usersBox;
late Box transactionsBox;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  usersBox = await Hive.openBox('users');
  transactionsBox = await Hive.openBox('transactions');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CurrencyProvider()),
      ],
      child: MaterialApp(
        title: 'Smart Expense Tracker',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: false,
        ),
        home: const LoginScreen(),
        routes: {
          '/dashboard': (ctx) => const DashboardScreen(),
          '/expenses': (ctx) => const ExpenseListScreen(),
          '/add-expense': (ctx) => const AddExpenseScreen(),
          '/ocr': (ctx) => const OcrScreen(), // Unified receipt scanner
          '/profile': (ctx) => const ProfileScreen(),
        },
      ),
    );
  }
}