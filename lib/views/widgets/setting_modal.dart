// lib/views/widgets/settings_modal.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:buddy/services/notification_service.dart';
import 'package:buddy/services/notification_helper.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/theme_service.dart';
import 'package:buddy/services/feedback_service.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/onboarding/login_screen.dart';

class SettingsModal extends StatefulWidget {
  final VoidCallback onDataCleared;

  const SettingsModal({super.key, required this.onDataCleared});

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  bool _autoDetectionEnabled = false;
  bool _isLoading = true;
  bool _isAccountActionLoading = false;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final enabled = await NotificationService.isAutoDetectionEnabled();
      if (mounted) {
        setState(() {
          _autoDetectionEnabled = enabled;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading settings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleAutoDetection(bool value) async {
    setState(() => _isLoading = true);

    try {
      if (value) {
        await NotificationHelper.requestNotificationPermission();
        final hasAccess = await NotificationService.requestNotificationAccess();

        if (!hasAccess) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️ Please grant notification access in settings',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));
          final recheckAccess =
              await NotificationService.requestNotificationAccess();
          if (!recheckAccess) {
            setState(() => _isLoading = false);
            return;
          }
        }

        await NotificationService.setAutoDetectionEnabled(true);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Auto-detection enabled successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        await NotificationService.setAutoDetectionEnabled(false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Auto-detection disabled'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }

      await _loadSettings();
    } catch (e) {
      debugPrint('❌ Error toggling auto-detection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearTodayData() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear Today\'s Data?',
      message:
          'This will delete all transactions from today. This cannot be undone.',
    );

    if (!confirmed) return;

    try {
      final firestore = FirestoreService.instance;
      final txns = await firestore.getAllTransactions();
      final today = DateTime.now();
      int deletedCount = 0;

      for (final txn in txns) {
        if (txn.date.year == today.year &&
            txn.date.month == today.month &&
            txn.date.day == today.day) {
          await firestore.deleteTransaction(txn.id!);
          deletedCount++;
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      widget.onDataCleared();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Deleted $deletedCount transaction(s) from today'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearThisMonthData() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear This Month\'s Data?',
      message:
          'This will delete all transactions from this month. This cannot be undone.',
    );

    if (!confirmed) return;

    try {
      final firestore = FirestoreService.instance;
      final txns = await firestore.getAllTransactions();
      final now = DateTime.now();
      int deletedCount = 0;

      for (final txn in txns) {
        if (txn.date.year == now.year && txn.date.month == now.month) {
          await firestore.deleteTransaction(txn.id!);
          deletedCount++;
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      widget.onDataCleared();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Deleted $deletedCount transaction(s) from this month'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear All Data?',
      message:
          'This will delete ALL transactions permanently. This cannot be undone.',
      isDangerous: true,
    );

    if (!confirmed) return;

    try {
      await FirestoreService.instance.clearAllData();

      if (!mounted) return;

      Navigator.pop(context);
      widget.onDataCleared();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ All data cleared'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Logout ──

  Future<void> _handleLogout() async {
    final confirmed = await _showConfirmDialog(
      title: 'Log Out?',
      message: 'You will need to sign in again to access your data.',
    );

    if (!confirmed) return;

    setState(() => _isAccountActionLoading = true);

    try {
      await _authService.signOut();

      if (!mounted) return;

      // Navigate to login and clear all routes
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAccountActionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  // ── Delete Account (2-step) ──

  Future<void> _handleDeleteAccount() async {
    // Step 1: First confirmation
    final firstConfirm = await _showConfirmDialog(
      title: 'Delete Account?',
      message:
          'This will permanently delete your account and ALL your data '
          '(transactions, categories, settings). This action CANNOT be undone.',
      isDangerous: true,
    );

    if (!firstConfirm || !mounted) return;

    // Step 2: Type "DELETE" confirmation
    final secondConfirm = await _showTypeToConfirmDialog();

    if (!secondConfirm || !mounted) return;

    setState(() => _isAccountActionLoading = true);

    try {
      await _authService.deleteAccount();

      if (!mounted) return;

      // Navigate to login and clear all routes
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account deleted successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAccountActionLoading = false);

      if (e.toString() == 'requires-recent-login') {
        // Handle re-authentication requirement
        await _handleReauthAndDelete();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleReauthAndDelete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final providers = user.providerData.map((p) => p.providerId).toList();

    if (providers.contains('google.com')) {
      // Google re-auth: just trigger Google sign-in again
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please sign in with Google again to confirm deletion'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      final success = await _authService.reauthenticate();
      if (success && mounted) {
        setState(() => _isAccountActionLoading = true);
        try {
          await _authService.deleteAccount();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        } catch (e) {
          if (mounted) {
            setState(() => _isAccountActionLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } else if (providers.contains('password')) {
      // Email/password re-auth: show password dialog
      if (!mounted) return;
      final password = await _showPasswordDialog();
      if (password == null || !mounted) return;

      final success = await _authService.reauthenticate(
        email: user.email,
        password: password,
      );
      if (success && mounted) {
        setState(() => _isAccountActionLoading = true);
        try {
          await _authService.deleteAccount();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        } catch (e) {
          if (mounted) {
            setState(() => _isAccountActionLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Incorrect password. Account not deleted.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } else if (user.isAnonymous) {
      // Guest accounts can be deleted directly
      try {
        await _authService.deleteAccount();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // ── Dialogs ──

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: AppColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondaryOf(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: isDangerous ? Colors.red : AppColors.primary,
            ),
            child: Text(isDangerous ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<bool> _showTypeToConfirmDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isValid = controller.text.trim().toUpperCase() == 'DELETE';
            return AlertDialog(
              backgroundColor: AppColors.cardOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Final Confirmation',
                      style: TextStyle(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type DELETE to permanently remove your account and all data.',
                    style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setDialogState(() {}),
                    style: TextStyle(
                      color: AppColors.textPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                    decoration: InputDecoration(
                      hintText: 'DELETE',
                      hintStyle: TextStyle(
                        color: AppColors.textLightOf(context),
                        letterSpacing: 2,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isValid ? Colors.red : AppColors.borderOf(context),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: controller.text.isNotEmpty && !isValid
                              ? Colors.orange
                              : AppColors.borderOf(context),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isValid ? Colors.red : AppColors.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondaryOf(context)),
                  ),
                ),
                TextButton(
                  onPressed: isValid ? () => Navigator.pop(context, true) : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    disabledForegroundColor: Colors.red.withValues(alpha: 0.3),
                  ),
                  child: const Text('Delete Forever'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result ?? false;
  }

  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    bool obscure = true;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Re-enter Password',
                style: TextStyle(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'For security, please re-enter your password to confirm account deletion.',
                    style: TextStyle(
                      color: AppColors.textSecondaryOf(context),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    style: TextStyle(color: AppColors.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: TextStyle(color: AppColors.textLightOf(context)),
                      filled: true,
                      fillColor: AppColors.surfaceOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.borderOf(context)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondaryOf(context)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = AppColors.cardOf(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final borderColor = AppColors.borderOf(context);
    final isDark = AppColors.isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Row(
                  children: [
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Appearance Section ──
                Text(
                  'Appearance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeService.themeModeNotifier,
                  builder: (context, currentMode, _) {
                    return Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF161C23)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          _buildThemeOption(
                            title: 'System',
                            icon: Icons.brightness_auto_rounded,
                            isSelected: currentMode == ThemeMode.system,
                            onTap: () =>
                                ThemeService.setThemeMode(ThemeMode.system),
                          ),
                          _buildThemeOption(
                            title: 'Light',
                            icon: Icons.light_mode_rounded,
                            isSelected: currentMode == ThemeMode.light,
                            onTap: () =>
                                ThemeService.setThemeMode(ThemeMode.light),
                          ),
                          _buildThemeOption(
                            title: 'Dark',
                            icon: Icons.dark_mode_rounded,
                            isSelected: currentMode == ThemeMode.dark,
                            onTap: () =>
                                ThemeService.setThemeMode(ThemeMode.dark),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 28),

                // ── Auto-Detection Section ──
                Text(
                  'Auto Transaction Detection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Auto-Detection Toggle
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2631) : Colors.white,
                    border: Border.all(
                      color: _autoDetectionEnabled
                          ? AppColors.primary.withValues(alpha: .5)
                          : borderColor,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-Detect Transactions',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Automatically add from SMS / bank notifications',
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isLoading)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Switch(
                          value: _autoDetectionEnabled,
                          onChanged: _toggleAutoDetection,
                          activeThumbColor: AppColors.primary,
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Support & Feedback Section ──
                Text(
                  'Support & Feedback',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Report a Bug
                _buildActionTile(
                  icon: Icons.bug_report_rounded,
                  title: 'Report a Bug',
                  subtitle: 'Found an issue? Mail developer directly',
                  color: const Color(0xFFFF7043),
                  onTap: () => FeedbackService.reportBug(context),
                ),
                const SizedBox(height: 12),

                // Request a Feature
                _buildActionTile(
                  icon: Icons.lightbulb_rounded,
                  title: 'Request a Feature',
                  subtitle: 'Suggest new features to faysarukattil@gmail.com',
                  color: const Color(0xFF7C4DFF),
                  onTap: () => FeedbackService.requestFeature(context),
                ),

                const SizedBox(height: 28),

                // ── Data Management Section ──
                Text(
                  'Data Management',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Clear Today's Data
                _buildActionTile(
                  icon: Icons.today_rounded,
                  title: 'Clear Today\'s Data',
                  subtitle: 'Delete all transactions from today',
                  color: Colors.blueAccent,
                  onTap: _clearTodayData,
                ),
                const SizedBox(height: 12),

                // Clear This Month's Data
                _buildActionTile(
                  icon: Icons.calendar_month_rounded,
                  title: 'Clear This Month',
                  subtitle: 'Delete all transactions from this month',
                  color: Colors.orangeAccent,
                  onTap: _clearThisMonthData,
                ),
                const SizedBox(height: 12),

                // Clear All Data
                _buildActionTile(
                  icon: Icons.delete_forever_rounded,
                  title: 'Clear All Data',
                  subtitle: 'Delete ALL transactions permanently',
                  color: Colors.redAccent,
                  onTap: _clearAllData,
                  isDangerous: true,
                ),

                const SizedBox(height: 28),

                // ── Account Section ──
                Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Logout
                _buildActionTile(
                  icon: Icons.logout_rounded,
                  title: 'Log Out',
                  subtitle: 'Sign out of your account',
                  color: const Color(0xFF546E7A),
                  onTap: _isAccountActionLoading ? () {} : _handleLogout,
                ),
                const SizedBox(height: 12),

                // Delete Account
                _buildActionTile(
                  icon: Icons.person_remove_rounded,
                  title: 'Delete Account',
                  subtitle: 'Permanently delete account & all data',
                  color: const Color(0xFFD32F2F),
                  onTap: _isAccountActionLoading ? () {} : _handleDeleteAccount,
                  isDangerous: true,
                ),

                // Loading overlay for account actions
                if (_isAccountActionLoading) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E2631)
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Processing... Please wait.',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── App Version ──
                Center(
                  child: Text(
                    'Buddy v1.0.0',
                    style: TextStyle(
                      fontSize: 12,
                      color: textSecondary.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
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
                size: 17,
                color: isSelected ? AppColors.primary : inactiveText,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
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

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isDangerous = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDangerous ? color : AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}
