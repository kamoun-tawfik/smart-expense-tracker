import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/currencies.dart';
import '../../../../core/providers/currency_provider.dart';
import '../../../../core/widgets/price_display.dart';
import '../../../../main.dart';
import '../../../ocr/presentation/screens/ocr_screen.dart';
import '../../../auth/presentation/screens/profile_screen.dart';
import '../../../analytics/presentation/screens/analytics_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;

  // StreamSubscription to listen for database changes
  StreamSubscription? _dbChangesSubscription;

  @override
  void initState() {
    super.initState();
    _ensureBoxAndLoad();
    _setupDatabaseListener(); // Set up the listener
  }

  // Method to set up a listener for any changes in the Hive box
  void _setupDatabaseListener() {
    try {
      final box = transactionsBox; // Use global transactionsBox
      _dbChangesSubscription = box.watch().listen((event) {
        String eventType;
        if (event.deleted) {
          eventType = 'Deleted';
        } else {
          eventType = 'Added/Updated';
        }
        print('📊 Database changed: Key ${event.key}, Event: $eventType');
        _loadTransactions();
      });
    } catch (e) {
      print('Error setting up database listener: $e');
    }
  }

  @override
  void dispose() {
    // Important! Cancel the subscription when the widget is removed
    _dbChangesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _ensureBoxAndLoad() async {
    try {
      if (!Hive.isBoxOpen('transactions')) {
        await Hive.openBox('transactions');
      }
      _loadTransactions();
    } catch (e) {
      print('Error opening transactions box: $e');
      setState(() => _loading = false);
    }
  }

  void _loadTransactions() {
    try {
      final box = transactionsBox; // Use global transactionsBox
      final List<Map<String, dynamic>> items = [];

      for (var i = 0; i < box.length; i++) {
        final key = box.keyAt(i);
        final val = box.getAt(i);
        if (val is Map) {
          final item = Map<String, dynamic>.from(val);
          item['_key'] = key;
          items.add(item);
        }
      }

      items.sort((a, b) {
        final da = _toDateTime(a['date']);
        final db = _toDateTime(b['date']);
        return db.compareTo(da);
      });

      if (mounted) {
        setState(() {
          _transactions = items;
          _loading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading transactions: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Helper to safely convert various date formats to DateTime
  DateTime _toDateTime(dynamic value) {
    if (value == null) return DateTime.now(); // Safer fallback
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try {
        if (value.contains('-')) {
          return DateTime.parse(value);
        } else if (value.contains('/')) {
          final parts = value.split('/');
          if (parts.length == 3) {
            final month = int.tryParse(parts[0]) ?? 1;
            final day = int.tryParse(parts[1]) ?? 1;
            final year = int.tryParse(parts[2]) ?? DateTime.now().year;
            return DateTime(year, month, day);
          }
        }
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now(); // Safer fallback
      }
    }
    return DateTime.now(); // Safer fallback
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

  // UPDATED: Calculate total spent this month in USD
  double _totalSpentThisMonthUSD() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(
      now.year,
      now.month + 1,
      1,
    ).subtract(const Duration(milliseconds: 1));
    double totalUSD = 0.0;

    for (final t in _transactions) {
      final dt = _toDateTime(t['date']);
      if (!dt.isBefore(start) && !dt.isAfter(end)) {
        final amountUSD = _getAmountUSD(t);
        totalUSD += amountUSD;
      }
    }
    return totalUSD;
  }

  List<Map<String, dynamic>> _recentTransactions([int limit = 5]) {
    return _transactions.take(limit).toList();
  }

  // Helper to capitalize the first letter of each word for consistent display
  String capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map(
          (word) =>
              word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
  }

  // Delete transaction with confirmation
  Future<void> _deleteTransaction(int index) async {
    final transaction = _transactions[index];
    final key = transaction['_key'];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text(
                'Delete Transaction',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this transaction?',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction['title'] ?? 'Expense',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // UPDATED: Use PriceDisplay widget
                    Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, child) {
                        final amountUSD = _getAmountUSD(transaction);
                        final convertedAmount = currencyProvider.convertFromUSD(amountUSD);
                        final displayText = currencyProvider.format(convertedAmount);
                        return Text(
                          displayText,
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final box = transactionsBox;
                  await box.delete(key);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Transaction deleted successfully'),
                          ],
                        ),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error deleting transaction: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // UPDATED: Update transaction with currency support
  Future<void> _updateTransaction(int index) async {
    final transaction = _transactions[index];
    final key = transaction['_key'];

    final titleController = TextEditingController(
      text: transaction['title'] ?? '',
    );
    final amountController = TextEditingController(
      text: transaction['originalAmount']?.toString() ?? 
            transaction['amount']?.toString() ?? '',
    );
    final categoryController = TextEditingController(
      text: transaction['category'] ?? '',
    );
    final dateController = TextEditingController(
      text:
          transaction['date'] != null
              ? _formatDate(_toDateTime(transaction['date']))
              : '',
    );
    
    // Get currency from transaction or default to current currency
    final currencyProvider = context.read<CurrencyProvider>();
    String selectedCurrency = transaction['currencyCode']?.toString() ?? 
                             currencyProvider.currentCurrency.code;
    final currencyController = TextEditingController();

    void updateCurrencyDisplay() {
      final currency = CurrencyConstants.getCurrency(selectedCurrency);
      currencyController.text = '${currency.code} (${currency.symbol})';
    }
    
    updateCurrencyDisplay();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: Colors.deepPurple, size: 28),
              SizedBox(width: 12),
              Text(
                'Update Transaction',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    prefixIcon: const Icon(
                      Icons.note,
                      color: Colors.deepPurple,
                    ),
                    filled: true,
                    fillColor: Colors.deepPurple.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.deepPurple,
                        width: 2,
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 12),
                
                // Amount with Currency Selection
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: amountController,
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: const Icon(
                            Icons.attach_money,
                            color: Colors.deepPurple,
                          ),
                          filled: true,
                          fillColor: Colors.deepPurple.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.deepPurple.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.deepPurple.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Colors.deepPurple,
                              width: 2,
                            ),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Currency Selection
                    SizedBox(
                      width: 120,
                      child: GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black,
                                    blurRadius: 12,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 12),
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[400],
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Select Currency',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.deepPurple[700],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () => Navigator.pop(ctx),
                                          color: Colors.grey[600],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(height: 1, color: Colors.grey[300]),
                                  Container(
                                    constraints: BoxConstraints(
                                      minHeight: 60.0 * CurrencyConstants.currencyCodes.length,
                                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                                    ),
                                    child: ListView(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      children: CurrencyConstants.currencyCodes.map((currencyCode) {
                                        final currency = CurrencyConstants.getCurrency(currencyCode);
                                        return Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                selectedCurrency = currencyCode;
                                                updateCurrencyDisplay();
                                              });
                                              Navigator.pop(ctx);
                                            },
                                            borderRadius: BorderRadius.circular(12),
                                            child: Container(
                                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 18,
                                              ),
                                              decoration: BoxDecoration(
                                                color: selectedCurrency == currencyCode
                                                    ? Colors.deepPurple[50]
                                                    : Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: selectedCurrency == currencyCode
                                                      ? Colors.deepPurple
                                                      : Colors.transparent,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        currency.code,
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: selectedCurrency == currencyCode
                                                              ? FontWeight.bold
                                                              : FontWeight.normal,
                                                          color: selectedCurrency == currencyCode
                                                              ? Colors.deepPurple[700]
                                                              : Colors.black87,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        currency.symbol,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color: Colors.grey[600],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (selectedCurrency == currencyCode)
                                                    Icon(
                                                      Icons.check_circle,
                                                      color: Colors.deepPurple,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          );
                        },
                        child: TextField(
                          controller: currencyController,
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: 'Currency',
                            filled: true,
                            fillColor: Colors.deepPurple[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                          ),
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    prefixIcon: const Icon(
                      Icons.category,
                      color: Colors.deepPurple,
                    ),
                    filled: true,
                    fillColor: Colors.deepPurple.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.deepPurple,
                        width: 2,
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateController,
                  decoration: InputDecoration(
                    labelText: 'Date (MM/DD/YYYY)',
                    prefixIcon: const Icon(
                      Icons.calendar_today,
                      color: Colors.deepPurple,
                    ),
                    filled: true,
                    fillColor: Colors.deepPurple.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.deepPurple,
                        width: 2,
                      ),
                    ),
                  ),
                  keyboardType: TextInputType.datetime,
                  readOnly: true,
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _toDateTime(transaction['date']),
                      firstDate: DateTime(now.year - 10),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (picked != null) {
                      dateController.text = _formatDate(picked);
                    }
                  },
                ),
              ],
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
                if (titleController.text.isEmpty || amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Please fill all required fields with valid values'),
                        ],
                      ),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                  return;
                }

                // Convert amount to USD for storage
                final amountUSD = CurrencyConstants.convertToUSD(amount, selectedCurrency);
                
                final updatedData = {
                  'title': titleController.text,
                  'amountUSD': amountUSD,
                  'originalAmount': amount,
                  'currencyCode': selectedCurrency,
                  'category': categoryController.text.toLowerCase().trim(),
                  'date': dateController.text,
                  'createdAt': DateTime.now().toIso8601String(),
                  if (transaction.containsKey('imagePath'))
                    'imagePath': transaction['imagePath'],
                  if (transaction.containsKey('meta'))
                    'meta': transaction['meta'],
                };

                try {
                  final box = transactionsBox;
                  await box.put(key, updatedData);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Transaction updated successfully'),
                          ],
                        ),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating transaction: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalUSD = _totalSpentThisMonthUSD();
    final recent = _recentTransactions();

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
          child:
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _navigateToProfile,
                                  icon: const Icon(Icons.person, size: 32),
                                  color: Colors.white,
                                  tooltip: 'Profile',
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _navigateToProfile,
                                  child: const Text(
                                    'Profile',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                // Show current currency
                                Consumer<CurrencyProvider>(
                                  builder: (context, currencyProvider, child) {
                                    final currency = currencyProvider.currentCurrency;
                                    return Chip(
                                      label: Text('${currency.code} (${currency.symbol})'),
                                      backgroundColor: Colors.white70,
                                      side: BorderSide.none,
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            Card(
                              elevation: 12,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                  horizontal: 20,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 30,
                                          backgroundColor:
                                              Colors.deepPurple[100],
                                          child: const Icon(
                                            Icons.pie_chart,
                                            color: Colors.deepPurple,
                                            size: 32,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Overview',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Quick summary of your finances',
                                                style: TextStyle(
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          onPressed: () async {
                                            await Navigator.pushNamed(
                                              context,
                                              '/add-expense',
                                            );
                                          },
                                          icon: const Icon(Icons.add),
                                          label: const Text('Add Expense'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap:
                                                () => Navigator.pushNamed(
                                                  context,
                                                  '/expenses',
                                                ),
                                            child: _SummaryCard(
                                              color: Colors.deepPurple,
                                              title: 'Spent this month',
                                              // UPDATED: Use PriceDisplay widget
                                              valueWidget: PriceDisplay(
                                                amountUSD: totalUSD,
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              icon:
                                                  Icons.account_balance_wallet,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Card(
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Recent Transactions',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (recent.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 20,
                                        ),
                                        child: Center(
                                          child: Column(
                                            children: const [
                                              Icon(
                                                Icons.inbox,
                                                size: 48,
                                                color: Colors.grey,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                'No transactions yet',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemBuilder: (context, index) {
                                          final t = recent[index];
                                          final dt = _toDateTime(t['date']);
                                          final title = t['title'] ?? 'Expense';
                                          // Use lowercase for icon lookup and formatted for display
                                          final category =
                                              (t['category'] ?? 'Uncategorized')
                                                  .toString()
                                                  .toLowerCase();
                                          final amountUSD = _getAmountUSD(t);

                                          return Dismissible(
                                            key: ValueKey(t['_key']),
                                            background: Container(
                                              color: Colors.red,
                                              alignment: Alignment.centerLeft,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                  ),
                                              child: const Icon(
                                                Icons.delete,
                                                color: Colors.white,
                                              ),
                                            ),
                                            secondaryBackground: Container(
                                              color: Colors.blue,
                                              alignment: Alignment.centerRight,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                  ),
                                              child: const Icon(
                                                Icons.edit,
                                                color: Colors.white,
                                              ),
                                            ),
                                            confirmDismiss: (direction) async {
                                              if (direction ==
                                                  DismissDirection.startToEnd) {
                                                _deleteTransaction(index);
                                                return false;
                                              } else if (direction ==
                                                  DismissDirection.endToStart) {
                                                _updateTransaction(index);
                                                return false;
                                              }
                                              return false;
                                            },
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor:
                                                    Colors.deepPurple.shade50,
                                                child: _getCategoryIcon(
                                                  category,
                                                ),
                                              ),
                                              title: Text(title),
                                              // Use formatted category for display
                                              subtitle: Text(
                                                '${capitalizeFirstLetter(category)} • ${_formatDate(dt)}',
                                              ),
                                              // UPDATED: Use PriceDisplay widget
                                              trailing: PriceDisplay(
                                                amountUSD: amountUSD,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                negativeColor: Colors.red,
                                              ),
                                            ),
                                          );
                                        },
                                        separatorBuilder:
                                            (_, __) => const Divider(),
                                        itemCount: recent.length,
                                      ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        // Scan Receipt Button
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(builder: (_) => const OcrScreen()),
                                              );
                                            },
                                            icon: const Icon(Icons.camera_alt_outlined, size: 20),
                                            label: const Text('Scan Receipt'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 12), // Space between buttons

                                        // Analytics Button
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                                            ),
                                            icon: const Icon(Icons.analytics, size: 20),
                                            label: const Text('Analytics'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
        ),
      ),
    );
  }

  Icon _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'groceries':
        return const Icon(Icons.shopping_cart, color: Colors.deepPurple);
      case 'food & drinks':
      case 'food & dining':
        return const Icon(Icons.restaurant, color: Colors.deepPurple);
      case 'transportation':
        return const Icon(Icons.directions_car, color: Colors.deepPurple);
      case 'healthcare':
        return const Icon(Icons.local_hospital, color: Colors.deepPurple);
      case 'entertainment':
        return const Icon(Icons.movie, color: Colors.deepPurple);
      case 'shopping':
        return const Icon(Icons.shopping_bag, color: Colors.deepPurple);
      case 'electronics':
        return const Icon(Icons.devices, color: Colors.deepPurple);
      default:
        return const Icon(Icons.receipt, color: Colors.deepPurple);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

// UPDATED: _SummaryCard to accept valueWidget instead of value
class _SummaryCard extends StatelessWidget {
  final Color color;
  final String title;
  final Widget valueWidget; // Changed from String to Widget
  final IconData icon;

  const _SummaryCard({
    required this.color,
    required this.title,
    required this.valueWidget, // Changed parameter
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white70,
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  // Use the valueWidget instead of Text
                  valueWidget,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}