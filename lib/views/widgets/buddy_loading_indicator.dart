import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A reusable loading indicator widget that uses the coin Lottie animation
/// from the splash screen. Uses a bundled asset so it works offline.
///
/// Usage:
/// ```dart
/// const BuddyLoadingIndicator()                   // default 48×48
/// BuddyLoadingIndicator(size: 32)                  // small inline
/// BuddyLoadingIndicator(size: 80)                  // large centered
/// BuddyLoadingIndicator.centered()                 // centered in parent
/// BuddyLoadingIndicator.centered(size: 64)         // centered, custom size
/// ```
class BuddyLoadingIndicator extends StatelessWidget {
  /// The width and height of the animation.
  final double size;

  const BuddyLoadingIndicator({super.key, this.size = 48});

  /// Returns a [Center]-wrapped loading indicator — handy for full-screen
  /// loading states and [SliverFillRemaining] bodies.
  static Widget centered({double size = 56, Key? key}) {
    return Center(
      key: key,
      child: BuddyLoadingIndicator(size: size),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        'assets/lottie/jsonlottie/Coinlottie.json',
        fit: BoxFit.contain,
        repeat: true,
        // No need for a network call — this is a bundled asset,
        // so it works fully offline.
      ),
    );
  }
}
