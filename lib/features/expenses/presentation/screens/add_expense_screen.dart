import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import '../../../../../main.dart';
import '../../../../../core/providers/currency_provider.dart';
import '../../../../../core/constants/currencies.dart';
import '../../../ocr/presentation/screens/ocr_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _currencyController = TextEditingController();
  
  DateTime _date = DateTime.now();
  String? _imagePath;
  String _selectedCurrency = 'USD';
  String? _selectedCategory;
  
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    
    // Initialize with current user's currency preference
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currencyProvider = context.read<CurrencyProvider>();
      setState(() {
        _selectedCurrency = currencyProvider.currentCurrency.code;
        _updateCurrencyDisplay();
      });
    });
  }

  void _updateCurrencyDisplay() {
    final currency = CurrencyConstants.getCurrency(_selectedCurrency);
    _currencyController.text = '${currency.code} (${currency.symbol})';
  }

  Future<void> _loadCategories() async {
    final box = await Hive.openBox('settings');
    final saved = box.get('categories', defaultValue: <String>[]);
    setState(() {
      _categories = List<String>.from(saved);
      if (_categories.isEmpty) {
        _categories = [
          'Food & Drinks',
          'Transport',
          'Shopping',
          'Entertainment',
          'Bills',
          'Health',
          'Groceries',
          'Travel',
          'Other'
        ];
        box.put('categories', _categories);
      }
    });
  }

  Future<void> _addNewCategory() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g. Subscription, Rent',
            filled: true,
            fillColor: Colors.deepPurple.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && !_categories.contains(result)) {
      setState(() {
        _categories.add(result);
        _selectedCategory = result;
      });
      await Hive.box('settings').put('categories', _categories);
    }
  }

  // Show currency selection modal
  void _showCurrencySelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
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
                    onPressed: () => Navigator.pop(context),
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
            
            // Divider
            Divider(height: 1, color: Colors.grey[300]),
            
            // Currency list
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
                          _selectedCurrency = currencyCode;
                          _updateCurrencyDisplay();
                        });
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedCurrency == currencyCode
                              ? Colors.deepPurple[50]
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedCurrency == currencyCode
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
                                    fontWeight: _selectedCurrency == currencyCode
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _selectedCurrency == currencyCode
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
                            if (_selectedCurrency == currencyCode)
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
            
            // Bottom padding for safe area
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['imagePath'] != null) {
      _imagePath = args['imagePath'] as String?;
      if ((_titleCtrl.text).isEmpty && _imagePath != null) {
        _titleCtrl.text = 'Receipt';
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _processReceiptWithOcr() async {
    if (_imagePath == null) return;
    final recognized = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => OcrScreen(initialImagePath: _imagePath),
      ),
    );
    if (recognized != null && recognized.isNotEmpty) {
      final lines =
          recognized
              .split(RegExp(r'\r?\n'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
      if (lines.isNotEmpty) _titleCtrl.text = lines.first;
      final numMatch = RegExp(r'[\d]+[.,]?\d*').firstMatch(recognized);
      if (numMatch != null) {
        final amtStr = numMatch.group(0)!.replaceAll(',', '.');
        _amountCtrl.text = amtStr;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OCR processed — fields prefilled')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }
    
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText.replaceAll(',', '.')) ?? 0.0;
    
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final box = transactionsBox;
    
    // Convert amount to USD for storage
    final amountUSD = CurrencyConstants.convertToUSD(amount, _selectedCurrency);
    
    final entry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': _titleCtrl.text.trim(),
      'amountUSD': amountUSD,
      'originalAmount': amount,
      'currencyCode': _selectedCurrency,
      'category': _selectedCategory!,
      'date': _date.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      if (_imagePath != null) 'imagePath': _imagePath,
    };
    
    await box.add(entry);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Expense saved: ${CurrencyConstants.format(amount, _selectedCurrency)}'),
        ),
      );
      Navigator.pop(context);
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 20,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.pop(context),
                                color: Colors.deepPurple[700],
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Add Expense',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_imagePath != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_imagePath!),
                                height: 180,
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (_imagePath != null)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _processReceiptWithOcr,
                                icon: const Icon(Icons.auto_fix_high),
                                label: const Text('Process Receipt (OCR)'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _titleCtrl,
                            decoration: InputDecoration(
                              labelText: 'Title',
                              prefixIcon: const Icon(Icons.title),
                              filled: true,
                              fillColor: Colors.deepPurple[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator:
                                (v) =>
                                    v == null || v.isEmpty
                                        ? 'Enter title'
                                        : null,
                          ),
                          const SizedBox(height: 12),
                          
                          // Amount with Currency Selection
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _amountCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Amount',
                                    prefixIcon: const Icon(Icons.attach_money),
                                    filled: true,
                                    fillColor: Colors.deepPurple[50],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  validator:
                                      (v) =>
                                          v == null ||
                                                  v.isEmpty ||
                                                  double.tryParse(v.replaceAll(',', '.')) == null
                                              ? 'Enter valid amount'
                                              : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Currency Selection Button
                              SizedBox(
                                width: 120,
                                child: GestureDetector(
                                  onTap: _showCurrencySelection,
                                  child: TextFormField(
                                    controller: _currencyController,
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
                          
                          // CATEGORY PICKER - Scrollable list with add option
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final selected = await showModalBottomSheet<String>(
                                context: context,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (ctx) => CategoryPickerSheet(
                                  categories: _categories,
                                  selectedCategory: _selectedCategory,
                                  onCategorySelected: (cat) => Navigator.pop(ctx, cat),
                                  onAddNewCategory: _addNewCategory,
                                ),
                              );
                              if (selected != null) {
                                setState(() => _selectedCategory = selected);
                              }
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Category',
                                prefixIcon: const Icon(Icons.category),
                                filled: true,
                                fillColor: Colors.deepPurple[50],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.deepPurple.shade200),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _selectedCategory ?? 'Select category',
                                    style: TextStyle(
                                      color: _selectedCategory == null ? Colors.grey[600] : Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Date: ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                                ),
                              ),
                              TextButton(
                                onPressed: _pickDate,
                                child: const Text('Pick Date'),
                              ),
                            ],
                          ),
                          SizedBox(
                            child: ElevatedButton(
                              onPressed: _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text('Save Expense'),
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
          ),
        ),
      ),
    );
  }
}

// Category Picker Bottom Sheet
class CategoryPickerSheet extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;
  final Function(String) onCategorySelected;
  final VoidCallback onAddNewCategory;

  const CategoryPickerSheet({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.onAddNewCategory,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Choose Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: onAddNewCategory,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                  style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 320,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final isSelected = cat == selectedCategory;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: isSelected ? Colors.deepPurple.shade100 : null,
                  child: ListTile(
                    leading: Icon(
                      _getCategoryIcon(cat),
                      color: isSelected ? Colors.deepPurple : Colors.grey.shade700,
                    ),
                    title: Text(cat, style: const TextStyle(fontWeight: FontWeight.w500)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.deepPurple) : null,
                    onTap: () => onCategorySelected(cat),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    final catLower = category.toLowerCase();
    if (catLower.contains('food') || catLower.contains('drink') || catLower.contains('restaurant')) {
      return Icons.restaurant;
    } else if (catLower.contains('transport') || catLower.contains('car') || catLower.contains('taxi')) {
      return Icons.directions_car;
    } else if (catLower.contains('shop') || catLower.contains('mall') || catLower.contains('store')) {
      return Icons.shopping_bag;
    } else if (catLower.contains('entertain') || catLower.contains('movie') || catLower.contains('game')) {
      return Icons.movie;
    } else if (catLower.contains('bill') || catLower.contains('rent') || catLower.contains('utility')) {
      return Icons.receipt;
    } else if (catLower.contains('health') || catLower.contains('medical') || catLower.contains('pharmacy')) {
      return Icons.local_hospital;
    } else if (catLower.contains('grocery') || catLower.contains('supermarket')) {
      return Icons.shopping_cart;
    } else if (catLower.contains('travel') || catLower.contains('hotel') || catLower.contains('flight')) {
      return Icons.flight;
    } else {
      return Icons.category;
    }
  }
}