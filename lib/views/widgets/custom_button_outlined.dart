// lib/views/widgets/custom_button_outlined.dart
import 'package:flutter/material.dart';
import 'package:buddy/utils/colors.dart';

class CustomButtonOutlined extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final double borderRadius;
  final Widget? icon;
  final Color? borderColor;
  final Color? textColor;

  const CustomButtonOutlined({
    super.key,
    required this.text,
    required this.onPressed,
    this.borderRadius = 8.0,
    this.icon,
    this.borderColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: borderColor ?? AppColors.textSecondary.withValues(alpha: .3),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          backgroundColor: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 12)],
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor ?? AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
