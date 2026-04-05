import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; 
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../../main.dart';
import '../../../home/presentation/screens/dashboard_screen.dart';
import '../../../../core/providers/currency_provider.dart'; 
import '../../../../core/constants/currencies.dart'; 

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  String? _errorMessage;
  String _selectedCurrency = 'HUF'; // Default: Hungarian Forint

  String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (usersBox.containsKey(email)) {
      setState(() => _errorMessage = 'User already exists');
      return;
    }

    final userData = {
      'firstName': firstName,
      'lastName': lastName,
      'passwordHash': hashPassword(password),
      'currency': _selectedCurrency,           // Save currency code
      'registeredAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    try {
      await usersBox.put(email, userData);
      if (!mounted) return;
      // Get the currency provider and set the selected currency
      final currencyProvider = context.read<CurrencyProvider>();
      await currencyProvider.setCurrency(_selectedCurrency);
      if (!mounted) return;
      setState(() => _errorMessage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful!')),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to register: $e');
    }
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.deepPurple[100],
                          child: const Icon(Icons.person_add, size: 40, color: Colors.deepPurple),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Create Account',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.deepPurple[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_errorMessage != null)
                          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 8),

                        // First Name
                        TextFormField(
                          controller: _firstNameController,
                          decoration: InputDecoration(
                            labelText: 'First Name',
                            prefixIcon: const Icon(Icons.person),
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) => v?.isEmpty ?? true ? 'Enter first name' : null,
                        ),
                        const SizedBox(height: 16),

                        // Last Name
                        TextFormField(
                          controller: _lastNameController,
                          decoration: InputDecoration(
                            labelText: 'Last Name',
                            prefixIcon: const Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) => v?.isEmpty ?? true ? 'Enter last name' : null,
                        ),
                        const SizedBox(height: 16),

                        // Email
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email),
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) => v?.isEmpty ?? true ? 'Enter email' : null,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) => v?.isEmpty ?? true ? 'Enter password' : null,
                        ),
                        const SizedBox(height: 16),

                        // CURRENCY PICKER - Updated to use CurrencyConstants
                        DropdownButtonFormField<String>(
                          value: _selectedCurrency,
                          decoration: InputDecoration(
                            labelText: 'Preferred Currency',
                            prefixIcon: const Icon(Icons.currency_exchange),
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: CurrencyConstants.currencyCodes.map((currencyCode) {
                            final currency = CurrencyConstants.getCurrency(currencyCode);
                            return DropdownMenuItem(
                              value: currencyCode,
                              child: Row(
                                children: [
                                  Text(currency.symbol, style: const TextStyle(fontSize: 20)),
                                  const SizedBox(width: 12),
                                  Text('${currency.code} - ${currency.name}'),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedCurrency = value);
                            }
                          },
                        ),

                        const SizedBox(height: 28),

                        // Sign Up Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _register,
                            child: const Text('Sign up', style: TextStyle(fontSize: 18)),
                          ),
                        ),

                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Already have an account? Login', style: TextStyle(color: Colors.deepPurple)),
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