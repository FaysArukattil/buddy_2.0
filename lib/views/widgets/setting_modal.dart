// lib/views/widgets/setting_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:buddy/services/notification_service.dart';
import 'package:buddy/services/notification_helper.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/theme_service.dart';
import 'package:buddy/services/feedback_service.dart';
import 'package:buddy/services/support_service.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/onboarding/login_screen.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/services/preference_service.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class SettingsModal extends StatefulWidget {
  final VoidCallback onDataCleared;

  const SettingsModal({super.key, required this.onDataCleared});

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  bool _autoDetectionEnabled = false;
  bool _includeDebtsInBalance = true;
  bool _isLoading = true;
  bool _isToggling = false; // Prevents rapid-fire toggle spam
  bool _isAccountActionLoading = false;
  String _accountActionMessage = 'Please wait...';
  String _appVersion = 'v1.0.0';
  final AuthService _authService = AuthService();
  final Set<String> _expandedSections = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final enabled = await NotificationService.isAutoDetectionEnabled();
      final hasAccess = await NotificationService.isNotificationAccessGranted();
      final includeDebts = PreferenceService.includeDebtsInHome;
      final versionStr = await FeedbackService.getAppVersionDisplay();
      if (mounted) {
        setState(() {
          _autoDetectionEnabled = enabled && hasAccess;
          _includeDebtsInBalance = includeDebts;
          _appVersion = versionStr;
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

  Future<void> _toggleIncludeDebts(bool value) async {
    await PreferenceService.setIncludeDebtsInHome(value);
    if (mounted) {
      setState(() => _includeDebtsInBalance = value);
      widget.onDataCleared();
    }
  }

  Future<void> _toggleAutoDetection(bool value) async {
    // Prevent rapid-fire toggling (fixes repeated snackbar on Nothing/Vivo)
    if (_isToggling) return;
    _isToggling = true;

    setState(() => _isLoading = true);

    // Clear any existing snackbars first
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    try {
      if (value) {
        // Request notification posting permission (Android 13+)
        await NotificationHelper.requestNotificationPermission();

        // Check if notification listener access is already granted
        final hasAccess = await NotificationService.isNotificationAccessGranted();

        if (!hasAccess) {
          // Open settings — DON'T show snackbar repeatedly
          NotificationService.awaitingPermissionReturn = true;
          await NotificationService.requestNotificationAccess();

          if (!mounted) {
            _isToggling = false;
            return;
          }

          // Show a single informative snackbar
          AppSnackbar.showWarning(
            context,
            'Enable "Buddy" in notification access settings, then come back',
            duration: const Duration(seconds: 4),
          );

          setState(() => _isLoading = false);
          _isToggling = false;
          return;
        }

        // Access is granted — enable auto-detection
        await NotificationService.setAutoDetectionEnabled(true);

        if (!mounted) {
          _isToggling = false;
          return;
        }

        setState(() {
          _autoDetectionEnabled = true;
          _isLoading = false;
        });

        AppSnackbar.showSuccess(context, 'Auto-detection enabled!');
      } else {
        await NotificationService.setAutoDetectionEnabled(false);

        if (!mounted) {
          _isToggling = false;
          return;
        }

        setState(() {
          _autoDetectionEnabled = false;
          _isLoading = false;
        });

        AppSnackbar.showInfo(context, 'Auto-detection disabled');
      }
    } catch (e) {
      debugPrint('❌ Error toggling auto-detection: $e');
      if (mounted) {
        AppSnackbar.showError(context, 'Error: $e');
        setState(() => _isLoading = false);
      }
    } finally {
      // Reset debounce after a short delay
      Future.delayed(const Duration(milliseconds: 800), () {
        _isToggling = false;
      });
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

      AppSnackbar.showSuccess(
        context,
        'Deleted $deletedCount transaction(s) from today',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Error: $e');
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

      AppSnackbar.showSuccess(
        context,
        'Deleted $deletedCount transaction(s) from this month',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Error: $e');
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

      AppSnackbar.showSuccess(context, 'All data cleared');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Error: $e');
    }
  }

  // ── Logout ──

  Future<void> _handleLogout() async {
    final confirmed = await _showConfirmDialog(
      title: 'Log Out?',
      message: 'You will need to sign in again to access your data.',
    );

    if (!confirmed) return;

    setState(() {
      _isAccountActionLoading = true;
      _accountActionMessage = 'Logging out...';
    });

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
      AppSnackbar.showError(context, 'Error: $e');
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

    setState(() {
      _isAccountActionLoading = true;
      _accountActionMessage = 'Deleting account...';
    });

    try {
      await _authService.deleteAccount();

      if (!mounted) return;

      // Navigate to login and clear all routes
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

      AppSnackbar.showSuccess(context, 'Account deleted successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAccountActionLoading = false);

      if (e.toString() == 'requires-recent-login') {
        // Handle re-authentication requirement
        await _handleReauthAndDelete();
      } else {
        AppSnackbar.showError(context, 'Error: $e');
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
      AppSnackbar.showWarning(
        context,
        'Please sign in with Google again to confirm deletion',
      );

      final success = await _authService.reauthenticate();
      if (success && mounted) {
        setState(() {
          _isAccountActionLoading = true;
          _accountActionMessage = 'Deleting account...';
        });
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
            AppSnackbar.showError(context, 'Error: $e');
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
        setState(() {
          _isAccountActionLoading = true;
          _accountActionMessage = 'Deleting account...';
        });
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
            AppSnackbar.showError(context, 'Error: $e');
          }
        }
      } else if (mounted) {
        AppSnackbar.showError(
          context,
          'Incorrect password. Account not deleted.',
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
          AppSnackbar.showError(context, 'Error: $e');
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
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    style: TextStyle(
                      color: AppColors.textPrimaryOf(context),
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Password',
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

  // ── BUILD UI ──

  @override
  Widget build(BuildContext context) {
    final cardBg = AppColors.cardOf(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final borderColor = AppColors.borderOf(context).withValues(alpha: 0.6);
    final isDark = AppColors.isDark(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.90;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 14.0, 20.0, 28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Frosted Drag Handle
                    Center(
                      child: Container(
                        width: 42,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.grey[300],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Top Header Bar
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Settings & Preferences',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Manage appearance, data, and tracking',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: cardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: borderColor),
                            ),
                          ),
                          icon: Icon(Icons.close_rounded,
                              color: textSecondary, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // ── 1. APPEARANCE & THEME TILE ──
                    _buildExpandableTile(
                      id: 'appearance',
                      icon: Icons.palette_outlined,
                      title: 'Appearance & Theme',
                      badge: ValueListenableBuilder<ThemeMode>(
                        valueListenable: ThemeService.themeModeNotifier,
                        builder: (context, currentMode, _) {
                          final label = currentMode == ThemeMode.system
                              ? 'System'
                              : currentMode == ThemeMode.light
                                  ? 'Light'
                                  : 'Dark';
                          return _buildBadge(label);
                        },
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: ValueListenableBuilder<ThemeMode>(
                            valueListenable: ThemeService.themeModeNotifier,
                            builder: (context, currentMode, _) {
                              return Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF161C23)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    _buildThemeOption(
                                      title: 'System',
                                      icon: Icons.brightness_auto_rounded,
                                      isSelected: currentMode == ThemeMode.system,
                                      onTap: () => ThemeService.setThemeMode(
                                          ThemeMode.system),
                                    ),
                                    _buildThemeOption(
                                      title: 'Light',
                                      icon: Icons.light_mode_rounded,
                                      isSelected: currentMode == ThemeMode.light,
                                      onTap: () => ThemeService.setThemeMode(
                                          ThemeMode.light),
                                    ),
                                    _buildThemeOption(
                                      title: 'Dark',
                                      icon: Icons.dark_mode_rounded,
                                      isSelected: currentMode == ThemeMode.dark,
                                      onTap: () => ThemeService.setThemeMode(
                                          ThemeMode.dark),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        Divider(height: 1, color: borderColor),
                        _buildSwitchRow(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Reflect Debts in Home',
                          subtitle: _includeDebtsInBalance
                              ? 'Included in net balance'
                              : 'Excluded from net balance',
                          value: _includeDebtsInBalance,
                          onChanged: _toggleIncludeDebts,
                        ),
                      ],
                    ),

                    // ── 2. SMART AUTO-DETECTION TILE ──
                    _buildExpandableTile(
                      id: 'auto_detection',
                      icon: Icons.notifications_active_outlined,
                      title: 'Smart Auto-Detection',
                      badge: _buildBadge(
                        _autoDetectionEnabled ? 'Active' : 'Off',
                        color: _autoDetectionEnabled
                            ? (isDark
                                ? const Color(0xFF064E3B)
                                : const Color(0xFFE8F5E9))
                            : null,
                        textColor: _autoDetectionEnabled
                            ? const Color(0xFF10B981)
                            : null,
                      ),
                      children: [
                        _buildSwitchRow(
                          icon: Icons.sms_outlined,
                          title: 'Track Bank SMS',
                          subtitle: 'Auto-record incoming transactions',
                          value: _autoDetectionEnabled,
                          isLoading: _isLoading,
                          onChanged: _toggleAutoDetection,
                        ),
                        if (_autoDetectionEnabled) ...[
                          Divider(height: 1, color: borderColor),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified_user_outlined,
                                  size: 13,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'DEVICE OPTIMIZATIONS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: textSecondary,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildSubOptionTile(
                            icon: Icons.battery_charging_full_rounded,
                            title: 'Disable Battery Optimization',
                            subtitle: 'Keeps detection reliable in background',
                            onTap: () => NotificationService
                                .openBatteryOptimizationSettings(),
                          ),
                          _buildSubOptionTile(
                            icon: Icons.rocket_launch_outlined,
                            title: 'Enable Autostart Access',
                            subtitle:
                                'Required on Vivo, Xiaomi, Oppo & Samsung',
                            onTap: () =>
                                NotificationService.openAutoStartSettings(),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],
                    ),

                    // ── 3. DATA MANAGEMENT TILE ──
                    _buildExpandableTile(
                      id: 'data',
                      icon: Icons.storage_rounded,
                      title: 'Data Management',
                      badge: _buildBadge('Storage'),
                      children: [
                        _buildActionRow(
                          icon: Icons.today_rounded,
                          title: 'Clear Today\'s Data',
                          subtitle: 'Delete records logged today only',
                          onTap: _clearTodayData,
                        ),
                        Divider(height: 1, color: borderColor),
                        _buildActionRow(
                          icon: Icons.calendar_month_rounded,
                          title: 'Clear This Month',
                          subtitle: 'Delete records logged this month',
                          onTap: _clearThisMonthData,
                        ),
                        Divider(height: 1, color: borderColor),
                        _buildActionRow(
                          icon: Icons.delete_forever_rounded,
                          title: 'Clear All Data',
                          subtitle: 'Permanently wipe all transaction records',
                          isDangerous: true,
                          onTap: _clearAllData,
                        ),
                      ],
                    ),

                    // ── 4. SUPPORT & COMMUNITY TILE ──
                    _buildExpandableTile(
                      id: 'support',
                      icon: Icons.favorite_border_rounded,
                      title: 'Support & Community',
                      badge: _buildBadge('Feedback'),
                      children: [
                        _buildActionRow(
                          icon: Icons.star_outline_rounded,
                          iconColor: const Color(0xFFFFB300),
                          title: 'Rate on Google Play',
                          subtitle: 'Share a review & rating on Play Store',
                          onTap: () => FeedbackService.openPlayStore(context),
                        ),
                        Divider(height: 1, color: borderColor),
                        _buildActionRow(
                          icon: Icons.bug_report_outlined,
                          title: 'Report a Bug',
                          subtitle: 'Email diagnostics directly to developer',
                          onTap: () => FeedbackService.reportBug(context),
                        ),
                        Divider(height: 1, color: borderColor),
                        _buildActionRow(
                          icon: Icons.lightbulb_outline_rounded,
                          title: 'Request a Feature',
                          subtitle: 'Share your ideas to improve Buddy',
                          onTap: () => FeedbackService.requestFeature(context),
                        ),
                        Divider(height: 1, color: borderColor),
                        _buildActionRow(
                          icon: Icons.local_cafe_outlined,
                          iconColor: const Color(0xFFFF9800),
                          title: 'Buy Me a Chai ☕',
                          subtitle: 'Support development at buymeachai.in',
                          onTap: () => SupportService.openBuyMeChai(context),
                        ),
                      ],
                    ),

                    // ── 5. ACCOUNT & SECURITY TILE ──
                    _buildExpandableTile(
                      id: 'account',
                      icon: Icons.person_outline_rounded,
                      title: 'Account & Security',
                      badge: _buildBadge('Profile'),
                      children: [
                        _buildUserProfileCard(),
                        Divider(height: 1, color: borderColor),
                        _buildActionRow(
                          icon: Icons.logout_rounded,
                          title: 'Sign Out',
                          subtitle: 'Safely sign out of your account',
                          onTap: _isAccountActionLoading ? () {} : _handleLogout,
                        ),
                        Divider(height: 1, color: borderColor),
                        _buildActionRow(
                          icon: Icons.person_remove_outlined,
                          title: 'Delete Account',
                          subtitle: 'Permanently remove account & cloud data',
                          isDangerous: true,
                          onTap: _isAccountActionLoading
                              ? () {}
                              : _handleDeleteAccount,
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // App Version Display
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Buddy $_appVersion',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Crafted for effortless personal finance',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: textSecondary.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),

          // Loading Overlay during account delete/logout
          if (_isAccountActionLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 26),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2631) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BuddyLoadingIndicator(size: 72),
                        const SizedBox(height: 16),
                        Text(
                          _accountActionMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Please wait a moment...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Helper UI Components ──

  /// Clean expanding category tile with butter-smooth animation
  Widget _buildExpandableTile({
    required String id,
    required IconData icon,
    required String title,
    required Widget badge,
    required List<Widget> children,
  }) {
    final isExpanded = _expandedSections.contains(id);
    final cardBg = AppColors.cardOf(context);
    final borderColor = isExpanded
        ? AppColors.primary.withValues(alpha: 0.40)
        : AppColors.borderOf(context).withValues(alpha: 0.55);

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: isExpanded ? 1.4 : 1.1,
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (isExpanded) {
                    _expandedSections.remove(id);
                  } else {
                    _expandedSections.add(id);
                  }
                });
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    badge,
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0.0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryOf(context),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanding Children Container
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.borderOf(context)
                            .withValues(alpha: 0.45),
                      ),
                      ...children,
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Compact, elegant capsule badge
  Widget _buildBadge(String text, {Color? color, Color? textColor}) {
    final isDark = AppColors.isDark(context);
    final bg = color ??
        (isDark ? const Color(0xFF1E2631) : const Color(0xFFF1F5F9));
    final fg = textColor ?? AppColors.textSecondaryOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  /// Sub-option Switch row
  Widget _buildSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 1.5),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: BuddyLoadingIndicator(size: 20),
            )
          else
            Switch.adaptive(
              value: value,
              onChanged: (v) {
                HapticFeedback.lightImpact();
                onChanged(v);
              },
              activeTrackColor: AppColors.primary,
            ),
        ],
      ),
    );
  }

  /// Sub-option Action row (tappable)
  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    bool isDangerous = false,
  }) {
    final effectiveColor = iconColor ??
        (isDangerous ? AppColors.expense : AppColors.primary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: effectiveColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDangerous
                            ? AppColors.expense
                            : AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color:
                    AppColors.textSecondaryOf(context).withValues(alpha: 0.5),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// User profile chip inside Account section
  Widget _buildUserProfileCard() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Logged In User';
    final displayName = user?.displayName;
    final initial = (displayName?.isNotEmpty == true
            ? displayName![0]
            : (email.isNotEmpty ? email[0] : 'U'))
        .toUpperCase();

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              initial,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (displayName != null && displayName.isNotEmpty) ...[
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                ],
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Theme segment selector item
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
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
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
                size: 16,
                color: isSelected ? AppColors.primary : inactiveText,
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
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

  /// Device optimization shortcut tile
  Widget _buildSubOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = AppColors.isDark(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.primary.withValues(alpha: 0.07)
                : AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: AppColors.primary, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 13,
                color: AppColors.textSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
