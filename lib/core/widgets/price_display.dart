import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';

/// Reusable widget for displaying prices with automatic currency conversion
class PriceDisplay extends StatelessWidget {
  final double amountUSD; // Amount stored in USD (base currency)
  final TextStyle? style;
  final bool showCurrencySymbol;
  final int? decimalDigits;
  final Color? positiveColor;
  final Color? negativeColor;
  final bool formatNegative;

  const PriceDisplay({
    super.key,
    required this.amountUSD,
    this.style,
    this.showCurrencySymbol = true,
    this.decimalDigits,
    this.positiveColor,
    this.negativeColor,
    this.formatNegative = true,
  });

  @override
  Widget build(BuildContext context) {
    final currencyProvider = context.watch<CurrencyProvider>();
    
    // Convert from USD to current currency
    final convertedAmount = currencyProvider.convertFromUSD(amountUSD);
    
    // Format the amount
    String displayText;
    if (showCurrencySymbol) {
      displayText = currencyProvider.format(convertedAmount);
    } else {
      // Format without symbol
      final currency = currencyProvider.currentCurrency;
      if (currency.code == 'HUF') {
        displayText = convertedAmount.toStringAsFixed(0);
      } else {
        displayText = convertedAmount.toStringAsFixed(
          decimalDigits ?? currency.decimalDigits
        );
      }
    }
    
    // Handle negative amounts
    final isNegative = amountUSD < 0;
    if (isNegative && formatNegative) {
      displayText = '-$displayText';
    }
    
    // Determine text color
    final defaultStyle = Theme.of(context).textTheme.bodyLarge;
    Color textColor = style?.color ?? defaultStyle?.color ?? Colors.black;
    
    if (isNegative && negativeColor != null) {
      textColor = negativeColor!;
    } else if (!isNegative && positiveColor != null) {
      textColor = positiveColor!;
    } else if (isNegative) {
      textColor = Colors.red;
    }
    
    // Create the text style
    final textStyle = (style ?? defaultStyle ?? const TextStyle()).copyWith(
      color: textColor,
    );
    
    return Text(
      displayText,
      style: textStyle,
    );
  }
}

/// Widget for displaying a price with a label
class LabeledPriceDisplay extends StatelessWidget {
  final String label;
  final double amountUSD;
  final TextStyle? labelStyle;
  final TextStyle? priceStyle;
  final bool showCurrencySymbol;
  final CrossAxisAlignment alignment;

  const LabeledPriceDisplay({
    super.key,
    required this.label,
    required this.amountUSD,
    this.labelStyle,
    this.priceStyle,
    this.showCurrencySymbol = true,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: labelStyle ?? Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        PriceDisplay(
          amountUSD: amountUSD,
          style: priceStyle ?? Theme.of(context).textTheme.titleMedium,
          showCurrencySymbol: showCurrencySymbol,
        ),
      ],
    );
  }
}

/// Widget for displaying a price change (positive/negative)
class PriceChangeDisplay extends StatelessWidget {
  final double amountUSD;
  final bool showPercentage;
  final TextStyle? style;

  const PriceChangeDisplay({
    super.key,
    required this.amountUSD,
    this.showPercentage = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = amountUSD < 0;
    final icon = isNegative ? Icons.arrow_downward : Icons.arrow_upward;
    final iconColor = isNegative ? Colors.red : Colors.green;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 4),
        PriceDisplay(
          amountUSD: amountUSD.abs(),
          style: style,
          negativeColor: Colors.red,
          positiveColor: Colors.green,
          formatNegative: false,
        ),
      ],
    );
  }
}