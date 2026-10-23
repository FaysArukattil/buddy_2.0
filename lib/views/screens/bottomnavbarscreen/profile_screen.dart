// ProfileScreen — clean, modern profile page.
// One teal header (avatar, name, balance), a quiet stats row, and grouped settings lists.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/format_utils.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/theme_service.dart';
import 'package:buddy/services/feedback_service.dart';
import 'package:buddy/services/support_service.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/views/screens/onboarding/login_screen.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';
import 'package:buddy/views/widgets/buddy_refresh_control.dart';
import 'package:buddy/views/screens/filtered_transactions_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Called by the parent (via GlobalKey) to refresh this tab.
  Future<void> refreshData() => _loadProfile();

  static const _mint = Color(0xFF69F0AE);
  static const _coral = Color(0xFFFF8A80);

  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();

  bool _isAccountActionLoading = false;
  String _name = '';
  String _email = '';
  String? _photoUrl;
  DateTime? _memberSince;
  double _totalIncome = 0;
  double _totalExpense = 0;
  String _topCategory = '-';
  int _totalTxnsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ───────────────────────── Data ─────────────────────────

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();

      final email = (user?.email ?? '').isNotEmpty
          ? user!.email!
          : (prefs.getString('email') ?? '');

      var name = prefs.getString('name') ?? user?.displayName ?? '';
      if (name.isEmpty && email.contains('@')) {
        final local = email.split('@').first;
        if (local.isNotEmpty)
          name = local[0].toUpperCase() + local.substring(1);
      }

      if (mounted) {
        setState(() {
          _name = name;
          _email = email;
          _photoUrl = user?.photoURL;
          _memberSince = user?.metadata.creationTime;
        });
      }
      _loadStats();
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadStats() async {
    try {
      final now = DateTime.now();
      final totals = await FirestoreService.instance.getMonthlyTotals(
        now.year,
        now.month,
      );
      final allTxns = await FirestoreService.instance.getAllTransactions();

      final counts = <String, int>{};
      for (final t in allTxns) {
        counts[t.category] = (counts[t.category] ?? 0) + 1;
      }
      var top = '-';
      if (counts.isNotEmpty) {
        top =
            (counts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;
      }

      if (!mounted) return;
      setState(() {
        _totalIncome = totals['income'] ?? 0;
        _totalExpense = totals['expense'] ?? 0;
        _topCategory = top;
        _totalTxnsCount = allTxns.length;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  // ───────────────────────── Helpers ─────────────────────────

  String _money(double v) => FormatUtils.formatCurrency(v, compact: true);

  String _memberSinceLabel() {
    const m = [
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
    return '${m[_memberSince!.month - 1]} ${_memberSince!.year}';
  }

  List<Color> _avatarGradient() {
    const gradients = [
      [Color(0xFF667eea), Color(0xFF764ba2)],
      [Color(0xFFf093fb), Color(0xFFf5576c)],
      [Color(0xFF4facfe), Color(0xFF00c6d7)],
      [Color(0xFF43e97b), Color(0xFF2bbfa8)],
      [Color(0xFFfa709a), Color(0xFFf0a020)],
      [Color(0xFF6a11cb), Color(0xFF2575fc)],
    ];
    if (_name.isEmpty) return gradients.first;
    return gradients[_name.codeUnitAt(0) % gradients.length];
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = AppColors.isDark(context);
    final topPadding = MediaQuery.of(context).padding.top;
    final headerColor = isDark
        ? const Color(0xFF0F2624)
        : const Color(0xFF0F3632);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
        children: [
          // Fills the area revealed when the user over-scrolls at the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, _) {
                final offset = _scrollController.hasClients
                    ? _scrollController.offset
                    : 0.0;
                if (offset >= 0) return const SizedBox.shrink();
                return Container(
                  height: topPadding - offset + 40,
                  color: headerColor,
                );
              },
            ),
          ),
          CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              BuddyRefreshControl(
                onRefresh: refreshData,
                backgroundColor: headerColor,
                topPadding: topPadding,
              ),
              SliverToBoxAdapter(child: _buildHeader(isDark, topPadding)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildStatsRow(),
                    const SizedBox(height: 28),
                    _sectionLabel('Appearance'),
                    _buildThemeSelector(isDark),
                    const SizedBox(height: 28),
                    _sectionLabel('Help & support'),
                    _group([
                      _tile(
                        icon: Icons.bug_report_outlined,
                        title: 'Report a bug',
                        onTap: () => FeedbackService.reportBug(context),
                      ),
                      _tile(
                        icon: Icons.lightbulb_outline_rounded,
                        title: 'Request a feature',
                        onTap: () => FeedbackService.requestFeature(context),
                      ),
                      _tile(
                        icon: Icons.local_cafe_outlined,
                        title: 'Buy me a chai',
                        onTap: () => SupportService.openBuyMeChai(context),
                      ),
                    ]),
                    const SizedBox(height: 28),
                    _sectionLabel('Account'),
                    _group([
                      _tile(
                        icon: Icons.logout_rounded,
                        title: 'Log out',
                        onTap: _isAccountActionLoading ? null : _handleLogout,
                      ),
                      _tile(
                        icon: Icons.delete_outline_rounded,
                        title: 'Delete account',
                        subtitle: 'Permanently removes your data',
                        color: const Color(0xFFD32F2F),
                        onTap: _isAccountActionLoading
                            ? null
                            : _handleDeleteAccount,
                      ),
                    ]),
                    if (_isAccountActionLoading) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const BuddyLoadingIndicator(size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'Please wait…',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Header ─────────────────────────

  Widget _buildHeader(bool isDark, double topPadding) {
    final balance = _totalIncome - _totalExpense;
    final positive = balance >= 0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPadding + 24, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0F2624), Color(0xFF1E5D57)]
              : const [Color(0xFF0F3632), Color(0xFF2C7A72)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          _buildAvatar(),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _editName,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _name.isEmpty ? 'Add your name' : _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
          if (_email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
          ],
          if (_memberSince != null) ...[
            const SizedBox(height: 2),
            Text(
              'Member since ${_memberSinceLabel()}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Balance this month',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            FormatUtils.formatCurrency(balance, compact: false),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: positive ? Colors.white : _coral,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _flowChip(
                  label: 'Income',
                  value: '+${_money(_totalIncome)}',
                  color: _mint,
                  icon: Icons.arrow_upward_rounded,
                  type: 'Income',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _flowChip(
                  label: 'Expenses',
                  value: '-${_money(_totalExpense)}',
                  color: _coral,
                  icon: Icons.arrow_downward_rounded,
                  type: 'Expense',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _flowChip({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required String type,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FilteredTransactionsScreen(type: type),
          ),
        ).then((_) => refreshData());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
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
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    const radius = 42.0;
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;

    return GestureDetector(
      onTap: _editName,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: hasPhoto
            ? CircleAvatar(
                radius: radius,
                backgroundColor: AppColors.surfaceOf(context),
                backgroundImage: NetworkImage(_photoUrl!),
                onBackgroundImageError: (e, _) =>
                    debugPrint('Error loading photo: $e'),
              )
            : Container(
                width: radius * 2,
                height: radius * 2,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _avatarGradient(),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Text(
                  _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
      ),
    );
  }

  // ───────────────────────── Stats ─────────────────────────

  Widget _buildStatsRow() {
    final balance = _totalIncome - _totalExpense;
    final divider = Container(
      width: 1,
      height: 36,
      color: AppColors.borderOf(context).withValues(alpha: 0.6),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _stat('Top category', _topCategory, const Color(0xFFFF7043)),
          ),
          divider,
          Expanded(
            child: _stat(
              'Saved',
              balance >= 0 ? _money(balance) : '-${_money(balance.abs())}',
              balance >= 0 ? AppColors.income : AppColors.expense,
            ),
          ),
          divider,
          Expanded(
            child: _stat(
              'Transactions',
              '$_totalTxnsCount',
              const Color(0xFF42A5F5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── Settings UI ─────────────────────────

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

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: AppColors.cardOf(context),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: AppColors.borderOf(context).withValues(alpha: 0.5),
    ),
  );

  /// A single rounded card holding several tiles separated by thin dividers.
  Widget _group(List<Widget> tiles) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      children.add(tiles[i]);
      if (i != tiles.length - 1) {
        children.add(
          Divider(
            height: 1,
            indent: 60,
            color: AppColors.borderOf(context).withValues(alpha: 0.5),
          ),
        );
      }
    }
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? color,
    required VoidCallback? onTap,
  }) {
    final tint = color ?? AppColors.textPrimaryOf(context);
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color ?? AppColors.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tint,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSecondaryOf(
                  context,
                ).withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeSelector(bool isDark) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, mode, _) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161C23) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              _themeOption(
                'System',
                Icons.brightness_auto_rounded,
                mode == ThemeMode.system,
                ThemeMode.system,
              ),
              _themeOption(
                'Light',
                Icons.light_mode_rounded,
                mode == ThemeMode.light,
                ThemeMode.light,
              ),
              _themeOption(
                'Dark',
                Icons.dark_mode_rounded,
                mode == ThemeMode.dark,
                ThemeMode.dark,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themeOption(
    String title,
    IconData icon,
    bool selected,
    ThemeMode mode,
  ) {
    final isDark = AppColors.isDark(context);
    final inactive = isDark ? Colors.white60 : Colors.grey.shade600;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ThemeService.setThemeMode(mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF263342) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primary : inactive,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.textPrimaryOf(context) : inactive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Name editing ─────────────────────────

  Future<void> _editName() async {
    HapticFeedback.lightImpact();
    final controller = TextEditingController(text: _name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Edit name',
          style: TextStyle(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
          style: TextStyle(color: AppColors.textPrimaryOf(context)),
          decoration: InputDecoration(
            hintText: 'Your name',
            hintStyle: TextStyle(color: AppColors.textLightOf(context)),
            filled: true,
            fillColor: AppColors.surfaceOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondaryOf(context)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', newName);
    if (!mounted) return;
    setState(() => _name = newName);
    AppSnackbar.showSuccess(context, 'Name updated');
  }

  // ───────────────────────── Logout ─────────────────────────

  Future<void> _handleLogout() async {
    final isGuest = await _authService.isGuestUser();

    final confirmed = isGuest
        ? await _showConfirmDialog(
            title: 'Log out as guest?',
            message:
                'All your transactions, categories and settings will be permanently deleted. '
                'Create an account first if you want to keep your data.',
            confirmLabel: 'Log out & delete',
            isDangerous: true,
          )
        : await _showConfirmDialog(
            title: 'Log out?',
            message: 'You will need to sign in again to access your data.',
            confirmLabel: 'Log out',
          );

    if (!confirmed || !mounted) return;
    setState(() => _isAccountActionLoading = true);

    try {
      // Guests have no account to return to, so wipe their data instead.
      if (isGuest) {
        await _authService.deleteAccount();
      } else {
        await _authService.signOut();
      }
      if (!mounted) return;
      _goToLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAccountActionLoading = false);
      AppSnackbar.showError(context, 'Error: $e');
    }
  }

  // ───────────────────────── Delete account ─────────────────────────

  Future<void> _handleDeleteAccount() async {
    final first = await _showConfirmDialog(
      title: 'Delete account?',
      message:
          'This permanently deletes your account and all your data. This cannot be undone.',
      confirmLabel: 'Delete',
      isDangerous: true,
    );
    if (!first || !mounted) return;

    final second = await _showTypeToConfirmDialog();
    if (!second || !mounted) return;

    setState(() => _isAccountActionLoading = true);
    try {
      await _authService.deleteAccount();
      if (!mounted) return;
      _goToLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAccountActionLoading = false);
      if (e.toString() == 'requires-recent-login') {
        await _reauthAndDelete();
      } else {
        AppSnackbar.showError(context, 'Error: $e');
      }
    }
  }

  Future<void> _reauthAndDelete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final providers = user.providerData.map((p) => p.providerId).toList();
    var reauthed = false;

    if (providers.contains('google.com')) {
      AppSnackbar.showWarning(
        context,
        'Sign in with Google again to confirm deletion',
      );
      reauthed = await _authService.reauthenticate();
    } else if (providers.contains('password')) {
      final password = await _showPasswordDialog();
      if (password == null || !mounted) return;
      reauthed = await _authService.reauthenticate(
        email: user.email,
        password: password,
      );
      if (!reauthed && mounted) {
        AppSnackbar.showError(
          context,
          'Incorrect password. Account not deleted.',
        );
        return;
      }
    } else if (user.isAnonymous) {
      reauthed = true;
    }

    if (!reauthed || !mounted) return;

    setState(() => _isAccountActionLoading = true);
    try {
      await _authService.deleteAccount();
      if (!mounted) return;
      _goToLogin();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAccountActionLoading = false);
      AppSnackbar.showError(context, 'Error: $e');
    }
  }

  // ───────────────────────── Dialogs ─────────────────────────

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            child: Text(confirmLabel),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isValid = controller.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            backgroundColor: AppColors.cardOf(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Final confirmation',
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.bold,
              ),
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
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.5,
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
                  disabledForegroundColor: Colors.grey,
                ),
                child: const Text('Delete everything'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    var obscure = true;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Confirm password',
            style: TextStyle(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your password to confirm account deletion.',
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
                style: TextStyle(color: AppColors.textPrimaryOf(context)),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: AppColors.textLightOf(context)),
                  filled: true,
                  fillColor: AppColors.surfaceOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
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
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondaryOf(context)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }
}
