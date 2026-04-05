import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; 
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../../main.dart';
import 'register_screen.dart';
import '../../../home/presentation/screens/dashboard_screen.dart';
import 'forgot_password_screen.dart';
import '../../../../core/providers/currency_provider.dart'; 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // DEBUG: Add these prints to see what's happening
    print('=== DEBUG LOGIN ===');
    print('Login attempt for: $email');
    print('Using global usersBox: ${usersBox.name}');

    // DEBUG: Print all users to see what's in the box
    print('All users in box: ${usersBox.keys.toList()}');
    print('Looking for key: "$email"');
    print('Key exists? ${usersBox.containsKey(email)}');

    if (!usersBox.containsKey(email)) {
      print('❌ USER NOT FOUND: No entry found for email: $email');
      setState(() => _errorMessage = 'User not found');
      return;
    }

    final user = usersBox.get(email);
    print('✅ User found: $user');

    String storedHash;
    Map<dynamic, dynamic>? userData;
    
    if (user is Map) {
      userData = user;
      storedHash = user['passwordHash']?.toString() ?? '';
      print('User data is Map, passwordHash: $storedHash');
    } else if (user is String) {
      storedHash = user;
      print('User data is String: $storedHash');
    } else {
      print('❌ UNEXPECTED DATA TYPE: ${user.runtimeType}');
      setState(() => _errorMessage = 'Invalid user data');
      return;
    }

    final computedHash = hashPassword(password);
    print('Computed hash: $computedHash');
    print('Hashes match: ${storedHash == computedHash}');

    if (storedHash != computedHash) {
      setState(() => _errorMessage = 'Incorrect password');
      return;
    }

    // ✅ LOGIN SUCCESSFUL - Now load user's currency preference
    print('✅ LOGIN SUCCESSFUL');
    
    // Load user's saved currency if available
    if (userData != null && userData.containsKey('currency')) {
      final savedCurrency = userData['currency']?.toString();
      if (savedCurrency != null) {
        print('Loading saved currency: $savedCurrency');
        
        // Get currency provider and set the saved currency
        final currencyProvider = context.read<CurrencyProvider>();
        try {
          await currencyProvider.setCurrency(savedCurrency);
          print('Currency provider updated with: $savedCurrency');
        } catch (e) {
          print('Error setting currency: $e');
        }
      }
    } else {
      print('No currency preference found for user, using default');
    }

    setState(() => _errorMessage = null);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Login successful!')));
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7F7FD5), Color(0xFF86A8E7), Color(0xFF91EAE4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 24,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.deepPurple[100],
                          child: const Icon(
                            Icons.lock_open,
                            size: 40,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Login',
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(
                            color: Colors.deepPurple[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_errorMessage != null)
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email),
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator:
                              (value) =>
                                  value == null || value.isEmpty
                                      ? 'Enter email'
                                      : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          obscureText: true,
                          validator:
                              (value) =>
                                  value == null || value.isEmpty
                                      ? 'Enter password'
                                      : null,
                        ),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                _login();
                              }
                            },
                            child: const Text(
                              'Login',
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),

                        const SizedBox(height: 7),
                        // centered column: forgot password above register
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) =>
                                            const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'Forgot password?',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.deepPurple),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => const RegisterScreen(),
                                    transitionsBuilder: (
                                      context,
                                      animation,
                                      secondaryAnimation,
                                      child,
                                    ) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      );
                                    },
                                  ),
                                );
                              },
                              child: const Text(
                                'Don\'t have an account? Sign up',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.deepPurple),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}