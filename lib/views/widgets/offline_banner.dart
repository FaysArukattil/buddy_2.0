import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/Network_services.dart';
import '../../utils/colors.dart';

/// An elegant, theme-adaptive floating offline indicator.
///
/// Features:
/// - Initially displays a smooth popup pill when offline.
/// - Automatically collapses after 3.5s into a subtle corner network cut icon
///   so the screen content remains unobscured.
/// - Tapping the corner cut icon re-expands the popup banner.
/// - Smoothly shifts to a green "Back online" pill when connectivity returns,
///   then dismisses completely.
/// - Adapts colors dynamically based on Light / Dark theme.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _wasOffline = false;
  bool _showOnlineRestored = false;
  bool _isExpanded = true;
  Timer? _dismissTimer;
  Timer? _collapseTimer;

  @override
  void initState() {
    super.initState();
    NetworkHelper.isOnline.addListener(_onConnectivityChanged);
    // If initially offline, show popup then auto-collapse
    if (!NetworkHelper.isOnline.value) {
      _wasOffline = true;
      _isExpanded = true;
      _startCollapseTimer();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _collapseTimer?.cancel();
    NetworkHelper.isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _startCollapseTimer({int milliseconds = 3500}) {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(Duration(milliseconds: milliseconds), () {
      if (mounted && !NetworkHelper.isOnline.value) {
        setState(() {
          _isExpanded = false;
        });
      }
    });
  }

  void _onConnectivityChanged() {
    final isOnline = NetworkHelper.isOnline.value;

    if (!isOnline) {
      _dismissTimer?.cancel();
      setState(() {
        _wasOffline = true;
        _showOnlineRestored = false;
        _isExpanded = true;
      });
      _startCollapseTimer();
    } else if (_wasOffline) {
      // Transitioned from offline to online
      _collapseTimer?.cancel();
      setState(() {
        _showOnlineRestored = true;
        _isExpanded = true;
      });
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) {
          setState(() {
            _showOnlineRestored = false;
            _wasOffline = false;
            _isExpanded = true;
          });
        }
      });
    }
  }

  void _expandTemporarily() {
    HapticFeedback.lightImpact();
    setState(() {
      _isExpanded = true;
    });
    _startCollapseTimer(milliseconds: 4000);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return ValueListenableBuilder<bool>(
      valueListenable: NetworkHelper.isOnline,
      builder: (context, isOnline, _) {
        final shouldShow = !isOnline || _showOnlineRestored;
        if (!shouldShow) return const SizedBox.shrink();

        // ── Theme-aware color palette ──
        final Color offlineBg = isDark
            ? const Color(0xFF1E2632).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.96);
        final Color onlineBg = isDark
            ? const Color(0xFF0F2B25).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.96);

        final Color offlineBorder = isDark
            ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
            : const Color(0xFFD97706).withValues(alpha: 0.35);
        final Color onlineBorder = isDark
            ? const Color(0xFF10B981).withValues(alpha: 0.45)
            : const Color(0xFF059669).withValues(alpha: 0.35);

        final Color offlineAccent =
            isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
        final Color onlineAccent =
            isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

        final Color textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);

        final currentBg = !isOnline ? offlineBg : onlineBg;
        final currentBorder = !isOnline ? offlineBorder : onlineBorder;
        final currentAccent = !isOnline ? offlineAccent : onlineAccent;

        return SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.4),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _isExpanded
                // ── Full Pill Banner ──
                ? Padding(
                    key: const ValueKey('full_pill_banner'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Center(
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          await NetworkHelper.checkConnection();
                          if (!NetworkHelper.isOnline.value) {
                            _startCollapseTimer(milliseconds: 2500);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: currentBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: currentBorder,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.30 : 0.10,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                !isOnline
                                    ? Icons.cloud_off_rounded
                                    : Icons.cloud_done_rounded,
                                size: 16,
                                color: currentAccent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                !isOnline
                                    ? "You're offline • Working locally"
                                    : "Back online • Syncing changes",
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              if (!isOnline) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: offlineAccent.withValues(
                                      alpha: isDark ? 0.20 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Check',
                                    style: TextStyle(
                                      color: offlineAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _isExpanded = false);
                                  },
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                // ── Sleek Collapsed Corner Icon Badge ──
                : Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                      child: GestureDetector(
                        key: const ValueKey('corner_cut_icon'),
                        onTap: _expandTemporarily,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: currentBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: currentBorder,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.08,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.cloud_off_rounded,
                              size: 17,
                              color: currentAccent,
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
