import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

/// A custom sliver refresh control that displays a dynamic coin animation
/// that smoothly rotates as you drag, turns and shines in the opposite direction
/// when released/refreshing, and smoothly fades out instead of abruptly disappearing.
class BuddyRefreshControl extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Color? backgroundColor;
  final double size;
  final double refreshTriggerPullDistance;
  final double refreshIndicatorExtent;

  final double topPadding;

  const BuddyRefreshControl({
    super.key,
    required this.onRefresh,
    this.backgroundColor,
    this.size = 46,
    this.refreshTriggerPullDistance = 90.0,
    this.refreshIndicatorExtent = 60.0,
    this.topPadding = 0.0,
  });

  @override
  State<BuddyRefreshControl> createState() => _BuddyRefreshControlState();
}

class _BuddyRefreshControlState extends State<BuddyRefreshControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  bool _hasHapticTriggered = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoSliverRefreshControl(
      refreshTriggerPullDistance: widget.refreshTriggerPullDistance + widget.topPadding,
      refreshIndicatorExtent: widget.refreshIndicatorExtent + widget.topPadding,
      onRefresh: () async {
        if (!_spinController.isAnimating) {
          _spinController.repeat();
        }
        try {
          await widget.onRefresh();
        } finally {
          // Keep spinning for a brief aesthetic moment so user sees it finish smoothly
          await Future.delayed(const Duration(milliseconds: 320));
          if (mounted) {
            _spinController.stop();
          }
        }
      },
      builder: (
        BuildContext context,
        RefreshIndicatorMode refreshState,
        double pulledExtent,
        double refreshTriggerPullDistance,
        double refreshIndicatorExtent,
      ) {
        if (refreshState == RefreshIndicatorMode.inactive) {
          _hasHapticTriggered = false;
          if (_spinController.isAnimating) {
            _spinController.stop();
          }
          return const SizedBox.shrink();
        }

        if (refreshState == RefreshIndicatorMode.armed && !_hasHapticTriggered) {
          _hasHapticTriggered = true;
          HapticFeedback.mediumImpact();
          if (!_spinController.isAnimating) {
            _spinController.repeat();
          }
        } else if (refreshState == RefreshIndicatorMode.drag) {
          _hasHapticTriggered = false;
        }

        final double effectivePullDistance = math.max(
          1.0,
          refreshTriggerPullDistance - widget.topPadding,
        );
        final double effectivePulled = math.max(
          0.0,
          pulledExtent - widget.topPadding,
        );
        final double progress =
            (effectivePulled / effectivePullDistance).clamp(0.0, 1.0);
        final bool isRefreshing = refreshState == RefreshIndicatorMode.refresh ||
            refreshState == RefreshIndicatorMode.armed;
        final bool isDone = refreshState == RefreshIndicatorMode.done;

        return Container(
          color: widget.backgroundColor ?? Colors.transparent,
          alignment: Alignment.center,
          padding: EdgeInsets.only(top: widget.topPadding, bottom: 8),
          child: AnimatedBuilder(
            animation: _spinController,
            builder: (context, child) {
              // Dragging rotates clockwise with finger pull.
              // Releasing / refreshing smoothly turns in the opposite (counter-clockwise) direction with shine.
              final double rotationAngle = isRefreshing
                  ? -(_spinController.value * 2 * math.pi)
                  : (progress * math.pi * 1.5);

              // Shimmer / pulse shine factor
              final double shineFactor = isRefreshing
                  ? (0.5 + 0.5 * math.sin(_spinController.value * 2 * math.pi))
                  : (progress * 0.4);

              return AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                opacity: isDone ? 0.0 : (isRefreshing ? 1.0 : (0.2 + 0.8 * progress)),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutBack,
                  scale: isDone ? 0.4 : (isRefreshing ? 1.0 : (0.55 + 0.45 * progress)),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD54F).withValues(
                            alpha: 0.25 + 0.35 * shineFactor,
                          ),
                          blurRadius: 16 + 10 * shineFactor,
                          spreadRadius: 2 + 2 * shineFactor,
                        ),
                      ],
                    ),
                    child: Transform.rotate(
                      angle: rotationAngle,
                      child: BuddyLoadingIndicator(size: widget.size),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
