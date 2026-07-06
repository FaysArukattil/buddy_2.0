import 'package:flutter/material.dart';
import 'package:buddy/utils/format_utils.dart';

class AnimatedMoneyText extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final bool showSign;
  final bool compact;
  final Duration duration;

  const AnimatedMoneyText({
    super.key,
    required this.value,
    this.style,
    this.showSign = false,
    this.compact = false,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        final sign = showSign ? (value >= 0 ? '+' : '-') : '';
        final formatted = compact
            ? FormatUtils.formatCurrency(animatedValue.abs(), compact: true)
            : FormatUtils.formatCurrencyFull(animatedValue.abs());
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '$sign$formatted',
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
