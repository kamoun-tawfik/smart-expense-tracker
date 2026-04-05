import 'package:flutter/foundation.dart';
import '../constants/currencies.dart';

/// Provider for managing currency state across the app
class CurrencyProvider extends ChangeNotifier {
  CurrencyData _currentCurrency = CurrencyConstants.getCurrency('USD');
  bool _isLoading = false;

  CurrencyData get currentCurrency => _currentCurrency;
  bool get isLoading => _isLoading;

  // Store currency preference in Hive (usersBox)
  Future<void> loadCurrency(String? userEmail) async {
    _isLoading = true;
    notifyListeners();

    try {
      String? savedCurrency;
      
      // Check if userEmail is not null and not empty
      final hasUserEmail = userEmail != null && userEmail.isNotEmpty;
      
      if (hasUserEmail) {
        // Try to load from user's data in Hive
        // Note: We'll need to pass usersBox from main.dart or create a service
        // For now, we'll implement this when we have access to usersBox
        
        // Example implementation (commented out until we can access usersBox):
        // final dynamic userData = usersBox.get(userEmail);
        // if (userData != null && userData is Map) {
        //   savedCurrency = userData['currency']?.toString();
        // }
      }
      
      // If we found a saved currency, use it; otherwise use default
      // ignore: unnecessary_null_comparison
      if (savedCurrency != null && CurrencyConstants.currencies.containsKey(savedCurrency)) {
        _currentCurrency = CurrencyConstants.getCurrency(savedCurrency);
        if (kDebugMode) {
          print('Loaded currency from storage: $savedCurrency');
        }
      } else {
        _currentCurrency = CurrencyConstants.getCurrency('USD');
        if (kDebugMode) {
          print('Using default currency: USD');
        }
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('Error loading currency: $e');
      }
      _currentCurrency = CurrencyConstants.getCurrency('USD');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Change the current currency
  Future<void> setCurrency(String currencyCode) async {
    if (_currentCurrency.code == currencyCode) return;
    
    final newCurrency = CurrencyConstants.getCurrency(currencyCode);
    _currentCurrency = newCurrency;
    
    notifyListeners();
  }

  /// Convert amount from USD to current currency
  double convertFromUSD(double amountUSD) {
    return CurrencyConstants.convertFromUSD(amountUSD, _currentCurrency.code);
  }

  /// Convert amount to USD from current currency
  double convertToUSD(double amount) {
    return CurrencyConstants.convertToUSD(amount, _currentCurrency.code);
  }

  /// Convert amount between currencies
  double convertAmount(double amount, String fromCurrency, String toCurrency) {
    final amountUSD = CurrencyConstants.convertToUSD(amount, fromCurrency);
    return CurrencyConstants.convertFromUSD(amountUSD, toCurrency);
  }

  /// Format amount in current currency
  String format(double amount) {
    return CurrencyConstants.format(amount, _currentCurrency.code);
  }

  /// Format an amount that's stored in USD
  String formatFromUSD(double amountUSD) {
    final convertedAmount = convertFromUSD(amountUSD);
    return format(convertedAmount);
  }
}