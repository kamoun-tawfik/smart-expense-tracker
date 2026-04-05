import 'dart:math';
import '../constants/currencies.dart';

/// Utility functions for currency operations
class CurrencyUtils {
  /// Parse amount from string with currency detection
  static double? parseAmount(String text, {String? currencyHint}) {
    try {
      // Remove all non-numeric characters except decimal point and minus
      final cleanedText = text
          .replaceAll(RegExp(r'[^\d\.\-]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      
      // Find numbers in the text
      final numberMatches = RegExp(r'-?\d+(\.\d+)?').allMatches(cleanedText);
      
      if (numberMatches.isEmpty) return null;
      
      // If we have a currency hint, try to match patterns
      if (currencyHint != null) {
        final currency = CurrencyConstants.getCurrency(currencyHint);
        final symbolPattern = RegExp(RegExp.escape(currency.symbol), caseSensitive: false);
        
        if (symbolPattern.hasMatch(text)) {
          // Find amount near the currency symbol
          final lines = text.split('\n');
          for (final line in lines) {
            if (line.contains(symbolPattern)) {
              final numbersInLine = RegExp(r'-?\d+(\.\d+)?').allMatches(line);
              if (numbersInLine.isNotEmpty) {
                return double.tryParse(numbersInLine.first.group(0)!);
              }
            }
          }
        }
      }
      
      // Return the largest number (often the total)
      double? largest;
      for (final match in numberMatches) {
        final value = double.tryParse(match.group(0)!);
        if (value != null && (largest == null || value > largest)) {
          largest = value;
        }
      }
      
      return largest;
    } catch (e) {
      return null;
    }
  }

  /// Detect currency from text (receipt OCR)
  static String? detectCurrencyFromText(String text) {
    final textUpper = text.toUpperCase();
    
    // Check for currency symbols
    if (text.contains('€') || textUpper.contains('EUR')) return 'EUR';
    if (text.contains('\$') || textUpper.contains('USD') || textUpper.contains('US\$')) return 'USD';
    if (text.contains('Ft') || textUpper.contains('HUF') || textUpper.contains('FORINT')) return 'HUF';
    
    // Check for common patterns
    if (textUpper.contains('EURO')) return 'EUR';
    if (textUpper.contains('DOLLAR')) return 'USD';
    
    return null;
  }

  /// Round amount based on currency decimal rules
  static double roundForCurrency(double amount, String currencyCode) {
    final currency = CurrencyConstants.getCurrency(currencyCode);
    
    if (currency.decimalDigits == 0) {
      return amount.roundToDouble();
    }
    
    final factor = pow(10, currency.decimalDigits);
    return (amount * factor).roundToDouble() / factor;
  }

  /// Validate currency code
  static bool isValidCurrency(String code) {
    return CurrencyConstants.currencies.containsKey(code.toUpperCase());
  }

  /// Get display text for currency
  static String getCurrencyDisplay(String currencyCode) {
    final currency = CurrencyConstants.getCurrency(currencyCode);
    return '${currency.code} (${currency.symbol})';
  }
}