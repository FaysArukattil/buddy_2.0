import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/Network_services.dart';

/// An elegant, non-intrusive floating banner that notifies the user
/// when internet connection is lost and confirms when back online.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _wasOffline = false;
  bool _showOnlineRestored = false;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    NetworkHelper.isOnline.addListener(_onConnectivityChanged);
    // If initially offline
    if (!NetworkHelper.isOnline.value) {
      _wasOffline = true;
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    NetworkHelper.isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    final isOnline = NetworkHelper.isOnline.value;

    if (!isOnline) {
      _dismissTimer?.cancel();
      setState(() {
        _wasOffline = true;
        _showOnlineRestored = false;
      });
    } else if (_wasOffline) {
      // Transitioned from offline to online
      setState(() {
        _showOnlineRestored = true;
      });
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) {
          setState(() {
            _showOnlineRestored = false;
            _wasOffline = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NetworkHelper.isOnline,
      builder: (context, isOnline, _) {
        final shouldShow = !isOnline || _showOnlineRestored;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, animation) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: shouldShow
              ? SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Center(
                      child: GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          await NetworkHelper.checkConnection();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: !isOnline
                                ? const Color(0xFF1E293B).withValues(alpha: 0.95)
                                : const Color(0xFF064E3B).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: !isOnline
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                                  : const Color(0xFF10B981).withValues(alpha: 0.5),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 12,
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
                                color: !isOnline
                                    ? const Color(0xFFFBBF24)
                                    : const Color(0xFF34D399),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                !isOnline
                                    ? "You're offline • Working locally"
                                    : "Back online • Syncing changes",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              if (!isOnline) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Check',
                                    style: TextStyle(
                                      color: Color(0xFFFBBF24),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}
