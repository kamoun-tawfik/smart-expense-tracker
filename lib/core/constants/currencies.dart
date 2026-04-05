class CurrencyConstants {
  static const Map<String, CurrencyData> currencies = {
    'EUR': CurrencyData(
      code: 'EUR',
      name: 'Euro',
      symbol: '€',
      exchangeRateToUSD: 0.85, // 1 EUR = 0.85 USD
      decimalDigits: 2,
    ),
    'USD': CurrencyData(
      code: 'USD',
      name: 'US Dollar',
      symbol: '\$',
      exchangeRateToUSD: 1.0, // 1 USD = 1 USD
      decimalDigits: 2,
    ),
    'HUF': CurrencyData(
      code: 'HUF',
      name: 'Hungarian Forint',
      symbol: 'Ft',
      exchangeRateToUSD: 300.0, // 1 USD = 300 HUF
      decimalDigits: 0, // HUF typically doesn't use decimals
    ),
  };

  // Default currency
  static const String defaultCurrency = 'USD';

  // Get currency data by code
  static CurrencyData getCurrency(String code) {
    return currencies[code] ?? currencies[defaultCurrency]!;
  }

  // Get all currency codes
  static List<String> get currencyCodes => currencies.keys.toList();

  // Convert amount from USD to target currency
  static double convertFromUSD(double amountUSD, String targetCurrencyCode) {
    final targetCurrency = getCurrency(targetCurrencyCode);
    return amountUSD * targetCurrency.exchangeRateToUSD;
  }

  // Convert amount to USD from source currency
  static double convertToUSD(double amount, String sourceCurrencyCode) {
    final sourceCurrency = getCurrency(sourceCurrencyCode);
    return amount / sourceCurrency.exchangeRateToUSD;
  }

  // Format amount with currency symbol
  static String format(double amount, String currencyCode) {
    final currency = getCurrency(currencyCode);
    
    // Special handling for HUF (no decimals)
    if (currencyCode == 'HUF') {
      return '${amount.toStringAsFixed(0)} ${currency.symbol}';
    }
    
    return '${amount.toStringAsFixed(currency.decimalDigits)} ${currency.symbol}';
  }

  // Get exchange rate between two currencies
  static double getExchangeRate(String fromCurrency, String toCurrency) {
    final from = getCurrency(fromCurrency);
    final to = getCurrency(toCurrency);
    return to.exchangeRateToUSD / from.exchangeRateToUSD;
  }
}

/// Data class for currency information
class CurrencyData {
  final String code;
  final String name;
  final String symbol;
  final double exchangeRateToUSD; // How many USD equals 1 unit of this currency
  final int decimalDigits;

  const CurrencyData({
    required this.code,
    required this.name,
    required this.symbol,
    required this.exchangeRateToUSD,
    required this.decimalDigits,
  });

  @override
  String toString() => '$code ($symbol)';
}