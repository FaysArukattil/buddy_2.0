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
        if (local.isNotEmpty) {
          name = local[0].toUpperCase() + local.substring(1);
        }
      }

      DateTime? memberSince = user?.metadata.creationTime;
      if (memberSince == null) {
        final saved = prefs.getString('member_since');
        if (saved != null) {
          memberSince = DateTime.tryParse(saved);
        }
      }
      if (memberSince == null) {
        memberSince = DateTime.now();
        await prefs.setString('member_since', memberSince.toIso8601String());
      } else {
        await prefs.setString('member_since', memberSince.toIso8601String());
      }

      if (mounted) {
        setState(() {
          _name = name;
          _email = email;
          _photoUrl = user?.photoURL;
          _memberSince = memberSince;
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
    if (_memberSince == null) return 'Recent';
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
    final monthIdx = (_memberSince!.month - 1).clamp(0, 11);
    return '${m[monthIdx]} ${_memberSince!.year}';
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
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(context).padding.bottom + 110,
                ),
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
      padding: EdgeInsets.fromLTRB(20, topPadding + 14, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF0F2624), Color(0xFF1E5D57)]
              : const [Color(0xFF0F3632), Color(0xFF2C7A72)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // Side-by-side layout: Large photo card on left, details on right
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildPhotoCard(),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _editName,
                      behavior: HitTestBehavior.opaque,
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
                    if (_email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        _email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Member since ${_memberSinceLabel()}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
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
          const SizedBox(height: 18),
          // Subtle horizontal divider line
          Container(
            height: 1,
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 14),
          Text(
            'Balance this month',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            FormatUtils.formatCurrency(balance, compact: false),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: positive ? Colors.white : _coral,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 14),
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
              const SizedBox(width: 10),
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

  Widget _buildPhotoCard() {
    const cardSize = 92.0;
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;

    return GestureDetector(
      onTap: _editName,
      child: Container(
        width: cardSize,
        height: cardSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: hasPhoto
              ? null
              : LinearGradient(
                  colors: _avatarGradient(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 2.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: hasPhoto
              ? Image.network(
                  _photoUrl!,
                  width: cardSize,
                  height: cardSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _avatarFallback(cardSize),
                )
              : _avatarFallback(cardSize),
        ),
      ),
    );
  }

  Widget _avatarFallback(double size) {
    return Center(
      child: Text(
        _name.isNotEmpty ? _name.trim()[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w800,
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
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
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
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
        final selectedIndex = mode == ThemeMode.system
            ? 0
            : (mode == ThemeMode.light ? 1 : 2);

        return Container(
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141A22) : const Color(0xFFEFF2F6),
            borderRadius: BorderRadius.circular(16),
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
                  // Smooth animated sliding pill
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    left: selectedIndex * tabWidth,
                    top: 0,
                    bottom: 0,
                    width: tabWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF243040)
                            : Colors.white,
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
                  // Tab items row
                  Row(
                    children: [
                      _themeTabItem(
                        title: 'System',
                        icon: Icons.brightness_auto_rounded,
                        isSelected: selectedIndex == 0,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ThemeService.setThemeMode(ThemeMode.system);
                        },
                        isDark: isDark,
                      ),
                      _themeTabItem(
                        title: 'Light',
                        icon: Icons.light_mode_rounded,
                        isSelected: selectedIndex == 1,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ThemeService.setThemeMode(ThemeMode.light);
                        },
                        isDark: isDark,
                      ),
                      _themeTabItem(
                        title: 'Dark',
                        icon: Icons.dark_mode_rounded,
                        isSelected: selectedIndex == 2,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ThemeService.setThemeMode(ThemeMode.dark);
                        },
                        isDark: isDark,
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

  Widget _themeTabItem({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final activeColor = isDark ? Colors.white : AppColors.textPrimaryOf(context);
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : AppColors.textSecondaryOf(context);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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

  // ───────────────────────── Name editing ─────────────────────────

  Future<void> _editName() async {
    HapticFeedback.lightImpact();
    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ModernEditNameDialog(initialName: _name),
    );

    if (newName == null || newName.isEmpty || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', newName);
    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
    } catch (e) {
      debugPrint('Could not update Firebase displayName: $e');
    }
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
      barrierDismissible: true,
      builder: (context) => _ModernConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        isDangerous: isDangerous,
      ),
    );
    return result ?? false;
  }

  Future<bool> _showTypeToConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ModernTypeToConfirmDialog(),
    );
    return result ?? false;
  }

  Future<String?> _showPasswordDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _ModernPasswordDialog(),
    );
    return result;
  }
}

// ───────────────────────── Modern Dialog Components ─────────────────────────

class _ModernConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool isDangerous;

  const _ModernConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.isDangerous,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final accentColor =
        isDangerous ? const Color(0xFFEF4444) : AppColors.primary;
    final icon =
        isDangerous ? Icons.delete_forever_rounded : Icons.logout_rounded;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.borderOf(context).withValues(
              alpha: isDark ? 0.35 : 0.2,
            ),
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
            // Icon Badge
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.28),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: accentColor, size: 26),
            ),
            const SizedBox(height: 18),
            // Title
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
            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondaryOf(context),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (isDangerous) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone.',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFFF8A80)
                              : const Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context, false);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textPrimaryOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context, true);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernEditNameDialog extends StatefulWidget {
  final String initialName;

  const _ModernEditNameDialog({required this.initialName});

  @override
  State<_ModernEditNameDialog> createState() => _ModernEditNameDialogState();
}

class _ModernEditNameDialogState extends State<_ModernEditNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      HapticFeedback.lightImpact();
      Navigator.pop(context, text);
    }
  }

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
            color: AppColors.borderOf(context).withValues(
              alpha: isDark ? 0.35 : 0.2,
            ),
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
                color: AppColors.primary.withValues(
                  alpha: isDark ? 0.18 : 0.12,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.badge_outlined,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Edit Name',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the name you would like to display on your profile and reports.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondaryOf(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Your name',
                hintStyle: TextStyle(
                  color: AppColors.textLightOf(context),
                  fontWeight: FontWeight.normal,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF141920)
                    : const Color(0xFFF8FAFC),
                prefixIcon: Icon(
                  Icons.person_outline_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.primary,
                    width: 1.8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textPrimaryOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _submit,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernTypeToConfirmDialog extends StatefulWidget {
  const _ModernTypeToConfirmDialog();

  @override
  State<_ModernTypeToConfirmDialog> createState() =>
      _ModernTypeToConfirmDialogState();
}

class _ModernTypeToConfirmDialogState extends State<_ModernTypeToConfirmDialog> {
  late final TextEditingController _controller;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final valid = _controller.text.trim().toUpperCase() == 'DELETE';
    if (valid != _isValid) {
      setState(() => _isValid = valid);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    const dangerColor = Color(0xFFEF4444);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: dangerColor.withValues(alpha: 0.3),
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
                color: dangerColor.withValues(alpha: isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: dangerColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: dangerColor,
                size: 26,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Final Confirmation',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 13.5,
                  height: 1.45,
                ),
                children: const [
                  TextSpan(text: 'Please type '),
                  TextSpan(
                    text: 'DELETE',
                    style: TextStyle(
                      color: dangerColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' below to permanently erase your account and all data.',
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
              decoration: InputDecoration(
                hintText: 'DELETE',
                hintStyle: TextStyle(
                  color: AppColors.textLightOf(context),
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF141920)
                    : const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: dangerColor,
                    width: 1.8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pop(context, false),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textPrimaryOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _isValid ? 1.0 : 0.4,
                    child: InkWell(
                      onTap: _isValid
                          ? () {
                              HapticFeedback.heavyImpact();
                              Navigator.pop(context, true);
                            }
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: dangerColor,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _isValid
                              ? [
                                  BoxShadow(
                                    color: dangerColor.withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: const Text(
                          'Delete Everything',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernPasswordDialog extends StatefulWidget {
  const _ModernPasswordDialog();

  @override
  State<_ModernPasswordDialog> createState() => _ModernPasswordDialogState();
}

class _ModernPasswordDialogState extends State<_ModernPasswordDialog> {
  late final TextEditingController _controller;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pwd = _controller.text;
    if (pwd.isNotEmpty) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, pwd);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    const dangerColor = Color(0xFFEF4444);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: dangerColor.withValues(alpha: 0.3),
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
                color: dangerColor.withValues(alpha: isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: dangerColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: dangerColor,
                size: 26,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Confirm Password',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please enter your account password to authorize permanent deletion.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondaryOf(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Your password',
                hintStyle: TextStyle(
                  color: AppColors.textLightOf(context),
                  fontWeight: FontWeight.normal,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF141920)
                    : const Color(0xFFF8FAFC),
                prefixIcon: const Icon(
                  Icons.key_rounded,
                  size: 20,
                  color: dangerColor,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppColors.textSecondaryOf(context),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: dangerColor,
                    width: 1.8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textPrimaryOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _submit,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: dangerColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: dangerColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Delete Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
