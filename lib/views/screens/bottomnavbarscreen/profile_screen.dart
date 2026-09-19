// ProfileScreen — Shows Google photo if available, or styled first letter avatar.
// No image upload. Premium glassmorphism design.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/images.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/notification_service.dart';
import 'package:buddy/services/theme_service.dart';
import 'package:buddy/services/feedback_service.dart';

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
  String? _googlePhotoUrl;
  bool _editing = false;
  double _totalIncome = 0;
  double _totalExpense = 0;
  String _topCategory = '-';
  DateTime? _memberSince;
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
    _headerBob = Tween<double>(begin: -4.0, end: 4.0).animate(
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
      final user = FirebaseAuth.instance.currentUser;

      // 1. Load basic info instantly from Auth / fast sources
      final email = user?.email ?? '';
      final googlePhotoUrl = user?.photoURL;
      final memberSince = user?.metadata.creationTime;

      // Check SharedPreferences for local name override
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('name');
      final savedEmail = prefs.getString('email') ?? '';

      String displayName = savedName ?? user?.displayName ?? '';
      final finalEmail = email.isNotEmpty ? email : savedEmail;
      if (displayName.isEmpty && finalEmail.isNotEmpty) {
        displayName = finalEmail.contains('@') ? finalEmail.split('@').first : finalEmail;
        if (displayName.isNotEmpty) {
          displayName = displayName[0].toUpperCase() + displayName.substring(1);
        }
      }

      if (mounted) {
        setState(() {
          _email = finalEmail;
          _nameController.text = displayName;
          _googlePhotoUrl = googlePhotoUrl;
          _memberSince = memberSince;
        });
      }

      // 2. Load heavy Firestore statistics in the background asynchronously
      _loadFirestoreStats();
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadFirestoreStats() async {
    try {
      final now = DateTime.now();
      double income = 0, expense = 0;
      String topCat = '-';

      final totals = await FirestoreService.instance.getMonthlyTotals(
        now.year,
        now.month,
      );
      income = totals['income'] ?? 0;
      expense = totals['expense'] ?? 0;

      // Get all transactions for stats
      final allTxns = await FirestoreService.instance.getAllTransactions();

      // Find top category
      final catCounts = <String, int>{};
      for (final t in allTxns) {
        catCounts[t.category] = (catCounts[t.category] ?? 0) + 1;
      }
      if (catCounts.isNotEmpty) {
        final sorted = catCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        topCat = sorted.first.key;
      }

      // Load auto-detection settings in background too
      await NotificationService.isAutoDetectionEnabled();

      if (mounted) {
        setState(() {
          _totalIncome = income;
          _totalExpense = expense;
          _topCategory = topCat;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error loading Firestore stats on profile: $e');
    }
  }

  // Gradient color based on first letter for non-Google users
  List<Color> _getAvatarGradient() {
    final name = _nameController.text;
    if (name.isEmpty) {
      return [const Color(0xFF667eea), const Color(0xFF764ba2)];
    }
    final charCode = name.codeUnitAt(0);
    final gradients = [
      [const Color(0xFF667eea), const Color(0xFF764ba2)],
      [const Color(0xFFf093fb), const Color(0xFFf5576c)],
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
      [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
      [const Color(0xFFfa709a), const Color(0xFFfee140)],
      [const Color(0xFF6a11cb), const Color(0xFF2575fc)],
      [const Color(0xFFff9a9e), const Color(0xFFfecfef)],
      [const Color(0xFFa18cd1), const Color(0xFFfbc2eb)],
    ];
    return gradients[charCode % gradients.length];
  }

  Widget _buildProfileImage() {
    // 1. Show Google photo if available
    if (_googlePhotoUrl != null && _googlePhotoUrl!.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: CircleAvatar(
          radius: 44,
          backgroundColor: Colors.white,
          child: CircleAvatar(
            radius: 41,
            backgroundColor: Colors.grey[100],
            backgroundImage: NetworkImage(_googlePhotoUrl!),
            onBackgroundImageError: (exception, stackTrace) {
              debugPrint('Error loading Google photo: $exception');
            },
          ),
        ),
      );
    }

    // 2. Styled first letter avatar
    final name = _nameController.text;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final gradient = _getAvatarGradient();

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: gradient[0].withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 44,
        backgroundColor: Colors.white,
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Text(
              letter,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  String _memberSinceLabel() {
    if (_memberSince == null) return '';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[_memberSince!.month - 1]} ${_memberSince!.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final balance = _totalIncome - _totalExpense;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
        children: [
          // Background image with dark mode dimming
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: isDark ? 0.25 : 1.0,
              child: Image.asset(AppImages.curvedBackground, fit: BoxFit.cover),
            ),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Profile Header Card ──
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
                                      AppColors.primary.withValues(alpha: 0.9),
                                      AppColors.secondary.withValues(alpha: 0.85),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: 0.35),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Profile Image
                                    _buildProfileImage(),

                                    const SizedBox(height: 14),

                                    // Name field
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      child: _editing
                                          ? Container(
                                              key: const ValueKey('editing'),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.white.withValues(alpha: 0.3),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: TextField(
                                                controller: _nameController,
                                                focusNode: _nameFocus,
                                                textAlign: TextAlign.center,
                                                decoration: const InputDecoration(
                                                  border: InputBorder.none,
                                                  hintText: 'Enter your name',
                                                  hintStyle: TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 20,
                                                  ),
                                                ),
                                                textInputAction: TextInputAction.done,
                                                onSubmitted: (_) => _saveProfile(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              key: const ValueKey('display'),
                                              _nameController.text.isEmpty
                                                  ? 'Tap edit to add name'
                                                  : _nameController.text,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                    ),

                                    const SizedBox(height: 8),

                                    // Email badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.email_rounded,
                                            color: Colors.white70,
                                            size: 13,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              _email,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Member since
                                    if (_memberSince != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Member since ${_memberSinceLabel()}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Edit button
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
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
                                      color: Colors.white.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    _editing
                                        ? Icons.check_rounded
                                        : Icons.edit_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Balance Card ──
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1E5D57),
                            Color(0xFF3B8E85),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E5D57).withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 24,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'CURRENT BALANCE',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'This Month',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatCurrency(balance),
                            style: TextStyle(
                              color: balance >= 0 ? Colors.white : Colors.red.shade300,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Income / Expense Cards ──
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            label: 'Income',
                            value: _formatCurrency(_totalIncome),
                            color: AppColors.income,
                            icon: Icons.trending_up_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            label: 'Expense',
                            value: _formatCurrency(_totalExpense),
                            color: AppColors.expense,
                            icon: Icons.trending_down_rounded,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Quick Stats ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                        boxShadow: AppColors.cardShadowOf(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppColors.primary, AppColors.secondary],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Quick Stats',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildQuickStatItem(
                                  icon: Icons.category_rounded,
                                  label: 'Top Category',
                                  value: _topCategory,
                                  color: const Color(0xFFFF7043),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: AppColors.borderOf(context),
                              ),
                              Expanded(
                                child: _buildQuickStatItem(
                                  icon: Icons.savings_rounded,
                                  label: 'Savings',
                                  value: balance >= 0 ? _formatCurrency(balance) : '-${_formatCurrency(balance.abs())}',
                                  color: balance >= 0 ? AppColors.income : AppColors.expense,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Appearance / Theme Card ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                        boxShadow: AppColors.cardShadowOf(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Appearance',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Dark Mode Switch Row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (isDark ? Colors.amber : AppColors.primary).withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                  color: isDark ? Colors.amber : AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Dark Mode',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimaryOf(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isDark ? 'Dark theme active' : 'Light theme active',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondaryOf(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isDark,
                                onChanged: (val) => ThemeService.toggleTheme(context),
                                activeThumbColor: AppColors.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // 3-way Mode Selector
                          ValueListenableBuilder<ThemeMode>(
                            valueListenable: ThemeService.themeModeNotifier,
                            builder: (context, currentMode, _) {
                              return Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF161C23) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.borderOf(context)),
                                ),
                                child: Row(
                                  children: [
                                    _buildThemeChip('System', Icons.brightness_auto_rounded, currentMode == ThemeMode.system, () => ThemeService.setThemeMode(ThemeMode.system)),
                                    _buildThemeChip('Light', Icons.light_mode_rounded, currentMode == ThemeMode.light, () => ThemeService.setThemeMode(ThemeMode.light)),
                                    _buildThemeChip('Dark', Icons.dark_mode_rounded, currentMode == ThemeMode.dark, () => ThemeService.setThemeMode(ThemeMode.dark)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Support & Developer Feedback Card ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                        boxShadow: AppColors.cardShadowOf(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF9966), Color(0xFFFF5E62)],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Support & Feedback',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Report a Bug Tile
                          _buildProfileFeedbackTile(
                            icon: Icons.bug_report_rounded,
                            title: 'Report a Bug',
                            subtitle: 'Found an issue? Mail dev with details',
                            color: const Color(0xFFFF7043),
                            onTap: () => FeedbackService.reportBug(context),
                          ),
                          const SizedBox(height: 10),
                          // Request a Feature Tile
                          _buildProfileFeedbackTile(
                            icon: Icons.lightbulb_rounded,
                            title: 'Request a Feature',
                            subtitle: 'Suggest features to faysarukattil@gmail.com',
                            color: const Color(0xFF7C4DFF),
                            onTap: () => FeedbackService.requestFeature(context),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Lottie Animation ──
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.lightImpact();
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
                            height: 90,
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

                    const SizedBox(height: 8),

                    // ── Date pill ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.5),
                        ),
                        boxShadow: AppColors.cardShadowOf(context),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _todayLabel(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
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

  Widget _buildThemeChip(
    String title,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final isDark = AppColors.isDark(context);
    final activeBg = isDark ? const Color(0xFF263342) : Colors.white;
    final activeText = isDark ? Colors.white : AppColors.textPrimary;
    final inactiveText = isDark ? Colors.white60 : Colors.grey.shade600;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.primary : inactiveText,
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeText : inactiveText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileFeedbackTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondaryOf(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stat Card (Income/Expense) ──
  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Quick Stat Item ──
  Widget _buildQuickStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondaryOf(context),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
