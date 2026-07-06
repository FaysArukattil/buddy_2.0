// ProfileScreen - Initially shows Google photo, then allows custom upload to local storage

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/images.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/repositories/transaction_repository.dart';
import 'package:buddy/services/notification_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  void refreshData() {
    _loadProfile();
  }

  final _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String _email = '';
  String? _customImagePath; // Local file path for custom image
  String? _googlePhotoUrl; // Google account photo URL
  bool _editing = false;
  // ignore: unused_field
  final bool _uploadingImage = false;
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _moneyLottieDy = 0;
  int _lottieTapEpoch = 0;
  double _moneyLottieScale = 1.0;
  late final AnimationController _headerController;
  late final Animation<double> _headerBob;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _headerBob = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _headerController, curve: Curves.easeInOut),
    );
    _headerController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    _headerController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;

      debugPrint('=== Loading Profile ===');
      debugPrint('User: ${user?.email}');
      debugPrint('Google Photo: ${user?.photoURL}');

      // Load saved data
      final savedName = prefs.getString('name');
      final customImagePath = prefs.getString('profile_image_path');

      debugPrint('Saved Name: $savedName');
      debugPrint('Custom Image Path: $customImagePath');

      // Validate custom image path if it exists
      String? validCustomPath;
      if (customImagePath != null && customImagePath.isNotEmpty) {
        final file = File(customImagePath);
        if (await file.exists()) {
          validCustomPath = customImagePath;
          debugPrint('Custom image file exists');
        } else {
          await prefs.remove('profile_image_path');
          debugPrint('Custom image file not found, removed from preferences');
        }
      }

      // Get user data from Firebase Auth
      final email = user?.email ?? prefs.getString('email') ?? '';
      final googlePhotoUrl = user?.photoURL;

      // Generate display name
      String displayName = savedName ?? user?.displayName ?? '';
      if (displayName.isEmpty && email.isNotEmpty) {
        displayName = email.contains('@') ? email.split('@').first : email;
        if (displayName.isNotEmpty) {
          displayName = displayName[0].toUpperCase() + displayName.substring(1);
        }
      }

      // Load transaction data
      final repo = TransactionRepository();
      final rows = await repo.getAll();
      final now = DateTime.now();
      double income = 0, expense = 0;

      for (final r in rows) {
        final dt = DateTime.tryParse(r['date'] as String) ?? now;
        if (dt.year == now.year && dt.month == now.month) {
          final amt = (r['amount'] as num).toDouble();
          final type = (r['type'] as String).toLowerCase().trim();
          if (type == 'income') {
            income += amt;
          } else if (type == 'expense') {
            expense += amt;
          }
        }
      }

      // Load auto-detection settings
      await NotificationService.isAutoDetectionEnabled();
      await repo.getAutoDetectedTransactions();

      // Update UI
      if (mounted) {
        setState(() {
          _email = email;
          _nameController.text = displayName;
          _customImagePath = validCustomPath;
          _googlePhotoUrl = googlePhotoUrl;
          _totalIncome = income;
          _totalExpense = expense;
        });
        debugPrint(
          'Profile loaded - Custom: $_customImagePath, Google: $_googlePhotoUrl',
        );
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load profile: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (picked == null) return;

      debugPrint('=== Image Picked ===');
      debugPrint('Path: ${picked.path}');

      // Verify file exists
      final file = File(picked.path);
      final exists = await file.exists();
      debugPrint('File exists: $exists');

      if (exists) {
        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image_path', picked.path);

        // Verify it was saved
        final savedPath = prefs.getString('profile_image_path');
        debugPrint('Verified saved path: $savedPath');

        if (mounted) {
          setState(() => _customImagePath = picked.path);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profile picture updated successfully!'),
              backgroundColor: AppColors.secondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Picked file does not exist');
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile picture: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildProfileImage() {
    // Priority: Custom local image > Google photo > Default icon

    // 1. Show custom local image if available
    if (_customImagePath != null && _customImagePath!.isNotEmpty) {
      return CircleAvatar(
        radius: 41,
        backgroundColor: Colors.grey[100],
        backgroundImage: FileImage(File(_customImagePath!)),
        onBackgroundImageError: (exception, stackTrace) {
          debugPrint('Error loading custom image: $exception');
        },
      );
    }

    // 2. Show Google photo if available
    if (_googlePhotoUrl != null && _googlePhotoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 41,
        backgroundColor: Colors.grey[100],
        backgroundImage: NetworkImage(_googlePhotoUrl!),
        onBackgroundImageError: (exception, stackTrace) {
          debugPrint('Error loading Google photo: $exception');
        },
      );
    }

    // 3. Fallback to default icon
    return CircleAvatar(
      radius: 41,
      backgroundColor: Colors.grey[100],
      child: Icon(
        Icons.person_rounded,
        size: 42,
        color: AppColors.primary.withValues(alpha: 0.5),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', _nameController.text.trim());

    if (!mounted) return;

    setState(() => _editing = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Profile updated successfully!'),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatCurrency(double v) =>
      FormatUtils.formatCurrency(v, compact: true);

  String _todayLabel() {
    final now = DateTime.now();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final balance = _totalIncome - _totalExpense;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background image
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(AppImages.curvedBackground, fit: BoxFit.cover),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile Header Card
                    AnimatedBuilder(
                      animation: _headerBob,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _headerBob.value),
                          child: child,
                        );
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.primary.withValues(alpha: 0.85),
                                      AppColors.primary.withValues(alpha: 0.75),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  20,
                                  20,
                                  16,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Profile Image with camera button
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.white.withValues(
                                                  alpha: 0.3,
                                                ),
                                                blurRadius: 16,
                                                spreadRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            radius: 44,
                                            backgroundColor: Colors.white,
                                            child: _buildProfileImage(),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: GestureDetector(
                                            onTap: () =>
                                                _showImageSourceSheet(context),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    AppColors.secondary,
                                                    AppColors.secondary
                                                        .withValues(alpha: 0.8),
                                                  ],
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppColors.secondary
                                                        .withValues(alpha: 0.4),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: const Icon(
                                                Icons.camera_alt_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // Name field
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      child: _editing
                                          ? Container(
                                              key: const ValueKey('editing'),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.3),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: TextField(
                                                controller: _nameController,
                                                focusNode: _nameFocus,
                                                textAlign: TextAlign.center,
                                                decoration:
                                                    const InputDecoration(
                                                      border: InputBorder.none,
                                                      hintText:
                                                          'Enter your name',
                                                      hintStyle: TextStyle(
                                                        color: Colors.white60,
                                                        fontSize: 20,
                                                      ),
                                                    ),
                                                textInputAction:
                                                    TextInputAction.done,
                                                onSubmitted: (_) =>
                                                    _saveProfile(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              key: const ValueKey('display'),
                                              _nameController.text.isEmpty
                                                  ? 'Tap edit to add name'
                                                  : _nameController.text,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.2),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                    ),

                                    const SizedBox(height: 6),

                                    // Email
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.email_rounded,
                                            color: Colors.white70,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              _email,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Edit button
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  if (_editing) {
                                    FocusScope.of(context).unfocus();
                                    _saveProfile();
                                  } else {
                                    setState(() => _editing = true);
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () {
                                        if (mounted) _nameFocus.requestFocus();
                                      },
                                    );
                                  }
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    _editing
                                        ? Icons.check_rounded
                                        : Icons.edit_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Balance card
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary,
                            AppColors.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Current Balance',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatCurrency(balance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _modernTotalCard(
                            label: 'Income',
                            value: _formatCurrency(_totalIncome),
                            color: AppColors.income,
                            icon: Icons.trending_up_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _modernTotalCard(
                            label: 'Expense',
                            value: _formatCurrency(_totalExpense),
                            color: AppColors.expense,
                            icon: Icons.trending_down_rounded,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Compact Lottie
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _lottieTapEpoch += 1;
                          _moneyLottieDy = (_moneyLottieDy + 15).clamp(0, 120);
                          _moneyLottieScale = (_moneyLottieScale + 0.08).clamp(
                            1.0,
                            1.4,
                          );
                        });
                        final epoch = _lottieTapEpoch;
                        Future.delayed(const Duration(milliseconds: 600), () {
                          if (!mounted) return;
                          if (epoch == _lottieTapEpoch) {
                            setState(() {
                              _moneyLottieDy = 0;
                              _moneyLottieScale = 1.0;
                            });
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        transform: Matrix4.translationValues(
                          0,
                          -_moneyLottieDy,
                          0,
                        ),
                        child: AnimatedScale(
                          scale: _moneyLottieScale,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          child: SizedBox(
                            height: 100,
                            child: Lottie.asset(
                              'assets/lottie/jsonlottie/Moneylottie.json',
                              fit: BoxFit.contain,
                              repeat: true,
                              animate: true,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _todayLabel(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernTotalCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showImageSourceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Choose Image Source',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _pickSourceButton(
                        icon: Icons.photo_camera_rounded,
                        label: 'Camera',
                        color: AppColors.secondary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(ImageSource.camera);
                        },
                      ),
                      _pickSourceButton(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        color: AppColors.primary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(ImageSource.gallery);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pickSourceButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
