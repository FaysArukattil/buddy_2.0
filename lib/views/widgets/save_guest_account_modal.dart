import 'package:flutter/material.dart';
import 'package:buddy/services/Network_services.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/widgets/auth_shell.dart';

/// Modal sheet for guest users to save their data permanently
/// by linking a new account or signing in & merging with an existing account.
class SaveGuestAccountModal extends StatefulWidget {
  final VoidCallback? onSuccess;

  const SaveGuestAccountModal({super.key, this.onSuccess});

  static Future<bool?> show(BuildContext context, {VoidCallback? onSuccess}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaveGuestAccountModal(onSuccess: onSuccess),
    );
  }

  @override
  State<SaveGuestAccountModal> createState() => _SaveGuestAccountModalState();
}

class _SaveGuestAccountModalState extends State<SaveGuestAccountModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  int _modeIndex = 0; // 0 = Create Account (Link), 1 = Sign In & Merge
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogle() async {
    final hasNetwork = await NetworkHelper.hasInternetConnection();
    if (!hasNetwork) {
      if (mounted) {
        AppSnackbar.showWarning(
          context,
          'No internet connection. Please check your network.',
        );
      }
      return;
    }

    setState(() => _isGoogleLoading = true);

    try {
      if (_modeIndex == 0) {
        // Mode 0: Try linking as new account
        try {
          final res = await _authService.convertGuestToGoogle();
          if (res != null && mounted) {
            _onCompleted('Account saved with Google! Data preserved.');
          } else if (mounted) {
            setState(() => _isGoogleLoading = false);
          }
        } on AccountExistsException catch (e) {
          // Conflict: Account already exists. Ask to merge!
          if (!mounted) return;
          setState(() => _isGoogleLoading = false);
          final shouldMerge = await _showMergeConfirmDialog(e.email);
          if (shouldMerge == true && e.credential != null && mounted) {
            setState(() => _isGoogleLoading = true);
            await _authService.signInAndMergeGuestWithGoogle(e.credential!);
            if (mounted) {
              _onCompleted('Merged successfully! All guest data saved.');
            }
          }
        }
      } else {
        // Mode 1: Sign in & merge directly with Google
        try {
          final res = await _authService.convertGuestToGoogle();
          if (res != null && mounted) {
            _onCompleted('Account linked with Google! Data preserved.');
          }
        } on AccountExistsException catch (e) {
          if (e.credential != null && mounted) {
            await _authService.signInAndMergeGuestWithGoogle(e.credential!);
            if (mounted) {
              _onCompleted('Merged successfully! Guest data added to account.');
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, authErrorMessage(e));
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Future<void> _handleEmailSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final hasNetwork = await NetworkHelper.hasInternetConnection();
    if (!hasNetwork) {
      if (mounted) {
        AppSnackbar.showWarning(
          context,
          'No internet connection. Please check your network.',
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_modeIndex == 0) {
        // Mode 0: Create new account by linking credentials
        try {
          final res = await _authService.convertGuestToEmailPassword(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
          if (res != null && mounted) {
            _onCompleted('Account created! All your data is saved.');
          }
        } on AccountExistsException catch (e) {
          // Account already exists
          if (!mounted) return;
          setState(() => _isLoading = false);
          final shouldSwitch = await _showAccountExistsDialog(e.email);
          if (shouldSwitch == true && mounted) {
            setState(() {
              _modeIndex = 1; // switch to Sign In & Merge
            });
          }
        }
      } else {
        // Mode 1: Sign in to existing account and merge guest data
        await _authService.signInAndMergeGuestWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) {
          _onCompleted('Signed in! Guest transactions merged into account.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, authErrorMessage(e));
        setState(() => _isLoading = false);
      }
    }
  }

  void _onCompleted(String message) {
    if (!mounted) return;
    Navigator.of(context).pop(true);
    AppSnackbar.showSuccess(context, message);
    widget.onSuccess?.call();
  }

  Future<bool?> _showMergeConfirmDialog(String email) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Existing Account Found',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'An account with $email already exists. Would you like to merge all your guest transactions into this account?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E5D57),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Merge Data'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showAccountExistsDialog(String email) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Account Already Exists',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'An account for $email is already registered. Would you like to switch to Sign In and merge your guest data?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E5D57),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Sign In & Merge'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anyLoading = _isLoading || _isGoogleLoading;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderOf(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Header with badge
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E5D57), Color(0xFF2C7A72)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFF1E5D57).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.cloud_done_rounded,
                          size: 22,
                          color: kAuthMint,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _modeIndex == 0
                                  ? 'Save Your Account'
                                  : 'Sign In & Merge',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _modeIndex == 0
                                  ? 'Preserve all your transactions permanently'
                                  : 'Merge your guest data into existing account',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Segmented control: Create Account vs Sign In
                  AuthSegmentedControl(
                    selectedIndex: _modeIndex,
                    onTabChanged: (i) => setState(() => _modeIndex = i),
                  ),
                  const SizedBox(height: 18),

                  // Google button
                  AuthGoogleButton(
                    label: _modeIndex == 0
                        ? 'Save with Google'
                        : 'Sign In & Merge with Google',
                    onPressed: anyLoading ? null : _handleGoogle,
                    loading: _isGoogleLoading,
                  ),

                  const SizedBox(height: 16),
                  AuthOrDivider(
                    text: _modeIndex == 0
                        ? 'or save with email'
                        : 'or sign in with email',
                  ),
                  const SizedBox(height: 16),

                  // Full name (only in Create Account mode)
                  if (_modeIndex == 0) ...[
                    ModernAuthField(
                      label: 'Full Name',
                      hint: 'Your name',
                      controller: _nameController,
                      prefixIcon: Icons.person_rounded,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      validator: (val) {
                        if (_modeIndex == 0 &&
                            (val == null || val.trim().isEmpty)) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Email
                  ModernAuthField(
                    label: 'Email',
                    hint: 'name@example.com',
                    controller: _emailController,
                    prefixIcon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!val.contains('@') || !val.contains('.')) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Password
                  ModernAuthField(
                    label: 'Password',
                    hint: _modeIndex == 0
                        ? 'Create a password (min 6 characters)'
                        : 'Enter your account password',
                    controller: _passwordController,
                    prefixIcon: Icons.lock_outline_rounded,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleEmailSubmit(),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (val.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),

                  if (_modeIndex == 0) ...[
                    PasswordStrengthMeter(password: _passwordController.text),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 18),

                  // Primary submit button
                  AuthPrimaryButton(
                    label: _modeIndex == 0
                        ? 'Save Account'
                        : 'Sign In & Merge Data',
                    loadingLabel: _modeIndex == 0
                        ? 'Saving account...'
                        : 'Merging data...',
                    loading: _isLoading,
                    onPressed: anyLoading ? null : _handleEmailSubmit,
                  ),

                  const SizedBox(height: 18),
                  const AuthTrustBadge(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

