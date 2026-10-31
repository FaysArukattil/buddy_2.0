// lib/views/widgets/setting_modal.dart
//
// Settings sheet — same visual language as Home / Statistics / Profile:
// deep-teal gradient header with a frosted profile card, then grouped
// rounded cards under quiet section labels. All behaviour is unchanged.
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
import 'package:buddy/views/widgets/save_guest_account_modal.dart';
import 'package:buddy/views/widgets/currency_picker_sheet.dart';
import 'package:buddy/services/currency_service.dart';
import 'package:buddy/services/global_parsing_service.dart';

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
  // Non-India auto-detection status (loaded asynchronously)
  bool _globalParsingEnabled = false;
  String _accountActionMessage = 'Please wait...';
  String _appVersion = 'v1.0.0';
  final AuthService _authService = AuthService();

  // ── Design tokens (shared with Home / Statistics / Profile) ──
  static const Color _mint = Color(0xFF69F0AE);
  static const Color _danger = Color(0xFFEF4444);
  static const Color _headerDark = Color(0xFF0F3632);

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
      final globalEnabled = await GlobalParsingService.isEnabledForCurrentUser();
      if (mounted) {
        setState(() {
          _autoDetectionEnabled = enabled && hasAccess;
          _includeDebtsInBalance = includeDebts;
          _appVersion = versionStr;
          _isLoading = false;
          _globalParsingEnabled = globalEnabled;
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
        final hasAccess =
            await NotificationService.isNotificationAccessGranted();

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
      icon: Icons.today_rounded,
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
      icon: Icons.calendar_month_rounded,
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
      icon: Icons.delete_forever_rounded,
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
      icon: Icons.logout_rounded,
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
      icon: Icons.person_remove_rounded,
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

  // ───────────────────────── Dialogs ─────────────────────────

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    bool isDangerous = false,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: isDangerous ? 'Delete' : 'Confirm',
        isDangerous: isDangerous,
        icon:
            icon ??
            (isDangerous
                ? Icons.delete_forever_rounded
                : Icons.help_outline_rounded),
      ),
    );

    return result ?? false;
  }

  Future<bool> _showTypeToConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _TypeToConfirmDialog(),
    );
    return result ?? false;
  }

  Future<String?> _showPasswordDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => const _PasswordDialog(),
    );
  }

  // ───────────────────────── BUILD UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(isDark),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 22, 20, bottomInset + 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Appearance & home ──
                      _sectionLabel('Appearance'),
                      _card(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: _buildThemeSelector(isDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // ── Currency & Region ──
                      _sectionLabel('Currency & region'),
                      ValueListenableBuilder<int>(
                        valueListenable: CurrencyService.currencyNotifier,
                        builder: (context, _, __) {
                          final isNonIndia = CurrencyService.countryCode != 'IN';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _card(
                                children: [
                                  _tile(
                                    icon: Icons.language_rounded,
                                    title: 'Country & currency',
                                    subtitle:
                                        '${CurrencyService.currencyCode} · ${CurrencyService.currencySymbol}  (display only — amounts not converted)',
                                    trailingIcon: Icons.chevron_right_rounded,
                                    onTap: () => CurrencyPickerSheet.show(context),
                                  ),
                                ],
                              ),
                              // Show info banner for non-India users
                              if (isNonIndia) ...[
                                const SizedBox(height: 10),
                                _nonIndiaTipBanner(),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 26),

                      // ── Home balance ──
                      _sectionLabel('Home balance'),
                      _card(
                        children: [
                          _buildSwitchRow(
                            icon: Icons.swap_horiz_rounded,
                            title: 'Include lending & borrowing',
                            subtitle: _includeDebtsInBalance
                                ? 'Debts count toward your balance'
                                : 'Debts are tracked separately',
                            value: _includeDebtsInBalance,
                            onChanged: _toggleIncludeDebts,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // ── Smart tracking ──
                      _sectionLabel('Smart tracking'),
                      _card(
                        children: [
                          _buildSwitchRow(
                            icon: Icons.bolt_rounded,
                            title: 'Track bank SMS',
                            subtitle: 'Auto-record incoming transactions',
                            value: _autoDetectionEnabled,
                            isLoading: _isLoading,
                            onChanged: _toggleAutoDetection,
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOutCubic,
                            alignment: Alignment.topCenter,
                            child: _autoDetectionEnabled
                                ? Column(
                                    children: [
                                      _divider(),
                                      _tile(
                                        icon:
                                            Icons.battery_charging_full_rounded,
                                        title: 'Disable battery optimization',
                                        subtitle:
                                            'Keeps detection reliable in background',
                                        trailingIcon: Icons.open_in_new_rounded,
                                        onTap: () =>
                                            NotificationService.openBatteryOptimizationSettings(),
                                      ),
                                      _divider(),
                                      _tile(
                                        icon: Icons.rocket_launch_outlined,
                                        title: 'Enable autostart access',
                                        subtitle:
                                            'Required on Vivo, Xiaomi, Oppo & Samsung',
                                        trailingIcon: Icons.open_in_new_rounded,
                                        onTap: () =>
                                            NotificationService.openAutoStartSettings(),
                                      ),
                                    ],
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // ── Data ──
                      _sectionLabel('Data'),
                      _card(
                        children: [
                          _tile(
                            icon: Icons.today_rounded,
                            title: 'Clear today\'s data',
                            subtitle: 'Delete records logged today only',
                            onTap: _clearTodayData,
                          ),
                          _divider(),
                          _tile(
                            icon: Icons.calendar_month_rounded,
                            title: 'Clear this month',
                            subtitle: 'Delete records logged this month',
                            onTap: _clearThisMonthData,
                          ),
                          _divider(),
                          _tile(
                            icon: Icons.delete_sweep_rounded,
                            title: 'Clear all data',
                            subtitle: 'Permanently wipe every transaction',
                            color: AppColors.expense,
                            onTap: _clearAllData,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // ── Help & support ──
                      _sectionLabel('Help & support'),
                      _card(
                        children: [
                          _tile(
                            icon: Icons.star_rate_rounded,
                            title: 'Rate on Google Play',
                            subtitle: 'Share a review & rating on Play Store',
                            color: const Color(0xFFFFB300),
                            tintOnly: true,
                            onTap: () => FeedbackService.openPlayStore(context),
                          ),
                          _divider(),
                          _tile(
                            icon: Icons.bug_report_outlined,
                            title: 'Report a bug',
                            subtitle: 'Email diagnostics directly to developer',
                            onTap: () => FeedbackService.reportBug(context),
                          ),
                          _divider(),
                          _tile(
                            icon: Icons.lightbulb_outline_rounded,
                            title: 'Request a feature',
                            subtitle: 'Share your ideas to improve Buddy',
                            onTap: () =>
                                FeedbackService.requestFeature(context),
                          ),
                          _divider(),
                          _tile(
                            icon: Icons.local_cafe_outlined,
                            title: 'Buy the developer a chai ☕',
                            subtitle: 'Support Buddy\'s development',
                            color: const Color(0xFFFF9800),
                            tintOnly: true,
                            onTap: () => SupportService.openBuyMeChai(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // ── Account ──
                      _sectionLabel('Account'),
                      _card(
                        children: [
                          if (FirebaseAuth.instance.currentUser?.isAnonymous == true) ...[
                            _tile(
                              icon: Icons.cloud_done_rounded,
                              title: 'Sign In / Save Account',
                              subtitle: 'Preserve all your guest data permanently',
                              color: AppColors.primary,
                              onTap: () {
                                Navigator.pop(context);
                                SaveGuestAccountModal.show(context);
                              },
                            ),
                            _divider(),
                          ],
                          _tile(
                            icon: Icons.logout_rounded,
                            title: 'Sign out',
                            subtitle: 'Safely sign out of your account',
                            onTap: _isAccountActionLoading
                                ? null
                                : _handleLogout,
                          ),
                          _divider(),
                          _tile(
                            icon: Icons.person_remove_outlined,
                            title: 'Delete account',
                            subtitle: 'Permanently remove account & cloud data',
                            color: AppColors.expense,
                            onTap: _isAccountActionLoading
                                ? null
                                : _handleDeleteAccount,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // ── Footer ──
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Buddy $_appVersion',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: AppColors.textSecondaryOf(
                                  context,
                                ).withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Crafted for effortless personal finance',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(
                                  context,
                                ).withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay during account delete/logout
          if (_isAccountActionLoading)
            Positioned.fill(
              child: AbsorbPointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 26,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
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
            ),
        ],
      ),
    );
  }

  // ───────────────────────── Header ─────────────────────────

  Widget _buildHeader(bool isDark) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Logged In User';
    final displayName = user?.displayName;
    final hasName = displayName != null && displayName.isNotEmpty;
    final photoUrl = user?.photoURL;
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;
    final initial =
        (hasName ? displayName[0] : (email.isNotEmpty ? email[0] : 'U'))
            .toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0F2624), Color(0xFF163E3B), Color(0xFF1E5D57)]
              : const [_headerDark, Color(0xFF1E5D57), Color(0xFF2C7A72)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: _headerDark.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Make Buddy work your way',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Frosted profile card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.32),
                      width: 1.4,
                    ),
                    image: hasPhoto
                        ? DecorationImage(
                            image: NetworkImage(photoUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: hasPhoto
                      ? null
                      : Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasName) ...[
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Status chips
          Row(
            children: [
              Expanded(
                child: _statusChip(
                  icon: Icons.bolt_rounded,
                  label: 'Auto-detect',
                  value: _autoDetectionEnabled ? 'On' : 'Off',
                  color: _autoDetectionEnabled ? _mint : Colors.white70,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeService.themeModeNotifier,
                  builder: (context, mode, _) {
                    final label = mode == ThemeMode.system
                        ? 'System'
                        : (mode == ThemeMode.light ? 'Light' : 'Dark');
                    return _statusChip(
                      icon: Icons.palette_outlined,
                      label: 'Theme',
                      value: label,
                      color: Colors.white,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Building blocks ─────────────────────────

  /// Info banner shown under "Currency & region" for non-India users.
  /// - When global parsing is OFF: explains manual entry is needed for now.
  /// - When global parsing is ON: tips the user to enable transaction alerts
  ///   in their bank app.
  Widget _nonIndiaTipBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF1E2A38)
        : const Color(0xFFEFF6FF);
    final borderColor = isDark
        ? const Color(0xFF2D4A6B)
        : const Color(0xFFBFDBFE);
    final textColor = isDark
        ? const Color(0xFF93C5FD)
        : const Color(0xFF1D4ED8);

    final String message = _globalParsingEnabled
        ? 'For automatic tracking, turn on transaction alerts in your bank app. '
            'Buddy will detect them automatically.'
        : 'Automatic detection is rolling out gradually for your country. '
            'Add transactions manually for now — it will activate when ready.';

    final IconData icon = _globalParsingEnabled
        ? Icons.check_circle_outline_rounded
        : Icons.info_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: textColor, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }

  /// Rounded card that holds a vertical stack of rows.
  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  /// Hairline divider; default inset aligns with row text.
  Widget _divider({double inset = 66}) {
    return Divider(
      height: 1,
      thickness: 0.8,
      indent: inset,
      color: AppColors.borderOf(context).withValues(alpha: 0.5),
    );
  }

  Widget _leadingIcon(IconData icon, Color tint) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 19, color: tint),
    );
  }

  /// Tappable row. [color] turns the whole row into a "danger"/accent row;
  /// with [tintOnly] only the icon is coloured and the title stays neutral.
  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color? color,
    bool tintOnly = false,
    IconData trailingIcon = Icons.chevron_right_rounded,
  }) {
    final iconTint = color ?? AppColors.primary;
    final titleColor = (color != null && !tintOnly)
        ? color
        : AppColors.textPrimaryOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _leadingIcon(icon, iconTint),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
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
              const SizedBox(width: 8),
              Icon(
                trailingIcon,
                size: trailingIcon == Icons.chevron_right_rounded ? 20 : 16,
                color: AppColors.textSecondaryOf(
                  context,
                ).withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _leadingIcon(icon, AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
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
          const SizedBox(width: 8),
          SizedBox(
            width: 54,
            child: Center(
              child: isLoading
                  ? const BuddyLoadingIndicator(size: 20)
                  : Switch.adaptive(
                      value: value,
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        onChanged(v);
                      },
                      activeTrackColor: AppColors.primary,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Theme selector ─────────────────────────

  Widget _buildThemeSelector(bool isDark) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, mode, _) {
        final selectedIndex = mode == ThemeMode.system
            ? 0
            : (mode == ThemeMode.light ? 1 : 2);

        return Container(
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141A22) : const Color(0xFFEFF2F6),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / 3;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: selectedIndex * tabWidth,
                    top: 0,
                    bottom: 0,
                    width: tabWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF243040) : AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.04),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.35 : 0.06,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _themeTab(
                        title: 'System',
                        icon: Icons.brightness_auto_rounded,
                        isSelected: selectedIndex == 0,
                        isDark: isDark,
                        onTap: () =>
                            ThemeService.setThemeMode(ThemeMode.system),
                      ),
                      _themeTab(
                        title: 'Light',
                        icon: Icons.light_mode_rounded,
                        isSelected: selectedIndex == 1,
                        isDark: isDark,
                        onTap: () => ThemeService.setThemeMode(ThemeMode.light),
                      ),
                      _themeTab(
                        title: 'Dark',
                        icon: Icons.dark_mode_rounded,
                        isSelected: selectedIndex == 2,
                        isDark: isDark,
                        onTap: () => ThemeService.setThemeMode(ThemeMode.dark),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _themeTab({
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final activeColor = AppColors.textPrimaryOf(context);
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : AppColors.textSecondaryOf(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.primary : inactiveColor,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Dialogs ─────────────────────────

/// Shared chrome for every dialog: icon badge, title, body, action row.
class _DialogShell extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final List<Widget> body;
  final Widget actions;

  const _DialogShell({
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.borderOf(
              context,
            ).withValues(alpha: isDark ? 0.35 : 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: 0.28),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            ...body,
            const SizedBox(height: 22),
            actions,
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? fill; // null → neutral ghost button

  const _DialogButton({required this.label, required this.onTap, this.fill});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final enabled = onTap != null;
    final filled = fill != null;
    final bg = filled
        ? (enabled ? fill! : fill!.withValues(alpha: 0.38))
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppColors.surfaceOf(context));

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.3),
                ),
          boxShadow: (filled && enabled)
              ? [
                  BoxShadow(
                    color: fill!.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
              color: filled
                  ? (enabled
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6))
                  : AppColors.textPrimaryOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _dialogFieldDecoration(
  BuildContext context, {
  required String hint,
  required Color focusColor,
  double letterSpacing = 0,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final isDark = AppColors.isDark(context);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  final base = AppColors.borderOf(context).withValues(alpha: 0.4);

  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppColors.textLightOf(context),
      letterSpacing: letterSpacing,
      fontWeight: FontWeight.w600,
    ),
    filled: true,
    fillColor: isDark ? const Color(0xFF141920) : AppColors.surfaceOf(context),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(base),
    enabledBorder: border(base),
    focusedBorder: border(focusColor, 1.8),
  );
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool isDangerous;
  final IconData icon;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.isDangerous,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDangerous
        ? _SettingsModalState._danger
        : AppColors.primary;

    return _DialogShell(
      icon: icon,
      accent: accent,
      title: title,
      body: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondaryOf(context),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
      ],
      actions: Row(
        children: [
          Expanded(
            child: _DialogButton(
              label: 'Cancel',
              onTap: () => Navigator.pop(context, false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DialogButton(
              label: confirmLabel,
              fill: accent,
              onTap: () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog();

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final valid = _controller.text.trim().toUpperCase() == 'DELETE';
      if (valid != _isValid) setState(() => _isValid = valid);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const danger = _SettingsModalState._danger;

    return _DialogShell(
      icon: Icons.warning_amber_rounded,
      accent: danger,
      title: 'Final Confirmation',
      body: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              color: AppColors.textSecondaryOf(context),
              fontSize: 13.5,
              height: 1.45,
            ),
            children: const [
              TextSpan(text: 'Type '),
              TextSpan(
                text: 'DELETE',
                style: TextStyle(
                  color: danger,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              TextSpan(
                text: ' to permanently remove your account and all data.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(
            color: AppColors.textPrimaryOf(context),
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
          decoration: _dialogFieldDecoration(
            context,
            hint: 'DELETE',
            letterSpacing: 3,
            focusColor: danger,
          ),
        ),
      ],
      actions: Row(
        children: [
          Expanded(
            child: _DialogButton(
              label: 'Cancel',
              onTap: () => Navigator.pop(context, false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DialogButton(
              label: 'Delete Forever',
              fill: danger,
              onTap: _isValid ? () => Navigator.pop(context, true) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const danger = _SettingsModalState._danger;

    return _DialogShell(
      icon: Icons.lock_outline_rounded,
      accent: danger,
      title: 'Re-enter Password',
      body: [
        Text(
          'For security, please re-enter your password to confirm account deletion.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondaryOf(context),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          obscureText: _obscure,
          autofocus: true,
          style: TextStyle(
            color: AppColors.textPrimaryOf(context),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: _dialogFieldDecoration(
            context,
            hint: 'Password',
            focusColor: danger,
            prefixIcon: const Icon(Icons.key_rounded, size: 20, color: danger),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: AppColors.textSecondaryOf(context),
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
      ],
      actions: Row(
        children: [
          Expanded(
            child: _DialogButton(
              label: 'Cancel',
              onTap: () => Navigator.pop(context, null),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DialogButton(
              label: 'Confirm',
              fill: danger,
              onTap: () => Navigator.pop(context, _controller.text),
            ),
          ),
        ],
      ),
    );
  }
}
