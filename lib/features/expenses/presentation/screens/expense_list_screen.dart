import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart'; 
import '../../../../main.dart';
import '../../../../core/providers/currency_provider.dart'; 
import '../../../../core/constants/currencies.dart';
import '../../../../core/widgets/price_display.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  // filters
  String _selectedCategory = 'All';
  DateTime? _startDate;
  DateTime? _endDate;

  // search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _ensureBoxAndLoad();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureBoxAndLoad() async {
    if (!Hive.isBoxOpen('transactions')) await Hive.openBox('transactions');
    _load();
  }

  void _load() {
    final box = transactionsBox; // Use the global transactionsBox
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < box.length; i++) {
      final key = box.keyAt(i);
      final val = box.getAt(i);
      if (val is Map) {
        final entry = Map<String, dynamic>.from(val);
        entry['_key'] = key;
        list.add(entry);
      }
    }
    list.sort((a, b) {
      final da = _toDateTime(a['date']);
      final db = _toDateTime(b['date']);
      return db.compareTo(da);
    });
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _openAdd() async {
    await Navigator.pushNamed(context, '/add-expense');
    _load();
  }

  // UPDATED: Get amount in USD for calculations
  double _getAmountUSD(Map<String, dynamic> transaction) {
    // First try to get amountUSD (new format)
    final amountUSD = transaction['amountUSD'];
    if (amountUSD != null && amountUSD is double) {
      return amountUSD;
    }
    
    // Fallback to old format (amount in original currency)
    final amount = double.tryParse('${transaction['amount']}') ?? 0.0;
    final currencyCode = transaction['currencyCode']?.toString() ?? 'USD';
    
    // Convert to USD if needed
    return CurrencyConstants.convertToUSD(amount, currencyCode);
  }

  // UPDATED: Calculate category totals in USD
  Map<String, double> _categoryTotals() {
    final Map<String, double> totals = {};
    for (final t in _items) {
      final cat = (t['category'] ?? 'Uncategorized').toString().toLowerCase();
      final amountUSD = _getAmountUSD(t);
      totals[cat] = (totals[cat] ?? 0.0) + amountUSD;
    }
    return totals;
  }

  // UPDATED: Filter items
  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((t) {
      final cat = (t['category'] ?? 'Uncategorized').toString().toLowerCase();
      if (_selectedCategory.toLowerCase() != 'all' &&
          cat != _selectedCategory.toLowerCase()){
        return false;}
      final dt = _toDateTime(t['date']);
      if (_startDate != null && dt.isBefore(_startDate!)) return false;
      if (_endDate != null && dt.isAfter(_endDate!)) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = '${t['title'] ?? ''}'.toLowerCase();
        final category = cat; // already lowercase
        final amountUSD = _getAmountUSD(t);
        final currencyProvider = context.read<CurrencyProvider>();
        final displayAmount = currencyProvider.convertFromUSD(amountUSD);
        final displayAmountStr = displayAmount.toString().toLowerCase();
        final dateStr = dt.toLocal().toString().toLowerCase();
        return title.contains(q) ||
            category.contains(q) ||
            displayAmountStr.contains(q) ||
            dateStr.contains(q);
      }
      return true;
    }).toList();
  }

  Future<void> _pickDateRange() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose date range',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        final now = DateTime.now();
                        setState(() {
                          _startDate = DateTime(now.year, now.month, now.day);
                          _endDate = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            23,
                            59,
                            59,
                          );
                        });
                        Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                      ),
                      child: const Text('Today'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final now = DateTime.now();
                        setState(() {
                          _startDate = now.subtract(const Duration(days: 6));
                          _endDate = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            23,
                            59,
                            59,
                          );
                        });
                        Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                      ),
                      child: const Text('Last 7 days'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final now = DateTime.now();
                        setState(() {
                          _startDate = DateTime(now.year, now.month, 1);
                          _endDate = DateTime(
                            now.year,
                            now.month + 1,
                            1,
                          ).subtract(const Duration(milliseconds: 1));
                        });
                        Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                      ),
                      child: const Text('This month'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final now = DateTime.now();
                        final first = DateTime(now.year - 2);
                        final last = DateTime(now.year + 1);
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: first,
                          lastDate: last,
                          initialDateRange:
                              _startDate != null && _endDate != null
                                  ? DateTimeRange(
                                    start: _startDate!,
                                    end: _endDate!,
                                  )
                                  : null,
                        );
                        if (picked != null) {
                          setState(() {
                            _startDate = picked.start;
                            _endDate = picked.end;
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                      ),
                      child: const Text('Custom range'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _startDate = null;
                          _endDate = null;
                        });
                        Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                      child: const Text('Clear range'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _clearFilters() async {
    setState(() {
      _selectedCategory = 'All';
      _startDate = null;
      _endDate = null;
      _searchController.clear();
      _showSearch = false;
    });
  }

  String _rangeLabel() {
    if (_startDate == null || _endDate == null) return 'All dates';
    final s =
        '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}';
    final e =
        '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}';
    return '$s → $e';
  }

  // --- HELPER FUNCTIONS ---
  DateTime _toDateTime(dynamic value) {
    if (value == null) return DateTime.now();
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
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  // NEW: Helper function to capitalize the first letter of each word
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

  // --- ACTION METHODS ---
  Future<void> _deleteTransaction(int index) async {
    final transactionToDelete = _filteredItems[index];
    final key = transactionToDelete['_key'];

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
                      transactionToDelete['title'] ?? 'Expense',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // UPDATED: Use PriceDisplay widget
                    Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, child) {
                        final amountUSD = _getAmountUSD(transactionToDelete);
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
              const SizedBox(height: 12),
              Text(
                'This action cannot be undone.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                  Navigator.pop(context);
                  _load();
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
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting transaction: $e')),
                  );
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

  Future<void> _updateTransaction(int index) async {
    final transactionToUpdate = _filteredItems[index];
    final key = transactionToUpdate['_key'];

    final titleController = TextEditingController(
      text: transactionToUpdate['title'] ?? '',
    );
    final amountController = TextEditingController(
      text: transactionToUpdate['originalAmount']?.toString() ?? 
            transactionToUpdate['amount']?.toString() ?? '',
    );
    final categoryController = TextEditingController(
      text: transactionToUpdate['category'] ?? '',
    );
    final dateController = TextEditingController(
      text:
          transactionToUpdate['date'] != null
              ? _formatDate(_toDateTime(transactionToUpdate['date']))
              : '',
    );
    
    // Get currency from transaction or default to current currency
    final currencyProvider = context.read<CurrencyProvider>();
    String selectedCurrency = transactionToUpdate['currencyCode']?.toString() ?? 
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
                      initialDate: _toDateTime(transactionToUpdate['date']),
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
                  if (transactionToUpdate.containsKey('imagePath'))
                    'imagePath': transactionToUpdate['imagePath'],
                };

                try {
                  final box = transactionsBox;
                  await box.put(key, updatedData);
                  Navigator.pop(context);
                  _load();
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
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating transaction: $e')),
                  );
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
    final totals = _categoryTotals();
    final filtered = _filteredItems;

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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  children: [
                    Card(
                      elevation: 12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.pop(context),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: Colors.deepPurple[700],
                            ),
                            const SizedBox(width: 12),
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.deepPurple[100],
                              child: const Icon(
                                Icons.list_alt,
                                color: Colors.deepPurple,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Expenses',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Show current currency
                            Consumer<CurrencyProvider>(
                              builder: (context, currencyProvider, child) {
                                final currency = currencyProvider.currentCurrency;
                                return Chip(
                                  label: Text('${currency.code} (${currency.symbol})'),
                                  backgroundColor: Colors.deepPurple[50],
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Search',
                              icon: Icon(
                                _showSearch ? Icons.close : Icons.search,
                                color: Colors.deepPurple,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showSearch = !_showSearch;
                                  if (!_showSearch) _searchController.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_showSearch)
                      Card(
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search,
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Search by title, category, amount or date',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => _searchController.clear(),
                                ),
                            ],
                          ),
                        ),
                      ),

                    Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Filters',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              alignment: WrapAlignment.start,
                              children: [
                                // UPDATED: Dropdown with formatted display names
                                SizedBox(
                                  width: 160,
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedCategory,
                                    items:
                                        [
                                          'All',
                                          ...totals.keys.map(
                                            (c) => capitalizeFirstLetter(c),
                                          ),
                                        ].toList().map((formattedCat) {
                                          final originalKey =
                                              formattedCat.toLowerCase() ==
                                                      'all'
                                                  ? 'All'
                                                  : totals.keys.firstWhere(
                                                    (k) =>
                                                        capitalizeFirstLetter(
                                                          k,
                                                        ) ==
                                                        formattedCat,
                                                    orElse:
                                                        () =>
                                                            formattedCat
                                                                .toLowerCase(),
                                                  );
                                          return DropdownMenuItem(
                                            value: originalKey,
                                            child: Text(formattedCat),
                                          );
                                        }).toList(),
                                    onChanged:
                                        (v) => setState(
                                          () => _selectedCategory = v ?? 'All',
                                        ),
                                    decoration: InputDecoration(
                                      labelText: 'Category',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.date_range,
                                      color: Colors.deepPurple,
                                    ),
                                    label: Text(
                                      _rangeLabel(),
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                    onPressed: _pickDateRange,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      side: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(
                                    Icons.clear_all,
                                    color: Colors.deepPurple,
                                  ),
                                  label: const Text(
                                    'Clear',
                                    style: TextStyle(color: Colors.deepPurple),
                                  ),
                                ),
                                const SizedBox(width: 100),
                                TextButton.icon(
                                  onPressed: _openAdd,
                                  icon: const Icon(
                                    Icons.add,
                                    color: Colors.deepPurple,
                                  ),
                                  label: const Text(
                                    'Add',
                                    style: TextStyle(color: Colors.deepPurple),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child:
                            _loading
                                ? const SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                                : filtered.isEmpty
                                ? SizedBox(
                                  height: 160,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.inbox,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'No expenses for selected filters',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemBuilder: (context, index) {
                                    final t = filtered[index];
                                    final dt = _toDateTime(t['date']).toLocal();
                                    final amountUSD = _getAmountUSD(t);
                                    final key = t['_key'];
                                    // UPDATED: Use lowercase for icon lookup and formatted for display
                                    final category =
                                        (t['category'] ?? 'Uncategorized')
                                            .toString()
                                            .toLowerCase();

                                    return Dismissible(
                                      key: ValueKey(key),
                                      background: Container(
                                        color: Colors.red,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
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
                                        padding: const EdgeInsets.symmetric(
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
                                          child: _getCategoryIcon(category),
                                        ),
                                        title: Text(
                                          '${t['title'] ?? 'Expense'}',
                                        ),
                                        // UPDATED: Use formatted category for display
                                        subtitle: Text(
                                          '${capitalizeFirstLetter(category)} • ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
                                        ),
                                        // UPDATED: Use PriceDisplay widget
                                        trailing: PriceDisplay(
                                          amountUSD: amountUSD,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onTap: () {},
                                      ),
                                    );
                                  },
                                ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}