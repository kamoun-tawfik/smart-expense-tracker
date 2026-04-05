import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../../../../core/constants/currencies.dart';
import '../../../../core/providers/currency_provider.dart';
import '../../../../core/utils/currency_utils.dart';


class OcrScreen extends StatefulWidget {
  final String? initialImagePath;
  const OcrScreen({super.key, this.initialImagePath});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _image;
  String _recognizedText = '';
  bool _isProcessing = false;

  // Controllers for in-screen editing
  final TextEditingController _vendorController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _totalController = TextEditingController();
  final TextEditingController _taxController = TextEditingController();

  // Extracted fields
  String _vendor = '';
  String _date = '';
  double _total = 0.0;
  double _tax = 0.0;
  String _category = 'Other';
  String _currencySymbol = '\$';
  String _currencyCode = 'USD';

  // camera integration / live viewfinder
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isCameraInitializing = false;
  bool _isPreviewing = false;
  int _currentCameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  // guidance UI
  Timer? _guidanceTimer;
  String _guidanceMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _processPath(widget.initialImagePath!);
    }
  }

  @override
  void dispose() {
    _guidanceTimer?.cancel();
    _disposeCamera();
    _vendorController.dispose();
    _dateController.dispose();
    _totalController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  // ---------------- image picking / scanning ----------------
  Future<void> _processPath(String path) async {
    setState(() {
      _image = File(path);
      _recognizedText = '';
      _isProcessing = true;
    });
    await _scanFile(path);
  }

  Future<void> _pickAndScan() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return;
    }
    setState(() {
      _image = File(picked.path);
      _recognizedText = '';
      _isProcessing = true;
      _isPreviewing = false;
    });
    await _scanFile(picked.path);
  }

  /// Pre-processes the image to improve OCR accuracy using a manual threshold loop.
  Future<String?> _preprocessImage(String originalPath) async {
    try {
      final originalFile = File(originalPath);
      final imageBytes = await originalFile.readAsBytes();

      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        return null;
      }

      // 1. Convert to grayscale
      final grayscaleImage = img.grayscale(originalImage);

      // 2. Manual Threshold Loop
      final threshold = 128;
      final width = grayscaleImage.width;
      final height = grayscaleImage.height;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = grayscaleImage.getPixel(x, y);
          if (pixel.r > threshold) {
            grayscaleImage.setPixel(x, y, img.ColorRgb8(255, 255, 255));
          } else {
            grayscaleImage.setPixel(x, y, img.ColorRgb8(0, 0, 0));
          }
        }
      }

      // 3. Save the processed image
      final tempDir = await getTemporaryDirectory();
      final processedFile = File(
        '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await processedFile.writeAsBytes(
        img.encodeJpg(grayscaleImage, quality: 95),
      );

      return processedFile.path;
    } catch (e) {
      debugPrint("Image preprocessing failed: $e");
      return null;
    }
  }

  Future<void> _scanFile(String path) async {
    // 1. Pre-process the image
    final processedImagePath = await _preprocessImage(path);

    if (processedImagePath == null) {
      if (mounted) {
        setState(() {
          _recognizedText = 'Error: Could not process image.';
          _isProcessing = false;
        });
      }
      return;
    }

    // 2. Send to Google ML Kit
    final inputImage = InputImage.fromFilePath(processedImagePath);
    final textRecognizer = TextRecognizer();

    try {
      final RecognizedText result = await textRecognizer.processImage(inputImage);
      final rawText = result.text;
      if (mounted) {
        setState(() => _recognizedText = rawText);
      }

      // 3. Parse the extracted text
      if (rawText.isNotEmpty) {
        _parseReceiptData(rawText);
      } else {
        if (mounted) {
          setState(() {
            _vendor = 'Not detected';
            _total = 0.0;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recognizedText = 'Error during OCR: $e';
        });
      }
    } finally {
      await textRecognizer.close();
      try {
        await File(processedImagePath).delete();
      } catch (e) {
        debugPrint("Failed to delete temporary image: $e");
      }
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ---------------- receipt data parsing ----------------
  void _parseReceiptData(String text) {
    // Reset fields
    setState(() {
      _vendor = '';
      _date = '';
      _total = 0.0;
      _tax = 0.0;
      _category = 'Other';
      _currencySymbol = '\$';
      _currencyCode = 'USD';
    });

    final lines = text.split('\n');

    // Extract currency information using CurrencyUtils
    _extractCurrencyInfo(text);

    // Extract all amounts with their context
    final amountEntries = _extractAllAmountsWithContext(lines);

    // Use multiple strategies for extraction
    _vendor = _extractVendorAdvanced(lines, text);
    _date = _extractDateAdvanced(lines, text);

    // Extract subtotal first (helps with tax calculation)
    double subtotal = _extractSubtotal(amountEntries, lines);

    // Extract total using robust logic
    _total = _selectBestTotal(amountEntries, lines, subtotal);

    // Extract tax using robust logic
    _tax = _extractTaxAdvanced(amountEntries, lines, _total, subtotal);

    // Auto-categorize based on vendor
    _categorizeExpense();

    // Update controllers with the parsed data
    if (mounted) {
      setState(() {
        _vendorController.text = _vendor;
        _dateController.text = _date;
        // Format amounts based on currency decimal rules
        final currency = CurrencyConstants.getCurrency(_currencyCode);
        _totalController.text = _total.toStringAsFixed(currency.decimalDigits);
        _taxController.text = _tax.toStringAsFixed(currency.decimalDigits);
      });
    }
  }

  void _extractCurrencyInfo(String text) {
    // Use CurrencyUtils for detection
    final detectedCode = CurrencyUtils.detectCurrencyFromText(text);
    
    setState(() {
      if (detectedCode != null && CurrencyUtils.isValidCurrency(detectedCode)) {
        _currencyCode = detectedCode;
        final currency = CurrencyConstants.getCurrency(detectedCode);
        _currencySymbol = currency.symbol;
      } else {
        // Fallback to default
        _currencyCode = CurrencyConstants.defaultCurrency;
        _currencySymbol = CurrencyConstants.getCurrency(CurrencyConstants.defaultCurrency).symbol;
      }
    });
  }

  String _extractVendorAdvanced(List<String> lines, String fullText) {
    final commonHeaders = [
      'receipt', 'invoice', 'bill', 'order', 'transaction', 'sale',
      'thank you', 'thanks', 'visa', 'mastercard', 'amex', 'debit',
      'credit', 'cash', 'change', 'subtotal', 'total', 'tax', 'date',
      'time', 'qty', 'quantity', 'description', 'price', 'amount',
      'balance', 'due', 'paid', 'payment', 'card', 'terminal', 'online',
    ];
    final websitePattern = RegExp(r'(www\.|http|\.com|\.org|\.net|\.io)');
    final emailPattern = RegExp(r'@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');

    for (int i = 0; i < min(8, lines.length); i++) {
      final line = lines[i].trim();
      if (line.length > 3 &&
          line.length < 60 &&
          !_isLikelyHeader(line, commonHeaders) &&
          !websitePattern.hasMatch(line) &&
          !emailPattern.hasMatch(line) &&
          !_isDate(line) &&
          !_isNumeric(line) &&
          !line.contains('#') &&
          !line.contains('****') &&
          !_isCommonReceiptJunk(line)) {
        return line;
      }
    }
    for (int i = 0; i < min(10, lines.length); i++) {
      final line = lines[i].trim();
      if (line == line.toUpperCase() &&
          line.length > 5 &&
          line.length < 50 &&
          line.split(' ').length <= 5 &&
          !_isCommonReceiptJunk(line)) {
        return line;
      }
    }
    return '';
  }

  String _extractDateAdvanced(List<String> lines, String fullText) {
    final datePatterns = [
      // MM/DD/YYYY, M/D/YYYY
      RegExp(r'\b(0[1-9]|1[0-2])[\/\-\.](0[1-9]|[12][0-9]|3[01])[\/\-\.](\d{2}|\d{4})\b'),
      RegExp(r'\b([1-9])[\/\-\.]([1-9]|[12][0-9]|3[01])[\/\-\.](\d{2}|\d{4})\b'),
      // Month DD, YYYY / Mon DD, YYYY
      RegExp(r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})\b', caseSensitive: false),
      RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2}),?\s+(\d{4})\b', caseSensitive: false),
      // DD Month, YYYY / DD Mon, YYYY
      RegExp(r'\b(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})\b', caseSensitive: false),
      RegExp(r'\b(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{4})\b', caseSensitive: false),
    ];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('date') || line.contains('time') || line.contains('issued')) {
        for (final pattern in datePatterns) {
          final match = pattern.firstMatch(lines[i]);
          if (match != null) {
            return match.group(0)!;
          }
        }
        if (i + 1 < lines.length) {
          for (final pattern in datePatterns) {
            final match = pattern.firstMatch(lines[i + 1]);
            if (match != null) {
              return match.group(0)!;
            }
          }
        }
      }
    }
    
    // General search if no keyword is found
    for (final line in lines) {
      for (final pattern in datePatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          return match.group(0)!;
        }
      }
    }
    return '';
  }

  List<AmountEntry> _extractAllAmountsWithContext(List<String> lines) {
    final entries = <AmountEntry>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final amounts = _extractAllAmountsFromLine(line);
      for (final amount in amounts) {
        if (amount > 0 && _isReasonableAmount(amount)) {
          entries.add(
            AmountEntry(
              amount: amount,
              line: line,
              lineIndex: i,
              context: _getLineContext(lines, i),
              hasTotalKeyword: _hasTotalKeyword(line),
              hasTaxKeyword: _hasTaxKeyword(line),
              hasSubtotalKeyword: _hasSubtotalKeyword(line),
              isAtBottom: i >= lines.length - 5,
              isStandaloneAmount: _isStandaloneAmount(line, amount),
            ),
          );
        }
      }
    }
    return entries;
  }

  List<double> _extractAllAmountsFromLine(String line) {
    final amounts = <double>[];
    final normalizedLine = line.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Use currency-specific patterns
    if (_currencyCode == 'HUF') {
      // HUF typically doesn't use decimals
      final pattern = RegExp(r'([\d,]+)');
      final matches = pattern.allMatches(normalizedLine);
      
      for (final match in matches) {
        try {
          String amountStr = match.group(1)!;
          amountStr = amountStr.replaceAll(',', '');
          final amount = double.tryParse(amountStr);
          if (amount != null && amount > 0) {
            amounts.add(amount);
          }
        } catch (e) {}
      }
    } else {
      // Standard decimal pattern for other currencies
      final pattern = RegExp(r'([\d,]+(?:\.\d{1,2})?)');
      final matches = pattern.allMatches(normalizedLine);
      
      for (final match in matches) {
        try {
          String amountStr = match.group(1)!;
          amountStr = amountStr.replaceAll(',', '');
          final amount = double.tryParse(amountStr);
          if (amount != null && amount > 0) {
            amounts.add(amount);
          }
        } catch (e) {}
      }
    }
    
    return amounts;
  }

  double _extractSubtotal(List<AmountEntry> entries, List<String> lines) {
    final subtotalEntries = entries.where(
      (e) => e.hasSubtotalKeyword && _isReasonableAmount(e.amount),
    );
    if (subtotalEntries.isNotEmpty) {
      final standaloneSubtotal = subtotalEntries.where(
        (e) => e.isStandaloneAmount,
      );
      if (standaloneSubtotal.isNotEmpty) {
        return standaloneSubtotal.first.amount;
      }
      return subtotalEntries.first.amount;
    }
    return 0.0;
  }

  double _selectBestTotal(
    List<AmountEntry> entries,
    List<String> lines,
    double subtotal,
  ) {
    // Strategy 1: Explicit "Total" keyword (Highest Priority)
    for (final entry in entries) {
      if (entry.hasTotalKeyword && entry.isStandaloneAmount) {
        return CurrencyUtils.roundForCurrency(entry.amount, _currencyCode);
      }
    }
    for (final entry in entries) {
      if (entry.hasTotalKeyword) {
        return CurrencyUtils.roundForCurrency(entry.amount, _currencyCode);
      }
    }

    // Strategy 2: Subtotal + Tax validation
    if (subtotal > 0) {
      final taxEntries = entries.where(
        (e) => e.hasTaxKeyword && _isReasonableAmount(e.amount),
      );
      for (final taxEntry in taxEntries) {
        final calculatedTotal = subtotal + taxEntry.amount;
        // Look for an amount that matches our calculated total
        for (final entry in entries) {
          if ((entry.amount - calculatedTotal).abs() < 0.05) {
            return CurrencyUtils.roundForCurrency(entry.amount, _currencyCode);
          }
        }
      }
    }

    // Strategy 3: Largest amount at the bottom of the receipt
    final bottomEntries = entries.where((e) => e.isAtBottom).toList();
    if (bottomEntries.isNotEmpty) {
      bottomEntries.sort((a, b) => b.amount.compareTo(a.amount));
      return CurrencyUtils.roundForCurrency(bottomEntries.first.amount, _currencyCode);
    }

    return 0.0;
  }

  double _extractTaxAdvanced(
    List<AmountEntry> entries,
    List<String> lines,
    double total,
    double subtotal,
  ) {
    // Strategy 1: Explicit "Tax" keyword
    final taxEntries = entries.where(
      (e) => e.hasTaxKeyword && _isReasonableAmount(e.amount),
    );
    if (taxEntries.isNotEmpty) {
      final standaloneTax = taxEntries.where((e) => e.isStandaloneAmount);
      if (standaloneTax.isNotEmpty) {
        return CurrencyUtils.roundForCurrency(standaloneTax.first.amount, _currencyCode);
      }
      return CurrencyUtils.roundForCurrency(taxEntries.first.amount, _currencyCode);
    }

    // Strategy 2: Calculate from Total and Subtotal
    if (total > 0 && subtotal > 0) {
      final calculatedTax = total - subtotal;
      if (calculatedTax > 0 && calculatedTax < total * 0.3) {
        return CurrencyUtils.roundForCurrency(calculatedTax, _currencyCode);
      }
    }
    return 0.0;
  }

  bool _isReasonableAmount(double amount) {
    double maxAmount = 100000;
    if (_currencyCode == 'HUF') {
      maxAmount = 10000000;
    } else if (_currencyCode == 'JPY' || _currencyCode == 'KRW') {
      maxAmount = 1000000;
    }
    return amount > 0 &&
        amount < maxAmount &&
        amount != 123456 &&
        amount != 999999 &&
        _hasReasonableDecimal(amount);
  }

  bool _hasReasonableDecimal(double amount) {
    final currency = CurrencyConstants.getCurrency(_currencyCode);
    if (currency.decimalDigits == 0) {
      return true;
    }
    final decimalPart = amount - amount.truncate();
    if (amount > 1000 && decimalPart == 0) {
      return false;
    }
    return true;
  }

  bool _isStandaloneAmount(String line, double amount) {
    final cleanLine = line.replaceAll(RegExp(r'[^\w\s$€£¥₹.,]'), '').trim();
    final amountStr = amount.toStringAsFixed(2);
    final amountPattern = RegExp(amountStr.replaceAll('.', r'\.'));
    return cleanLine.length < 15 ||
        amountPattern.hasMatch(cleanLine) ||
        cleanLine.replaceAll(RegExp(r'[^\d]'), '').length ==
            amountStr.replaceAll('.', '').length;
  }

  bool _isLikelyHeader(String line, List<String> commonHeaders) {
    final lowerLine = line.toLowerCase();
    return commonHeaders.any((header) => lowerLine.contains(header));
  }

  bool _isCommonReceiptJunk(String line) {
    final junkPatterns = [
      'ipsum', 'lorem', 'freepik', 'designed by', 'thank you',
      '********', 'approval', 'code', 'bureau', 'clone', 'change',
      'card', 'visa', 'mastercard', 'amex', 'terminal', 'authorized',
      'signature',
    ];
    final lowerLine = line.toLowerCase();
    return junkPatterns.any((pattern) => lowerLine.contains(pattern));
  }

  bool _hasTotalKeyword(String line) {
    final keywords = [
      'total', 'balance', 'amount due', 'grand total', 'final amount',
      'payable', 'receipt total',
    ];
    final lowerLine = line.toLowerCase();
    return keywords.any((keyword) => lowerLine.contains(keyword)) &&
        !lowerLine.contains('subtotal');
  }

  bool _hasTaxKeyword(String line) {
    final keywords = ['tax', 'gst', 'hst', 'vat', 'sales tax'];
    return keywords.any((keyword) => line.toLowerCase().contains(keyword));
  }

  bool _hasSubtotalKeyword(String line) {
    final keywords = ['subtotal', 'sub total', 'sub-total'];
    return keywords.any((keyword) => line.toLowerCase().contains(keyword));
  }

  String _getLineContext(List<String> lines, int index) {
    final context = <String>[];
    if (index > 0) {
      context.add(lines[index - 1]);
    }
    context.add(lines[index]);
    if (index < lines.length - 1) {
      context.add(lines[index + 1]);
    }
    return context.join(' | ');
  }

  bool _isDate(String text) {
    final datePatterns = [
      RegExp(r'\b\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}\b'),
      RegExp(r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b', caseSensitive: false),
      RegExp(r'\b(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\b', caseSensitive: false),
    ];
    return datePatterns.any((pattern) => pattern.hasMatch(text));
  }

  bool _isNumeric(String text) {
    return double.tryParse(text.replaceAll(RegExp(r'[^\d.]'), '')) != null;
  }

  void _categorizeExpense() {
    final vendorLower = _vendor.toLowerCase();
    setState(() {
      if (vendorLower.contains('repair') || vendorLower.contains('service')) {
        _category = 'Services';
      } else if (vendorLower.contains('apple') || vendorLower.contains('electronics')) {
        _category = 'Electronics';
      } else if (vendorLower.contains('grocery') || vendorLower.contains('market')) {
        _category = 'Groceries';
      } else if (vendorLower.contains('restaurant') || vendorLower.contains('cafe')) {
        _category = 'Food & Dining';
      } else if (vendorLower.contains('gas') || vendorLower.contains('fuel')) {
        _category = 'Transportation';
      } else if (vendorLower.contains('nike') || vendorLower.contains('sports')) {
        _category = 'Shopping';
      } else {
        _category = 'Other';
      }
    });
  }

  // ---------------- saving expense data ----------------
  Future<String?> _copyImageToAppDir(File? src) async {
    if (src == null || !await src.exists()) {
      return null;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${docs.path}/expense_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      final filename = src.uri.pathSegments.isNotEmpty
          ? src.uri.pathSegments.last
          : 'expense_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final destPath = '${imagesDir.path}/$filename';
      final destFile = await src.copy(destPath);
      return destFile.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveExpense() async {
    try {
      // Read from controllers
      final vendor = _vendorController.text;
      final date = _dateController.text;
      final total = double.tryParse(_totalController.text) ?? 0.0;
      final tax = double.tryParse(_taxController.text) ?? 0.0;

      if (total <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a valid total amount.')),
          );
        }
        return;
      }

      // Convert amounts to USD for storage
      final totalUSD = CurrencyConstants.convertToUSD(total, _currencyCode);
      final taxUSD = CurrencyConstants.convertToUSD(tax, _currencyCode);

      final savedImagePath = await _copyImageToAppDir(_image);
      final expense = {
        'title': vendor.isNotEmpty ? vendor : 'Receipt Expense',
        'amount': totalUSD, // Store in USD
        'category': _category,
        'date': date.isNotEmpty ? date : DateTime.now().toIso8601String().split('T')[0],
        'vendor': vendor,
        'tax': taxUSD, // Store in USD
        'currencySymbol': _currencySymbol,
        'currencyCode': _currencyCode,
        'imagePath': savedImagePath,
        'notes': _recognizedText.length > 100
            ? '${_recognizedText.substring(0, 100)}...'
            : _recognizedText,
        'createdAt': DateTime.now().toIso8601String(),
        'originalAmount': total, // Store original amount for reference
        'originalTax': tax, // Store original tax for reference
      };
      
      if (!Hive.isBoxOpen('transactions')) {
        await Hive.openBox('transactions');
      }
      final box = Hive.box('transactions');
      await box.add(expense);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense saved successfully!')),
        );
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      debugPrint('Failed to save expense: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save expense')),
        );
      }
    }
  }

  // ---------------- camera helpers ----------------
  Future<void> _fetchCameras() async {
    try {
      _cameras = await availableCameras();
    } catch (_) {
      _cameras = [];
    }
  }

  Future<void> _initCamera(CameraDescription camera) async {
    await _disposeCamera();
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      setState(() => _isCameraInitializing = true);
      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(_flashMode);
    } catch (_) {
      await _disposeCamera();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to initialize camera')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCameraInitializing = false);
      }
    }
  }

  Future<void> _disposeCamera() async {
    try {
      await _cameraController?.dispose();
    } catch (_) {}
    _cameraController = null;
    if (mounted) {
      setState(() => _isPreviewing = false);
    }
  }

  Future<void> _startPreview() async {
    await _fetchCameras();
    if (_cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No camera found')),
        );
      }
      return;
    }
    _currentCameraIndex = 0;
    await _initCamera(_cameras[_currentCameraIndex]);
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      if (mounted) {
        setState(() => _isPreviewing = true);
      }
      _startGuidanceSequence();
    }
  }

  Future<void> _stopPreview() async {
    await _disposeCamera();
    if (mounted) {
      setState(() => _isPreviewing = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) {
      return;
    }
    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _initCamera(_cameras[_currentCameraIndex]);
    if (mounted) {
      setState(() {});
      _startGuidanceSequence();
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) {
      return;
    }
    try {
      _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _cameraController!.setFlashMode(_flashMode);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _captureFromCamera() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      setState(() {
        _isProcessing = true;
        _guidanceMessage = 'Processing...';
      });
      final XFile file = await _cameraController!.takePicture();
      if (!mounted) {
        return;
      }
      setState(() {
        _image = File(file.path);
        _isPreviewing = false;
      });
      await _scanFile(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      await _disposeCamera();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _guidanceMessage = '';
        });
      }
    }
  }

  void _startGuidanceSequence() {
    _guidanceTimer?.cancel();
    setState(() => _guidanceMessage = 'Move closer');
    _guidanceTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() => _guidanceMessage = 'Hold steady');
      }
    });
  }

  // Helper functions for the editable UI
  Widget _buildEditableDetailRow(
    String label,
    TextEditingController controller, {
    bool isDate = false,
    bool isCurrency = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: isCurrency 
                  ? TextInputType.numberWithOptions(decimal: true)
                  : isDate 
                      ? TextInputType.none
                      : TextInputType.text,
              readOnly: isDate,
              decoration: InputDecoration(
                hintText: 'Enter $label',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                prefixText: isCurrency ? _currencySymbol : null,
                suffixIcon: isDate
                    ? IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () => _selectDate(controller),
                      )
                    : null,
              ),
              onChanged: (value) {
                if (isCurrency) {
                  // Round to appropriate decimal places
                  final amount = double.tryParse(value);
                  if (amount != null) {
                    final rounded = CurrencyUtils.roundForCurrency(amount, _currencyCode);
                    final currency = CurrencyConstants.getCurrency(_currencyCode);
                    if (value != rounded.toStringAsFixed(currency.decimalDigits)) {
                      controller.text = rounded.toStringAsFixed(currency.decimalDigits);
                    }
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Text(
              'Category: ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Other', child: Text('Other')),
                DropdownMenuItem(value: 'Services', child: Text('Services')),
                DropdownMenuItem(value: 'Electronics', child: Text('Electronics')),
                DropdownMenuItem(value: 'Groceries', child: Text('Groceries')),
                DropdownMenuItem(value: 'Food & Dining', child: Text('Food & Dining')),
                DropdownMenuItem(value: 'Transportation', child: Text('Transportation')),
                DropdownMenuItem(value: 'Healthcare', child: Text('Healthcare')),
                DropdownMenuItem(value: 'Entertainment', child: Text('Entertainment')),
                DropdownMenuItem(value: 'Shopping', child: Text('Shopping')),
                DropdownMenuItem(value: 'Travel', child: Text('Travel')),
              ],
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _category = newValue;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final formattedDate =
          "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      controller.text = formattedDate;
    }
  }

 // ---------------- UI ----------------
@override
Widget build(BuildContext context) {
  return Consumer<CurrencyProvider>(
    builder: (context, currencyProvider, child) {
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
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 18,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Receipt Scanner',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.deepPurple[100],
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              size: 34,
                              color: Colors.deepPurple,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Capture receipt to extract expense details',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    icon: _isProcessing
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.photo_library),
                                    label: Text(
                                      _isProcessing ? 'Processing...' : 'Pick image',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepPurple,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _isProcessing ? null : _pickAndScan,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  icon: _isCameraInitializing
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          _isPreviewing ? Icons.camera_alt : Icons.camera_alt,
                                        ),
                                  label: Text(
                                    _isPreviewing
                                        ? 'Stop camera'
                                        : (_isCameraInitializing
                                            ? 'Initializing...'
                                            : 'Live camera'),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _isCameraInitializing
                                      ? null
                                      : (_isPreviewing ? _stopPreview : _startPreview),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_isPreviewing &&
                            _cameraController != null &&
                            _cameraController!.value.isInitialized)
                          Container(
                            height: 500,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12), // Rounded corners
                              color: Colors.black,
                            ),
                            child: ClipRRect( // This will clip the camera to the container
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  // Camera preview - fills container
                                  SizedBox.expand(
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: _cameraController!.value.previewSize!.width,
                                        height: _cameraController!.value.previewSize!.height,
                                        child: CameraPreview(_cameraController!),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 10,
                                    left: 10,
                                    right: 10,
                                    child: AnimatedOpacity(
                                      opacity: _guidanceMessage.isNotEmpty ? 1.0 : 0.0,
                                      duration: const Duration(milliseconds: 250),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black45,
                                            borderRadius: BorderRadius.circular(24),
                                          ),
                                          child: Text(
                                            _guidanceMessage,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          tooltip: 'Switch camera',
                                          icon: const Icon(
                                            Icons.switch_camera,
                                            color: Colors.white,
                                          ),
                                          onPressed: _isCameraInitializing ? null : _switchCamera,
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            shape: const CircleBorder(),
                                            backgroundColor: Colors.white70,
                                            padding: const EdgeInsets.all(14),
                                          ),
                                          onPressed: _isCameraInitializing ? null : _captureFromCamera,
                                          child: const Icon(
                                            Icons.camera_alt,
                                            color: Colors.black87,
                                            size: 28,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Toggle flash',
                                          icon: Icon(
                                            _flashMode == FlashMode.off
                                                ? Icons.flash_off
                                                : Icons.flash_on,
                                            color: Colors.white,
                                          ),
                                          onPressed: _isCameraInitializing ? null : _toggleFlash,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!_isPreviewing && _image != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Container(
                                height: 250, // CHANGED: Match camera height
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(_image!, fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          // Currency info display
                          if (_currencyCode.isNotEmpty)
                          // Editable Details Section
                          if (_vendor.isNotEmpty || _total > 0)
                            Column(
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Extracted Details:',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      _buildEditableDetailRow('Vendor', _vendorController),
                                      _buildEditableDetailRow('Date', _dateController, isDate: true),
                                      _buildEditableDetailRow('Total', _totalController, isCurrency: true),
                                      _buildEditableDetailRow('Tax', _taxController, isCurrency: true),
                                      _buildCategoryRow(),
                                    ],
                                  ),
                                ),                                    
                              ],
                            ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                onPressed: (_total > 0) ? _saveExpense : null,
                                icon: const Icon(Icons.save),
                                label: const Text('Save Expense'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
    },
  );
}
}

class AmountEntry {
  final double amount;
  final String line;
  final int lineIndex;
  final String context;
  final bool hasTotalKeyword;
  final bool hasTaxKeyword;
  final bool hasSubtotalKeyword;
  final bool isAtBottom;
  final bool isStandaloneAmount;

  AmountEntry({
    required this.amount,
    required this.line,
    required this.lineIndex,
    required this.context,
    required this.hasTotalKeyword,
    required this.hasTaxKeyword,
    required this.hasSubtotalKeyword,
    required this.isAtBottom,
    required this.isStandaloneAmount,
  });
}