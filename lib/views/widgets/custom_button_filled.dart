import 'package:flutter/material.dart';
import 'package:buddy/utils/colors.dart';

class CustomButtonFilled extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final double? width;
  final double height;
  final double borderRadius;
  final Gradient? gradient;
  final Color? backgroundColor;
  final TextStyle? textStyle;

  const CustomButtonFilled({
    super.key,
    required this.text,
    required this.onPressed,
    this.width,
    this.height = 56,
    this.borderRadius = 16,
    this.gradient,
    this.backgroundColor,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.primaryGradient,
        color: gradient == null ? backgroundColor : null,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: Text(
          text,
          style:
              textStyle ??
              const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textWhite,
              ),
        ),
      ),
    );
  }
}
