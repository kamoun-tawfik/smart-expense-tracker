import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart'; // Add this import
import 'dart:io';
import '../../../../main.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../../../core/providers/currency_provider.dart'; // Add this import
import '../../../../../core/constants/currencies.dart'; // Add this import

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _currentUserEmail;
  Map<String, dynamic>? _userData;
  bool _loading = true;

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _editingProfile = false;
  bool _changingPassword = false;
  String? _errorMessage;
  String? _successMessage;

  // Profile image variables
  String? _profileImagePath;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final users = usersBox.keys.toList();
    if (users.isNotEmpty) {
      _currentUserEmail = users.first.toString();
      final dynamic userData = usersBox.get(_currentUserEmail);

      if (userData != null && userData is Map) {
        _userData = _convertMap(userData);

        // Load profile image path if exists
        _profileImagePath = _userData!['profileImagePath'];

        if (_userData != null) {
          _firstNameController.text = _userData!['firstName'] ?? '';
          _lastNameController.text = _userData!['lastName'] ?? '';
          _emailController.text = _currentUserEmail ?? '';
          
          // Initialize currency provider with user's saved currency
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final savedCurrency = _userData!['currency'];
            if (savedCurrency != null && savedCurrency is String) {
              final currencyProvider = context.read<CurrencyProvider>();
              currencyProvider.setCurrency(savedCurrency);
            }
          });
        }
      }
    }
    setState(() => _loading = false);
  }

  // Helper method to convert Map<dynamic, dynamic> to Map<String, dynamic>
  Map<String, dynamic> _convertMap(Map<dynamic, dynamic> originalMap) {
    final Map<String, dynamic> newMap = {};
    originalMap.forEach((key, value) {
      newMap[key.toString()] = value;
    });
    return newMap;
  }

  // Show currency selection modal bottom sheet (better design)
  void _showCurrencySelection() {
    final currencyProvider = context.read<CurrencyProvider>();
    final currentCurrency = currencyProvider.currentCurrency;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
            
            // Currency list - Using our new CurrencyConstants
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
                      onTap: () async {
                        // Update currency provider
                        await currencyProvider.setCurrency(currencyCode);
                        
                        // Save to user data
                        await _saveCurrencyToUserData(currencyCode);
                        
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
                          color: currentCurrency.code == currencyCode
                              ? Colors.deepPurple[50]
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: currentCurrency.code == currencyCode
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
                                    fontWeight: currentCurrency.code == currencyCode
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: currentCurrency.code == currencyCode
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
                            if (currentCurrency.code == currencyCode)
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

  // Save currency preference to user data
  Future<void> _saveCurrencyToUserData(String currencyCode) async {
    if (_userData == null || _currentUserEmail == null) return;
    
    try {
      final updatedData = Map<String, dynamic>.from(_userData!);
      updatedData['currency'] = currencyCode;
      updatedData['updatedAt'] = DateTime.now().toIso8601String();

      await usersBox.put(_currentUserEmail, updatedData);

      // Reload user data
      final dynamic updatedUserData = usersBox.get(_currentUserEmail);
      if (updatedUserData != null && updatedUserData is Map) {
        _userData = _convertMap(updatedUserData);
      }

      setState(() {
        _successMessage = 'Currency updated successfully!';
        _errorMessage = null;
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _successMessage = null);
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to save currency: $e');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _profileImagePath = image.path;
        });

        // Auto-save the image path when a new image is selected
        await _saveProfileImagePath(image.path);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to pick image: $e');
    }
  }

  Future<void> _takePhotoWithCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _profileImagePath = image.path;
        });

        // Auto-save the image path when a new image is taken
        await _saveProfileImagePath(image.path);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to take photo: $e');
    }
  }

  Future<void> _saveProfileImagePath(String imagePath) async {
    try {
      final updatedData = Map<String, dynamic>.from(_userData!);
      updatedData['profileImagePath'] = imagePath;
      updatedData['updatedAt'] = DateTime.now().toIso8601String();

      await usersBox.put(_currentUserEmail, updatedData);

      // Reload user data
      final dynamic updatedUserData = usersBox.get(_currentUserEmail);
      if (updatedUserData != null && updatedUserData is Map) {
        _userData = _convertMap(updatedUserData);
      }

      setState(() {
        _successMessage = 'Profile photo updated successfully!';
        _errorMessage = null;
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _successMessage = null);
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to save profile photo: $e');
    }
  }

  Future<void> _removeProfileImage() async {
    try {
      final updatedData = Map<String, dynamic>.from(_userData!);
      updatedData.remove('profileImagePath');
      updatedData['updatedAt'] = DateTime.now().toIso8601String();

      await usersBox.put(_currentUserEmail, updatedData);

      // Reload user data
      final dynamic updatedUserData = usersBox.get(_currentUserEmail);
      if (updatedUserData != null && updatedUserData is Map) {
        _userData = _convertMap(updatedUserData);
      }

      setState(() {
        _profileImagePath = null;
        _successMessage = 'Profile photo removed successfully!';
        _errorMessage = null;
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _successMessage = null);
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to remove profile photo: $e');
    }
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImageFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Take a Photo'),
                  onTap: () {
                    Navigator.pop(context);
                    _takePhotoWithCamera();
                  },
                ),
                if (_profileImagePath != null)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text(
                      'Remove Photo',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _removeProfileImage();
                    },
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final newFirstName = _firstNameController.text.trim();
    final newLastName = _lastNameController.text.trim();
    final newEmail = _emailController.text.trim();

    try {
      // If email changed, we need to create new entry and delete old one
      if (newEmail != _currentUserEmail) {
        if (usersBox.containsKey(newEmail)) {
          setState(() => _errorMessage = 'Email already exists');
          return;
        }

        // Create new user entry with updated data
        final updatedData = Map<String, dynamic>.from(_userData!);
        updatedData['firstName'] = newFirstName;
        updatedData['lastName'] = newLastName;
        updatedData['updatedAt'] = DateTime.now().toIso8601String();

        await usersBox.put(newEmail, updatedData);

        // Remove old entry if email changed
        if (_currentUserEmail != null) {
          await usersBox.delete(_currentUserEmail);
        }

        _currentUserEmail = newEmail;
      } else {
        // Just update the existing entry
        final updatedData = Map<String, dynamic>.from(_userData!);
        updatedData['firstName'] = newFirstName;
        updatedData['lastName'] = newLastName;
        updatedData['updatedAt'] = DateTime.now().toIso8601String();

        await usersBox.put(_currentUserEmail, updatedData);
      }

      // Reload user data after update
      final dynamic updatedUserData = usersBox.get(_currentUserEmail);
      if (updatedUserData != null && updatedUserData is Map) {
        _userData = _convertMap(updatedUserData);
      }

      setState(() {
        _editingProfile = false;
        _successMessage = 'Profile updated successfully!';
        _errorMessage = null;
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _successMessage = null);
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to update profile: $e');
    }
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = 'New passwords do not match');
      return;
    }

    // Verify current password
    final currentHash = _userData!['passwordHash'];
    String hashPassword(String password) {
      return sha256.convert(utf8.encode(password)).toString();
    }

    if (currentHash != hashPassword(currentPassword)) {
      setState(() => _errorMessage = 'Current password is incorrect');
      return;
    }

    try {
      final updatedData = Map<String, dynamic>.from(_userData!);
      updatedData['passwordHash'] = hashPassword(newPassword);
      updatedData['passwordUpdatedAt'] = DateTime.now().toIso8601String();

      await usersBox.put(_currentUserEmail, updatedData);

      // Reload user data after update
      final dynamic updatedUserData = usersBox.get(_currentUserEmail);
      if (updatedUserData != null && updatedUserData is Map) {
        _userData = _convertMap(updatedUserData);
      }

      setState(() {
        _changingPassword = false;
        _successMessage = 'Password changed successfully!';
        _errorMessage = null;
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _successMessage = null);
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to change password: $e');
    }
  }

  Future<void> _logout() async {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Account'),
            content: const Text(
              'Are you sure you want to delete your account? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true && _currentUserEmail != null) {
      await usersBox.delete(_currentUserEmail);
      _logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyProvider = context.watch<CurrencyProvider>();
    final currentCurrency = currencyProvider.currentCurrency;
    final savedCurrencyCode = _userData?['currency'];

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
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 24,
                    ),
                    child:
                        _loading
                            ? const SizedBox(
                              height: 200,
                              child: Center(child: CircularProgressIndicator()),
                            )
                            : Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Back Button at Top
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: IconButton(
                                      icon: const Icon(Icons.arrow_back),
                                      onPressed: () => Navigator.pop(context),
                                      padding: EdgeInsets.zero,
                                      color: Colors.deepPurple[700],
                                      constraints: const BoxConstraints(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: _showImagePickerModal,
                                        child: CircleAvatar(
                                          radius: 48,
                                          backgroundColor:
                                              Colors.deepPurple[100],
                                          backgroundImage:
                                              _profileImagePath != null
                                                  ? FileImage(
                                                    File(_profileImagePath!),
                                                  )
                                                  : null,
                                          child:
                                              _profileImagePath != null
                                                  ? null
                                                  : const Icon(
                                                    Icons.person,
                                                    size: 50,
                                                    color: Colors.deepPurple,
                                                  ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: GestureDetector(
                                          onTap: _showImagePickerModal,
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _editingProfile
                                        ? 'Edit Profile'
                                        : _changingPassword
                                        ? 'Change Password'
                                        : 'My Profile',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall?.copyWith(
                                      color: Colors.deepPurple[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Success/Error Messages
                                  if (_successMessage != null)
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(_successMessage!),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_errorMessage != null)
                                    Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: Colors.red),
                                    ),

                                  const SizedBox(height: 16),

                                  // Profile Information (when not editing)
                                  if (!_editingProfile &&
                                      !_changingPassword) ...[
                                    _buildInfoRow(
                                      'First Name',
                                      _userData?['firstName'] ?? 'Not set',
                                    ),
                                    _buildInfoRow(
                                      'Last Name',
                                      _userData?['lastName'] ?? 'Not set',
                                    ),
                                    _buildInfoRow(
                                      'Email',
                                      _currentUserEmail ?? 'Not set',
                                    ),
                                    _buildInfoRow(
                                      'Currency',
                                      savedCurrencyCode != null 
                                          ? CurrencyConstants.getCurrency(savedCurrencyCode).name
                                          : 'Not set',
                                    ),
                                    
                                    const SizedBox(height: 24),

                                    // Action Buttons
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.deepPurple,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        onPressed:
                                            () => setState(
                                              () => _editingProfile = true,
                                            ),
                                        child: const Text(
                                          'Edit Profile',
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          side: BorderSide(
                                            color: Colors.deepPurple.shade300,
                                          ),
                                        ),
                                        onPressed:
                                            () => setState(
                                              () => _changingPassword = true,
                                            ),
                                        child: Text(
                                          'Change Password',
                                          style: TextStyle(
                                            color: Colors.deepPurple[700],
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.red,
                                          ),
                                        ),
                                        onPressed: _logout,
                                        child: const Text(
                                          'Logout',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: _deleteAccount,
                                      child: const Text(
                                        'Delete Account',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],

                                  // Edit Profile Form
                                  if (_editingProfile) ...[
                                    TextFormField(
                                      controller: _firstNameController,
                                      decoration: InputDecoration(
                                        labelText: 'First Name',
                                        prefixIcon: const Icon(Icons.person),
                                        filled: true,
                                        fillColor: Colors.deepPurple[50],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      validator:
                                          (value) =>
                                              value == null || value.isEmpty
                                                  ? 'Enter first name'
                                                  : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _lastNameController,
                                      decoration: InputDecoration(
                                        labelText: 'Last Name',
                                        prefixIcon: const Icon(
                                          Icons.person_outline,
                                        ),
                                        filled: true,
                                        fillColor: Colors.deepPurple[50],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      validator:
                                          (value) =>
                                              value == null || value.isEmpty
                                                  ? 'Enter last name'
                                                  : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _emailController,
                                      decoration: InputDecoration(
                                        labelText: 'Email',
                                        prefixIcon: const Icon(Icons.email),
                                        filled: true,
                                        fillColor: Colors.deepPurple[50],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      validator:
                                          (value) =>
                                              value == null || value.isEmpty
                                                  ? 'Enter email'
                                                  : null,
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    // Currency Selection Button
                                    GestureDetector(
                                      onTap: _showCurrencySelection,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurple[50],
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.deepPurple.shade200,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.currency_exchange,
                                              color: Colors.deepPurple,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Currency',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${currentCurrency.code} (${currentCurrency.symbol})',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.arrow_drop_down,
                                              color: Colors.deepPurple,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              side: BorderSide(
                                                color:
                                                    Colors.deepPurple.shade300,
                                              ),
                                            ),
                                            onPressed:
                                                () => setState(
                                                  () {
                                                    _editingProfile = false;
                                                  },
                                                ),
                                            child: Text(
                                              'Cancel',
                                              style: TextStyle(
                                                color: Colors.deepPurple[700],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            onPressed: _updateProfile,
                                            child: const Text('Save Changes'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  // Change Password Form
                                  if (_changingPassword) ...[
                                    TextFormField(
                                      controller: _currentPasswordController,
                                      decoration: InputDecoration(
                                        labelText: 'Current Password',
                                        prefixIcon: const Icon(Icons.lock),
                                        filled: true,
                                        fillColor: Colors.deepPurple[50],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      obscureText: true,
                                      validator:
                                          (value) =>
                                              value == null || value.isEmpty
                                                  ? 'Enter current password'
                                                  : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _newPasswordController,
                                      decoration: InputDecoration(
                                        labelText: 'New Password',
                                        prefixIcon: const Icon(
                                          Icons.lock_outline,
                                        ),
                                        filled: true,
                                        fillColor: Colors.deepPurple[50],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      obscureText: true,
                                      validator:
                                          (value) =>
                                              value == null || value.length < 6
                                                  ? 'At least 6 characters'
                                                  : null,
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _confirmPasswordController,
                                      decoration: InputDecoration(
                                        labelText: 'Confirm New Password',
                                        prefixIcon: const Icon(
                                          Icons.lock_reset,
                                        ),
                                        filled: true,
                                        fillColor: Colors.deepPurple[50],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      obscureText: true,
                                      validator:
                                          (value) =>
                                              value == null || value.length < 6
                                                  ? 'At least 6 characters'
                                                  : null,
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              side: BorderSide(
                                                color:
                                                    Colors.deepPurple.shade300,
                                              ),
                                            ),
                                            onPressed:
                                                () => setState(
                                                  () =>
                                                      _changingPassword = false,
                                                ),
                                            child: Text(
                                              'Cancel',
                                              style: TextStyle(
                                                color: Colors.deepPurple[700],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            onPressed: _changePassword,
                                            child: const Text(
                                              'Change Password',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}