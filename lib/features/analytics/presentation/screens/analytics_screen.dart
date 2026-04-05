import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; 
import '../../../../core/constants/currencies.dart';
import '../../../../core/providers/currency_provider.dart';
import '../../../../core/widgets/price_display.dart';
import '../../../../main.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Map<String, dynamic>> _allTransactions = [];
  bool _isLoading = true;

  DateTime _selectedMonth = DateTime.now();
  double _monthlyBudget = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!Hive.isBoxOpen('transactions')) await Hive.openBox('transactions');
    if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');

    final box = transactionsBox; 
    final settingsBox = Hive.box('settings');

    final List<Map<String, dynamic>> loaded = [];
    for (var i = 0; i < box.length; i++) {
      final val = box.getAt(i);
      if (val is Map) loaded.add(Map<String, dynamic>.from(val));
    }

    setState(() {
      _allTransactions = loaded;
      _monthlyBudget = settingsBox.get('monthly_budget', defaultValue: 0.0);
      _isLoading = false;
    });
  }

  DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try {
        if (value.contains('/')) {
          final parts = value.split('/');
          if (parts.length == 3) {
            final month = int.tryParse(parts[0]) ?? 1;
            final day = int.tryParse(parts[1]) ?? 1;
            final year = int.tryParse(parts[2]) ?? DateTime.now().year;
            return DateTime(year, month, day);
          }
        }
        return DateTime.parse(value);
      } catch (_) {}
    }
    return DateTime.now();
  }

  // UPDATED: Get amount in USD for calculations
  double _getAmountUSD(Map<String, dynamic> transaction) {
    // First try to get amountUSD (new format)
    final amountUSD = transaction['amountUSD'];
    if (amountUSD != null && amountUSD is double) {
      return amountUSD;
    }
    
    // Fallback to old format (amount in original currency)
    final amount = (transaction['amount'] is num)
        ? (transaction['amount'] as num).toDouble()
        : double.tryParse('${transaction['amount']}') ?? 0.0;
    final currencyCode = transaction['currencyCode']?.toString() ?? 'USD';
    
    // Convert to USD if needed
    return CurrencyConstants.convertToUSD(amount, currencyCode);
  }

  // UPDATED: Get amount for display in current currency
  double _getAmountForDisplay(Map<String, dynamic> transaction, CurrencyProvider currencyProvider) {
    final amountUSD = _getAmountUSD(transaction);
    return currencyProvider.convertFromUSD(amountUSD);
  }

  double get totalForSelectedMonthUSD {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
    double totalUSD = 0.0;
    for (final t in _allTransactions) {
      final date = _toDateTime(t['date']);
      if (date.isAfter(start.subtract(const Duration(seconds: 1))) &&
          date.isBefore(end.add(const Duration(seconds: 1)))) {
        totalUSD += _getAmountUSD(t);
      }
    }
    return totalUSD;
  }

  // UPDATED: Daily bars with currency conversion
  List<BarChartGroupData> getDailyBars(CurrencyProvider currencyProvider) {
    final Map<int, double> dailyUSD = {};
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    for (int i = 1; i <= daysInMonth; i++) 
    {dailyUSD[i] = 0.0;}

    for (final t in _allTransactions) {
      final date = _toDateTime(t['date']);
      if (date.year == year && date.month == month) {
        dailyUSD[date.day] = dailyUSD[date.day]! + _getAmountUSD(t);
      }
    }

    // Convert USD to current currency for display
    final Map<int, double> dailyDisplay = {};
    dailyUSD.forEach((day, amountUSD) {
      dailyDisplay[day] = currencyProvider.convertFromUSD(amountUSD);
    });

    final maxValue = dailyDisplay.values.fold(0.0, (a, b) => a > b ? a : b);
    return dailyDisplay.entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value,
            color: const Color(0xFF86A8E7),
            width: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxValue == 0 ? 1000 : maxValue * 1.3,
              color: Colors.grey.shade100,
            ),
          ),
        ],
      );
    }).toList();
  }

  // UPDATED: Get breakdown in current currency
  Map<String, double> _getBreakdown(CurrencyProvider currencyProvider) {
    final map = <String, double>{};
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

    for (final t in _allTransactions) {
      final date = _toDateTime(t['date']);
      if (date.isAfter(start.subtract(const Duration(seconds: 1))) &&
          date.isBefore(end.add(const Duration(seconds: 1)))) {
        final key = (t['category']?.toString() ?? 'uncategorized');
        final amountForDisplay = _getAmountForDisplay(t, currencyProvider);
        map[key] = (map[key] ?? 0) + amountForDisplay;
      }
    }
    return map;
  }

  void _previousMonth() => setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1));
  void _nextMonth() {
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    if (next.isBefore(DateTime.now().add(const Duration(days: 30)))) {
      setState(() => _selectedMonth = next);
    }
  }

  Future<void> _setOrEditBudget() async {
    final currencyProvider = context.read<CurrencyProvider>();
    final currentCurrency = currencyProvider.currentCurrency;
    
    // Convert budget to display currency for editing
    final budgetInDisplayCurrency = _monthlyBudget > 0 
        ? currencyProvider.convertFromUSD(_monthlyBudget)
        : 0;
        
    final controller = TextEditingController(
      text: _monthlyBudget > 0 ? budgetInDisplayCurrency.toStringAsFixed(0) : ''
    );
    
    final result = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Monthly Budget", style: TextStyle(color: Colors.deepPurple)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "Enter amount (${currentCurrency.symbol})",
                filled: true,
                fillColor: Colors.deepPurple.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Budget will be stored in USD for accurate calculations across all currencies",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () {
              final amountText = controller.text.trim();
              if (amountText.isEmpty) return Navigator.pop(context, 0.0);
              
              final amount = double.tryParse(amountText.replaceAll(',', '.')) ?? 0.0;
              if (amount <= 0) return Navigator.pop(context, 0.0);
              
              // Convert entered amount to USD for storage
              final amountUSD = currencyProvider.convertToUSD(amount);
              Navigator.pop(context, amountUSD);
            },
            child: const Text("Save", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result >= 0) {
      await Hive.box('settings').put('monthly_budget', result);
      setState(() => _monthlyBudget = result);

      // Reset alert flag when budget changes
      final key = 'budget_alert_shown_${_selectedMonth.year}_${_selectedMonth.month}';
      if (Hive.box('settings').containsKey(key)) {
        await Hive.box('settings').delete(key);
      }
    }
  }

  void _checkAndShowBudgetAlert(double totalUSD, double budgetUSD, CurrencyProvider currencyProvider) {
    if (budgetUSD <= 0 || totalUSD <= budgetUSD) return;

    final alertKey = 'budget_alert_shown_${_selectedMonth.year}_${_selectedMonth.month}';
    final alreadyShown = Hive.box('settings').get(alertKey, defaultValue: false);

    if (!alreadyShown) {
      Hive.box('settings').put(alertKey, true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final totalDisplay = currencyProvider.convertFromUSD(totalUSD);
        final budgetDisplay = currencyProvider.convertFromUSD(budgetUSD);
        final overspentDisplay = totalDisplay - budgetDisplay;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
                SizedBox(width: 2),
                Text("Budget Exceeded!", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "You've spent ${currencyProvider.format(totalDisplay)} this month.\nThat's over your budget of ${currencyProvider.format(budgetDisplay)}!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Text(
                  "Overspent by ${currencyProvider.format(overspentDisplay)}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 20),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK", style: TextStyle(color: Colors.deepPurple)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Navigator.pop(context);
                  _setOrEditBudget();
                },
                child: const Text("Edit Budget", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalUSD = totalForSelectedMonthUSD;

    return Consumer<CurrencyProvider>(
      builder: (context, currencyProvider, child) {
        // Show alert after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndShowBudgetAlert(totalUSD, _monthlyBudget, currencyProvider);
        });

        final dailyBars = getDailyBars(currencyProvider);
        final maxY = dailyBars.isEmpty
            ? 1000.0
            : dailyBars.map((e) => e.barRods[0].toY).fold(0.0, (a, b) => a > b ? a : b) * 1.3;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7F7FD5), Color(0xFF86A8E7), Color(0xFF91EAE4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Header
                          Card(
                            elevation: 12,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              child: Row(
                                children: [
                                  // Back Button
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.deepPurple),
                                    onPressed: () => Navigator.pop(context),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 15),

                                  // Analytics Icon + Title
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.deepPurple.shade100,
                                    child: const Icon(Icons.bar_chart_rounded, color: Colors.deepPurple, size: 35),
                                  ),
                                  const SizedBox(width: 16),
                                  const Expanded(
                                    child: Text(
                                      'Analytics',
                                      style: TextStyle(
                                        fontSize: 25,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 8),
                                  // Current currency indicator
                                  Chip(
                                    label: Text('${currencyProvider.currentCurrency.code} (${currencyProvider.currentCurrency.symbol})'),
                                    backgroundColor: Colors.deepPurple[50],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Main Card
                          Card(
                            elevation: 12,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Total spending this month', style: TextStyle(color: Colors.grey, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  // UPDATED: Use PriceDisplay widget
                                  PriceDisplay(
                                    amountUSD: totalUSD,
                                    style: TextStyle(
                                      fontSize: 38,
                                      fontWeight: FontWeight.bold,
                                      color: totalUSD > _monthlyBudget && _monthlyBudget > 0 ? Colors.red : Colors.deepPurple,
                                    ),
                                  ),

                                  // Budget Line — FULLY CLICKABLE
                                  if (_monthlyBudget > 0)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: _setOrEditBudget,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                        child: Row(
                                          children: [
                                            // Warning icon if overspent
                                            if (totalUSD > _monthlyBudget)
                                              const Padding(
                                                padding: EdgeInsets.only(right: 10),
                                                child: Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                                              ),

                                            // Budget text
                                            Expanded(
                                              child: Text(
                                                'Budget: ${currencyProvider.format(currencyProvider.convertFromUSD(_monthlyBudget))}',
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w600,
                                                  color: totalUSD > _monthlyBudget ? Colors.red : Colors.black87,
                                                  decoration: totalUSD > _monthlyBudget ? TextDecoration.none : TextDecoration.underline,
                                                  decorationColor: Colors.deepPurple,
                                                ),
                                              ),
                                            ),

                                            // Overspent amount (if any)
                                            if (totalUSD > _monthlyBudget)
                                              Text(
                                                '(−${currencyProvider.format(currencyProvider.convertFromUSD(totalUSD - _monthlyBudget))})',
                                                style: const TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),

                                            const SizedBox(width: 40),

                                            // Reset Button (small delete icon)
                                            GestureDetector(
                                              onTap: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                    title: const Text("Remove Budget?"),
                                                    content: const Text("Your monthly budget will be deleted."),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(ctx, true),
                                                        child: const Text("Remove", style: TextStyle(color: Colors.red)),
                                                      ),
                                                    ],
                                                  ),
                                                );

                                                if (confirm == true) {
                                                  await Hive.box('settings').delete('monthly_budget');
                                                  final alertKey = 'budget_alert_shown_${_selectedMonth.year}_${_selectedMonth.month}';
                                                  if (Hive.box('settings').containsKey(alertKey)) {
                                                    await Hive.box('settings').delete(alertKey);
                                                  }
                                                  setState(() => _monthlyBudget = 0.0);
                                                }
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close_rounded,
                                                  color: Colors.red,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    TextButton.icon(
                                      onPressed: _setOrEditBudget,
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text("Set up a budget"),
                                      style: TextButton.styleFrom(foregroundColor: Colors.black),
                                    ),

                                  const SizedBox(height: 15),

                                  // Chart
                                  SizedBox(
                                    height: 220,
                                    child: totalUSD == 0
                                        ? const Center(child: Text("No expenses this month", style: TextStyle(color: Colors.grey)))
                                        : BarChart(
                                            BarChartData(
                                              alignment: BarChartAlignment.spaceAround,
                                              maxY: maxY > 0 ? maxY : 1000,
                                              titlesData: FlTitlesData(
                                                bottomTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: 30,
                                                    getTitlesWidget: (value, meta) {
                                                      final day = value.toInt();
                                                      if (day % 7 == 1 || [1, 8, 15, 22, 29].contains(day)) {
                                                        return Padding(
                                                          padding: const EdgeInsets.only(top: 8),
                                                          child: Text('$day', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                                        );
                                                      }
                                                      return const SizedBox();
                                                    },
                                                  ),
                                                ),
                                                leftTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: 40,
                                                    getTitlesWidget: (value, meta) {
                                                      if (value == 0) return const Text('0');
                                                      // Format Y-axis labels based on currency
                                                      if (currencyProvider.currentCurrency.code == 'HUF') {
                                                        // For HUF, show full numbers (no 'k' suffix)
                                                        return Text('${value.toInt()}',
                                                            style: const TextStyle(color: Colors.grey, fontSize: 11));
                                                      } else {
                                                        // For EUR/USD, use 'k' suffix for thousands
                                                        return Text('${(value / 1000).toStringAsFixed(0)}k',
                                                            style: const TextStyle(color: Colors.grey, fontSize: 11));
                                                      }
                                                    },
                                                  ),
                                                ),
                                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                              ),
                                              gridData: FlGridData(
                                                show: true,
                                                drawVerticalLine: false,
                                                horizontalInterval: maxY / 5,
                                                getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                                              ),
                                              borderData: FlBorderData(show: false),
                                              barGroups: dailyBars,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Month Selector
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(onPressed: _previousMonth, icon: const Icon(Icons.chevron_left, color: Colors.deepPurple)),
                                        Text(
                                          DateFormat('MMMM yyyy').format(_selectedMonth),
                                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.deepPurple),
                                        ),
                                        IconButton(
                                          onPressed: _nextMonth,
                                          icon: Icon(Icons.chevron_right,
                                              color: _selectedMonth.month == DateTime.now().month && _selectedMonth.year == DateTime.now().year
                                                  ? Colors.grey.shade400
                                                  : Colors.deepPurple),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Categories Card
                          Card(
                            elevation: 12,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                            child: Column(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                                  ),
                                ),
                                SizedBox(
                                  height: 300,
                                  child: _buildBreakdownList(_getBreakdown(currencyProvider), currencyProvider),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreakdownList(Map<String, double> data, CurrencyProvider currencyProvider) {
    if (data.isEmpty) {
      return const Center(child: Text("No expenses this month", style: TextStyle(fontSize: 16, color: Colors.grey)));
    }

    final sorted = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalAll = data.values.fold(0.0, (a, b) => a + b);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final e = sorted[i];
        final percent = totalAll > 0 ? (e.value / totalAll) * 100 : 0.0;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.shade50,
              radius: 22,
              child: Icon(
                e.key.toLowerCase().contains('travel')
                    ? Icons.flight
                    : e.key.toLowerCase().contains('food') || e.key.toLowerCase().contains('drink')
                        ? Icons.restaurant
                        : Icons.category,
                color: Colors.deepPurple,
              ),
            ),
            title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${percent.toStringAsFixed(1)}% of total', style: const TextStyle(fontSize: 13)),
            trailing: Text(
              currencyProvider.format(e.value),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
            ),
          ),
        );
      },
    );
  }
}
